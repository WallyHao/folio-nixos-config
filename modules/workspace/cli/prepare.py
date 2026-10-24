"""Interactive, English workspace preparation, following Folio CLI colors."""

import argparse
import concurrent.futures
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys

from folio_workspace_health import (
    connectivity_check,
    privileged_disk_check,
    privileged_repair,
    report,
    finding,
    restart_failed,
    safe_check,
    service_check,
    time_check,
)


class Console:
    colors = {"heading": "1;36", "success": "1;32", "warning": "33", "error": "31", "info": "2"}

    def paint(self, value, tone):
        if not sys.stdout.isatty() or "NO_COLOR" in os.environ or os.environ.get("TERM") == "dumb":
            return value
        return f"\033[{self.colors.get(tone, '2')}m{value}\033[0m"

    def say(self, message, tone="info"):
        message = "".join(char if char.isprintable() else " " for char in str(message))
        label = {"success": " OK ", "warning": "WARN", "error": "FAIL", "heading": "STEP"}.get(
            tone, "INFO"
        )
        print(f"{self.paint('[' + label + ']', tone)} {message}", flush=True)


def backend(action, console):
    args = ["sudo", "-n", "--", "/run/current-system/sw/bin/folio-workspace-system", action]
    if action == "cleanup":
        args.append("--apply")
    with subprocess.Popen(
        args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, text=True
    ) as process:
        for line in process.stdout:
            try:
                message = json.loads(line)
                console.say(message["message"], message.get("tone", "info"))
            except (ValueError, KeyError, TypeError):
                console.say(line.strip())
        code = process.wait()
    if code:
        console.say(f"{action.capitalize()} failed (exit {code}).", "error")
    return code


def approved(console, question):
    if not sys.stdin.isatty():
        return False
    try:
        return input(console.paint(question + " [y/N] ", "warning")).strip().lower() in {"y", "yes"}
    except EOFError:
        return False


def display(console, result):
    console.say(result["name"], "heading")
    for item in result["findings"]:
        console.say(item["message"], item["tone"])


def status(result):
    tones = {item["tone"] for item in result["findings"]}
    return "FAIL" if "error" in tones else "WARN" if "warning" in tones else "PASS"


def automatic_checks(console):
    console.say("1/4  Network initialization + parallel local checks", "heading")
    console.say(
        "Automatic: storage/mounts, system/user services, and clock status run alongside network setup."
    )
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        pending = [
            executor.submit(safe_check, name, operation)
            for name, operation in (
                ("Storage and mounts", privileged_disk_check),
                ("Service health", service_check),
                ("Time synchronization", time_check),
            )
        ]
        network_ready = backend("network", console) == 0
        reports = [future.result() for future in pending]
    console.say("2/4  Automatic health results", "heading")
    if network_ready:
        console.say("Network is stable; checking DNS / VPN / GitHub / Nix cache in parallel.")
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            connectivity = executor.submit(
                safe_check, "DNS and service connectivity", connectivity_check
            )
            clock = None
            if not reports[2]["data"].get("synchronized"):
                clock = executor.submit(safe_check, "Time synchronization", time_check, wait=8)
            if clock is not None:
                reports[2] = clock.result()
            reports.append(connectivity.result())
    else:
        reports.append(
            report(
                "DNS and service connectivity",
                [
                    finding(
                        "Skipped: Wi-Fi / VPN initialization failed; local health checks still completed.",
                        "warning",
                    )
                ],
            )
        )
    for result in reports:
        display(console, result)
    return network_ready, reports


def optional_repairs(console, reports):
    console.say("3/4  Optional repairs (confirmation required)", "heading")
    failed = reports[1]["data"].get("failed", [])
    changed = False
    repairs = []
    if failed and approved(console, "Restart the failed services listed above?"):
        for scope in ("system", "user"):
            units = [entry["unit"] for entry in failed if entry["scope"] == scope]
            # Bound each privileged request, even for unusually large inventories.
            for start in range(0, len(units), 64):
                batch = units[start : start + 64]
                operation = (
                    (lambda: privileged_repair("repair-services", batch))
                    if scope == "system"
                    else (lambda: restart_failed("user", batch))
                )
                result = safe_check("Service repair", operation, error_tone="error")
                repairs.append(result)
                display(console, result)
        reports[1] = safe_check("Service health", service_check)
        display(console, reports[1])
        reports[2] = safe_check("Time synchronization", time_check)
        changed = True
    elif failed:
        console.say("Service restarts skipped.")
    clock = reports[2]["data"]
    if not clock.get("synchronized") and clock.get("ntp_enabled"):
        if approved(console, "Retry time synchronization by restarting systemd-timesyncd?"):
            result = safe_check(
                "Time synchronization retry", privileged_repair, "sync-time", error_tone="error"
            )
            repairs.append(result)
            display(console, result)
            reports[2] = safe_check("Time synchronization", time_check)
            display(console, reports[2])
            changed = True
        else:
            console.say("Time synchronization retry skipped.")
    if changed:
        # Restarting a network-related service or changing clock state can alter
        # endpoint reachability. Report current observations after repairs.
        reports[3] = safe_check("DNS and service connectivity", connectivity_check)
        display(console, reports[3])
    return repairs


