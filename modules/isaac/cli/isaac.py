"""Explicit local Isaac installation and execution inside the Nix FHS environment."""

import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def save(target, value):
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".isaac-", dir=target.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, target)
        directory = os.open(target.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def digest(target):
    with target.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def run(argv, **kwargs):
    return subprocess.run(argv, check=True, **kwargs)


def validate(state, name, commands, cwd=None):
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    report = state / "validation" / (stamp + "-" + name + ".json")
    log_file = report.with_suffix(".log")
    report.parent.mkdir(parents=True, exist_ok=True)
    result = {"stage": name, "status": "failed", "commands": commands, "log": str(log_file)}
    print(f"Validating {name}: {log_file}", flush=True)
    try:
        with log_file.open("w") as log:
            for command in commands:
                run(command, cwd=cwd, stdout=log, stderr=subprocess.STDOUT)
        if name in {"cuda", "sim", "gui", "cartpole", "quadruped"}:
            log_text = log_file.read_text(errors="replace")
            if "Failed to startup python extension" in log_text:
                raise ValueError(f"A required Kit extension failed to start; inspect {log_file}")
            markers = []
            for line in log_text.splitlines():
                try:
                    value = json.loads(line)
                except ValueError:
                    continue
                if (
                    isinstance(value, dict)
                    and value.get("stage") == name
                    and value.get("status") == "passed"
                ):
                    markers.append(value)
            if not markers:
                raise ValueError(
                    f"{name} exited without its successful validation marker; inspect {log_file}"
                )
            result["evidence"] = markers[-1]
        result["status"] = "passed"
    except subprocess.CalledProcessError as error:
        result["exitCode"] = error.returncode
        raise
    finally:
        save(report, result)
        print(json.dumps(result), flush=True)


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in {"setup", "run", "sim", "doctor", "status"}:
        raise ValueError("Expected setup, run, sim, doctor or status")
    action = sys.argv[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--accept-eula",
        action="store_true",
        help="Accept https://docs.omniverse.nvidia.com/eula for this installation",
    )
    parser.add_argument("--workspace", type=Path, default=Path.home() / "Workspace/isaac/IsaacLab")
    parser.add_argument(
        "--stage",
        choices=["preflight", "cuda", "sim", "gui", "cartpole", "quadruped"],
        default="preflight",
    )
    if action in {"run", "sim"}:
        parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args(sys.argv[2:])
    version = json.loads(Path(os.environ["ISAAC_VERSIONS"]).read_text())
    data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "folio/isaac"
    state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "folio/isaac"
    state.mkdir(parents=True, exist_ok=True)
    cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "folio/isaac"
    os.environ.setdefault("UV_CACHE_DIR", str(cache / "uv"))
    os.environ["UV_PYTHON_DOWNLOADS"] = "never"
    os.environ["UV_PYTHON_PREFERENCE"] = "only-system"
    os.environ["PYTHONUNBUFFERED"] = "1"
    active_file = data / "active.json"
    active = json.loads(active_file.read_text()) if active_file.exists() else None
    if action == "status":
        print(json.dumps({"profile": version, "active": active}, indent=2))
        return
    if action == "setup":
        with (state / "install.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            workspace = args.workspace.expanduser().absolute()
            if not workspace.is_absolute() or workspace.is_symlink():
                raise ValueError("Use an absolute workspace directory without a symlink")
            if not workspace.exists():
                workspace.parent.mkdir(parents=True, exist_ok=True)
                run(
                    [
                        "git",
                        "clone",
                        "--branch",
                        "v" + version["isaaclab"],
                        "--depth",
                        "1",
                        version["repository"],
                        str(workspace),
                    ]
                )
            actual = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=workspace, text=True
            ).strip()
            if (
                actual != version["commit"]
                or digest(workspace / "uv.lock") != version["lockSha256"]
            ):
                raise ValueError(
                    "Source commit/lock differs from the reviewed profile; refusing to overwrite it"
                )
            dirty = subprocess.check_output(
                ["git", "status", "--porcelain", "--untracked-files=no"], cwd=workspace, text=True
            ).strip()
            if dirty:
                raise ValueError(
                    "Source checkout has modifications; use a separate checkout for installation"
                )
            # A failed candidate can be resumed; another version always gets another directory.
            candidate_name = version["profile"]
            if active and active.get("environment") == str(data / "environments" / candidate_name):
                candidate_name += "-" + datetime.datetime.now(datetime.timezone.utc).strftime(
                    "%Y%m%dT%H%M%S%f"
                )
            environment = data / "environments" / candidate_name
            if environment.is_symlink():
                raise ValueError("Environment directory must not be a symlink")
            os.environ["UV_PROJECT_ENVIRONMENT"] = str(environment)
            command = ["uv", "sync", "--frozen", "--python", "/usr/bin/python3.12"]
            kit_wheel = (
                cache / "wheels/isaacsim_extscache_kit-6.2.0.0-cp312-none-manylinux_2_35_x86_64.whl"
            )
            local_kit = kit_wheel.is_file() and not Path(str(kit_wheel) + ".aria2").exists()
            if local_kit:
                if digest(kit_wheel) != version["kitWheelSha256"]:
                    raise ValueError("Local Kit wheel does not match the upstream lock SHA-256")
                command.extend(["--no-install-package", "isaacsim-extscache-kit"])
            for extra in version["extras"]:
                command.extend(["--extra", extra])
            log_file = state / "install.log"
            with log_file.open("a") as log:
                print(f"Installation output: {log_file}", flush=True)
                run(command, cwd=workspace, stdout=log, stderr=subprocess.STDOUT)
            python = str(environment / "bin/python")
            if local_kit:
                run(
                    [
                        "uv",
                        "pip",
                        "install",
                        "--python",
                        python,
                        "--no-deps",
                        "--no-index",
                        str(kit_wheel),
                    ]
                )
            compatibility = Path(os.environ["ISAAC_COMPATIBILITY"])
            if digest(compatibility) != version["compatibilitySha256"]:
                raise ValueError("Compatibility overlay digest differs from the reviewed profile")
            run(["uv", "pip", "uninstall", "--python", python, "onnxruntime"])
            run(
                [
                    "uv",
                    "pip",
                    "install",
                    "--python",
                    python,
                    "--no-deps",
                    "--require-hashes",
                    "-r",
                    str(compatibility),
                ]
            )
            # Keep the raw metadata report. Isaac Lab intentionally overrides several
            # exact Sim requirements; validate those against its reviewed overrides.
            with (state / "dependency-metadata.log").open("w") as log:
                subprocess.run(
                    ["uv", "pip", "check", "--python", python],
                    stdout=log,
                    stderr=subprocess.STDOUT,
                    check=False,
                )
            validate(
                state,
                "dependencies",
                [[python, os.environ["ISAAC_VALIDATION_SCRIPTS"] + "/dependencies.py"]],
                cwd=workspace,
            )
            validate(state, "cuda", [[python, os.environ["ISAAC_VALIDATION_SCRIPTS"] + "/cuda.py"]])
            if not args.accept_eula:
                raise ValueError(
                    "Dependencies prepared. Re-run setup --accept-eula after reviewing the NVIDIA EULA;"
                    " the active environment has not been changed"
                )
            os.environ["OMNI_KIT_ACCEPT_EULA"] = "yes"
            validate(
                state,
                "sim",
                [[python, os.environ["ISAAC_VALIDATION_SCRIPTS"] + "/sim.py"]],
                cwd=workspace,
            )
            manifest = {
                "profile": version,
                "workspace": str(workspace),
                "environment": str(environment),
                "acceptedEula": "https://docs.omniverse.nvidia.com/eula",
                "runtime": os.environ["ISAAC_RUNTIME"],
                "validatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "stages": ["cuda", "sim"],
            }
            roots = data / "roots"
            roots.mkdir(parents=True, exist_ok=True)
            run(
                [
                    "nix-store",
                    "--add-root",
                    str(roots / candidate_name),
                    "--indirect",
                    "--realise",
                    os.environ["ISAAC_RUNTIME"],
                ]
            )
            save(data / "manifests" / (candidate_name + ".json"), manifest)
            save(active_file, manifest)
            print(f"Validated active environment: {environment}")
            return
    if action == "doctor" and args.stage == "preflight":
        validate(
            state,
            "preflight",
            [["/run/current-system/sw/bin/nvidia-smi"], ["vulkaninfo", "--summary"]],
        )
        return
    if active is None:
        raise ValueError("No validated environment. Run isaac-setup first")
    if active["profile"] != version:
        raise ValueError("Active environment profile differs from this launcher")
    workspace = Path(active["workspace"])
    if digest(workspace / "uv.lock") != version["lockSha256"]:
        raise ValueError(
            "Active environment lock changed; verify the research environment explicitly"
        )
    os.environ.update(UV_PROJECT_ENVIRONMENT=active["environment"], OMNI_KIT_ACCEPT_EULA="yes")
    if action == "doctor":
        script = "training" if args.stage in {"cartpole", "quadruped"} else args.stage
        if args.stage == "gui":
            script = "sim"
        command = [
            active["environment"] + "/bin/python",
            os.environ["ISAAC_VALIDATION_SCRIPTS"] + f"/{script}.py",
        ]
        if script == "training":
            command.append(args.stage)
        if args.stage == "gui":
            capture = (
                state
                / "validation"
                / (datetime.datetime.now().strftime("%Y%m%dT%H%M%S") + "-viewport.png")
            )
            command.extend(["--gui", "--screenshot", str(capture)])
        validate(state, args.stage, [command], cwd=workspace)
        return
    arguments = args.arguments
    if arguments and arguments[0] == "--":
        arguments = arguments[1:]
    if not arguments and action == "run":
        arguments = ["--help"]
    os.chdir(workspace)
    executable = "isaacsim" if action == "sim" else "isaaclab"
    os.execvp("uv", ["uv", "run", "--no-sync", executable, *arguments])


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Isaac: {error}", file=sys.stderr)
        sys.exit(1)
