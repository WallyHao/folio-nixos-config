"""Fixed privileged operations; cleanup is reachable only with --apply."""

import contextlib
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

from folio_workspace_health import disk_check, restart_failed, retry_time_sync, safe_check


PROFILE = Path("/nix/var/nix/profiles/system")


def event(message, tone="info"):
    print(json.dumps({"message": message, "tone": tone}), flush=True)


def run(args):
    result = subprocess.run(
        args, capture_output=True, text=True, timeout=1800, stdin=subprocess.DEVNULL
    )
    for line in (result.stdout + result.stderr).splitlines():
        event(line)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed (exit {result.returncode}); cleanup stopped.")
    return result.stdout


def deletion_candidates(generations, protected, count=3):
    retained = set(protected)
    for generation in sorted(generations, reverse=True):
        if len(retained) >= count:
            break
        retained.add(generation)
    return sorted(set(generations) - retained)


def cleanup():
    if not disk_check()["data"].get("cleanup_safe"):
        raise RuntimeError("Mount verification failed; repair mounts before storage cleanup.")
    # Match the manager's lock order so queued deployments cannot be activated
    # while their system generations and boot entries are being pruned.
    with contextlib.ExitStack() as stack:
        for path in ("/var/lib/folio/deployments/queue.lock", "/var/lib/folio/mutation.lock"):
            lock = stack.enter_context(open(path, "a"))
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        before = shutil.disk_usage("/nix").free
        event("Inspecting system generations.")
        listing = run(["nix-env", "--profile", str(PROFILE), "--list-generations"])
        generations = [
            int(match.group(1))
            for line in listing.splitlines()
            if (match := re.match(r"^\s*(\d+)\s", line))
        ]
        if not generations:
            raise RuntimeError("No system generations found; refusing cleanup.")
        targets = {PROFILE.resolve(strict=True)}
        for path in ("/run/current-system", "/run/booted-system"):
            if Path(path).exists():
                targets.add(Path(path).resolve(strict=True))
        protected = set()
        for target in targets:
            matches = [
                generation
                for generation in generations
                if PROFILE.with_name(f"system-{generation}-link").resolve(strict=True) == target
            ]
            if matches:
                protected.add(max(matches))
        selected = deletion_candidates(generations, protected)
        event("Removing system generations: " + (", ".join(map(str, selected)) or "none") + ".")
        if selected:
            run(["nix-env", "--profile", str(PROFILE), "--delete-generations", *map(str, selected)])
        # Refresh before GC; do not activate a different generation.
        event("Refreshing boot entries.")
        run([str(PROFILE / "bin/switch-to-configuration"), "boot"])
        event("Collecting unreferenced Nix store paths; recovery roots remain protected.")
        run(["nix-store", "--gc"])
        reclaimed = max(0, shutil.disk_usage("/nix").free - before)
        event(
            f"Storage cleanup complete; available space increased by {reclaimed / 1024**3:.2f} GiB.",
            "success",
        )


def main():
    if os.geteuid() != 0:
        event("This operation requires the installed privileged helper.", "error")
        return 1
    action = sys.argv[1:]
    if action not in (
        ["network"],
        ["disk-check"],
        ["repair-services", "--apply"],
        ["sync-time", "--apply"],
        ["cleanup", "--apply"],
    ):
        event(
            "Usage: folio-workspace-system network | disk-check | repair-services --apply | sync-time --apply | cleanup --apply",
            "error",
        )
        return 2
    try:
        if action == ["disk-check"]:
            print(json.dumps(safe_check("Storage and mounts", disk_check)))
            return 0
        with open("/run/lock/folio-workspace.lock", "a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            if action == ["network"]:
                return subprocess.call(["folio-network-prepare"], stdin=subprocess.DEVNULL)
            if action == ["repair-services", "--apply"]:
                request = sys.stdin.read(65537)
                if len(request) > 65536:
                    raise ValueError("Service repair request is too large")
                result = restart_failed("system", json.loads(request)["units"])
                print(json.dumps(result))
            elif action == ["sync-time", "--apply"]:
                print(json.dumps(retry_time_sync()))
            else:
                cleanup()
        return 0
    except (
        OSError,
        ValueError,
        KeyError,
        TypeError,
        RuntimeError,
        subprocess.TimeoutExpired,
    ) as error:
        event(f"Operation failed: {error}", "error")
        return 1


if __name__ == "__main__":
    sys.exit(main())