def session(console):
    network_ready, reports = automatic_checks(console)
    if not network_ready:
        console.say(
            "Preparation stopped. Review local results, resolve the network error and run folio prepare.",
            "error",
        )
        return 1
    repairs = []
    if sys.stdin.isatty():
        repairs = optional_repairs(console, reports)
    else:
        console.say(
            "3/4  Optional repairs skipped: interactive confirmation is required.", "warning"
        )
    console.say("4/4  Optional storage cleanup", "heading")
    console.say(
        "Keep three system generations, refresh the boot menu, and collect unreferenced Nix store paths."
    )
    console.say(
        "Active / booted systems, Home Manager generations, Folio recovery records and personal files are preserved."
    )
    if not reports[0]["data"].get("cleanup_safe", False):
        console.say(
            "Storage cleanup skipped: mount verification failed or is unavailable.", "warning"
        )
    elif not sys.stdin.isatty():
        console.say("Storage cleanup skipped: interactive confirmation is required.", "warning")
    elif approved(console, "Run storage cleanup?"):
        if backend("cleanup", console):
            return 1
        reports[0] = safe_check("Storage and mounts", privileged_disk_check)
        display(console, reports[0])
    else:
        console.say("Storage cleanup skipped.")
    summary = [f"{item['name']}={status(item)}" for item in reports]
    if repairs:
        repair_state = (
            "FAIL"
            if any(status(item) == "FAIL" for item in repairs)
            else ("WARN" if any(status(item) == "WARN" for item in repairs) else "PASS")
        )
        summary.append(f"Optional repairs={repair_state}")
    console.say("Health summary: " + "; ".join(summary) + ".")
    failed = any(status(item) == "FAIL" for item in reports + repairs)
    warned = any(status(item) == "WARN" for item in reports)
    console.say(
        "Workspace preparation finished with health errors."
        if failed
        else "Workspace preparation complete; review the warnings above."
        if warned
        else "Workspace preparation complete.",
        "error" if failed else "warning" if warned else "success",
    )
    return 1 if failed else 0


def main():
    if os.environ.get("FOLIO_JSON") == "true":
        print(
            json.dumps(
                {
                    "status": "invalid",
                    "data": None,
                    "error": "Workspace preparation requires human-readable interactive mode; omit --json.",
                    "taskId": None,
                }
            )
        )
        return 2
    parser = argparse.ArgumentParser(
        description="Prepare networking, run automatic health checks, then offer repairs and cleanup."
    )
    parser.add_argument(
        "--boot", action="store_true", help="Run once per boot, after graphical login"
    )
    parser.add_argument(
        "--pause", action="store_true", help="Wait for Enter before closing the terminal"
    )
    args = parser.parse_args()
    console = Console()
    code = 1
    try:
        runtime = Path(os.environ["XDG_RUNTIME_DIR"])
        with (runtime / "folio-workspace.lock").open("w") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                console.say("Workspace preparation is already running.", "warning")
                return 0
            marker = runtime / "folio-workspace.boot"
            boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
            if args.boot and marker.exists() and marker.read_text() == boot:
                return 0
            if args.boot:
                marker.write_text(boot)
            console.say("Folio Workspace Preparation", "heading")
            code = session(console)
    except KeyboardInterrupt:
        console.say("Workspace preparation interrupted.", "warning")
        code = 130
    except (OSError, KeyError) as error:
        console.say(f"Preparation unavailable: {error}", "error")
    if args.pause and sys.stdin.isatty():
        try:
            input("Press Enter to close this terminal. ")
        except (EOFError, KeyboardInterrupt):
            pass
    return code


if __name__ == "__main__":
    sys.exit(main())
