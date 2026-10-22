"""Check failure isolation and exact argument forwarding without installing Isaac."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    workspace = root / "source with spaces"
    workspace.mkdir()
    (workspace / "uv.lock").write_text("fixture lock\n")
    version = {"profile": "fixture", "lockSha256": hashlib.sha256(b"fixture lock\n").hexdigest()}
    (root / "versions.json").write_text(json.dumps(version))
    env = dict(os.environ, XDG_STATE_HOME=str(root / "state"), XDG_DATA_HOME=str(root / "data"),
               XDG_CACHE_HOME=str(root / "cache"), ISAAC_VERSIONS=str(root / "versions.json"))
    command = [os.environ["PYTHON"], os.environ["ISAAC_CLI"]]

    def invoke(*arguments):
        return subprocess.run([*command, *arguments], env=env, text=True, capture_output=True)

    status = invoke("status")
    assert status.returncode == 0 and json.loads(status.stdout)["active"] is None
    missing = invoke("run", "--", "isaaclab", "train")
    assert missing.returncode != 0 and "No validated environment" in missing.stderr
    active_file = root / "data/folio/isaac/active.json"
    active_file.parent.mkdir(parents=True)
    active = {"profile": version, "workspace": str(workspace), "environment": str(root / "venv")}
    active_file.write_text(json.dumps(active))
    fake_bin = root / "bin"
    fake_bin.mkdir()
    uv = fake_bin / "uv"
    uv.write_text("#!" + os.environ["PYTHON"] + "\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n")
    uv.chmod(0o755)
    env["PATH"] = str(fake_bin) + os.pathsep + env["PATH"]
    arguments = ["train", "--task", "task with spaces", "physics=isaacsim_physx"]
    forwarded = invoke("run", "--", *arguments)
    assert forwarded.returncode == 0, forwarded.stderr
    assert json.loads(forwarded.stdout) == ["run", "--no-sync", "isaaclab", *arguments]
    simulator = invoke("sim", "--", "--no-window")
    assert simulator.returncode == 0, simulator.stderr
    assert json.loads(simulator.stdout) == ["run", "--no-sync", "isaacsim", "--no-window"]
    (workspace / "uv.lock").write_text("changed")
    rejected = invoke("run", "--", "isaaclab")
    assert rejected.returncode != 0 and "lock changed" in rejected.stderr
    assert json.loads(active_file.read_text()) == active
    print("Missing installation, spaced paths, argument boundaries and lock drift passed")
    spec = importlib.util.spec_from_file_location("isaac_cli", os.environ["ISAAC_CLI"])
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    try:
        module.validate(root / "reports", "sim", [[os.environ["PYTHON"], "-c", "pass"]])
    except ValueError:
        pass
    else:
        raise AssertionError("Zero exit without a completed simulation must not pass")
    failed = list((root / "reports/validation").glob("*.json"))
    assert len(failed) == 1 and json.loads(failed[0].read_text())["status"] == "failed"
    module.validate(root / "reports", "sim", [[os.environ["PYTHON"], "-c",
                    'print(\'{"stage":"sim","status":"passed","steps":180}\')']])
    try:
        module.validate(root / "reports", "sim", [[os.environ["PYTHON"], "-c",
                        'print("Failed to startup python extension"); '
                        'print(\'{"stage":"sim","status":"passed"}\')']])
    except ValueError:
        pass
    else:
        raise AssertionError("A completed numeric check cannot hide a failed Kit extension")
    print("Early successful exit is rejected; explicit completed-stage evidence is required")
