"""Bounded read-only health checks and explicitly requested repairs."""

import concurrent.futures
import json
import os
from pathlib import Path
import re
import subprocess
import time


HELPER = "/run/current-system/sw/bin/folio-workspace-system"
CHECK_PATHS = ("/", "/home", "/nix", "/boot")
CONFIG = Path("/etc/folio/workspace-checks.json")


def finding(message, tone="info"):
    return {"message": message, "tone": tone}


def report(name, findings, **data):
    return {"name": name, "findings": findings, "data": data}


def command(args, timeout=8, check=True, input=None):
    result = subprocess.run(
        args,
        input=input,
        stdin=None if input is not None else subprocess.DEVNULL,
        capture_output=True,
        text=True,
        timeout=timeout,
        env={**os.environ, "LC_ALL": "C", "SYSTEMD_COLORS": "0"},
    )
    if check and result.returncode:
        raise RuntimeError(f"{args[0]} exited with status {result.returncode}")
    return result


def safe_check(name, operation, *args, error_tone="warning", **kwargs):
    try:
        return operation(*args, **kwargs)
    except (
        OSError,
        ValueError,
        KeyError,
        TypeError,
        RuntimeError,
        subprocess.TimeoutExpired,
    ) as error:
        label = "Repair failed" if error_tone == "error" else "Check unavailable"
        return report(name, [finding(f"{label}: {error}", error_tone)])


def properties(text):
    return dict(line.split("=", 1) for line in text.splitlines() if "=" in line)


def flatten_mounts(rows):
    for row in rows:
        yield row
        yield from flatten_mounts(row.get("children", []))


def containing_mount(path, mounts):
    matches = [
        row
        for row in mounts
        if path == row["target"] or path.startswith(row["target"].rstrip("/") + "/")
    ]
    return max(matches, key=lambda row: len(row["target"])) if matches else None


def disk_check():
    config = json.loads(CONFIG.read_text())
    expected = config["mounts"]
    if not any(row.get("target") == "/" for row in expected):
        raise ValueError("Declared root mount is missing from workspace configuration")
    inventory = json.loads(
        command(
            ["findmnt", "--json", "--list", "--output", "TARGET,SOURCE,FSTYPE,OPTIONS,FSROOT"]
        ).stdout
    )
    mounted = list(flatten_mounts(inventory["filesystems"]))
    findings, cleanup_safe = [], True
    for path in CHECK_PATHS:
        declared, actual = containing_mount(path, expected), containing_mount(path, mounted)
        problems = []
        if actual is None or declared is None:
            problems.append("no matching declared / active filesystem")
        else:
            if actual["target"] != declared["target"]:
                problems.append(f"expected mount {declared['target']}, found {actual['target']}")
            if declared["fsType"] not in ("auto", actual["fstype"]):
                problems.append(f"expected {declared['fsType']}, found {actual['fstype']}")
            device = declared.get("device", "")
            source = actual.get("source", "").split("[", 1)[0]
            if device.startswith("/dev/"):
                if os.path.realpath(device) != os.path.realpath(source):
                    problems.append("mounted device differs from declared device")
            subvol = next(
                (value[7:] for value in declared.get("options", []) if value.startswith("subvol=")),
                None,
            )
            if subvol is not None and actual.get("fsroot", "").strip("/") != subvol.strip("/"):
                problems.append("Btrfs subvolume differs from declared subvolume")
            if "ro" in actual.get("options", "").split(","):
                problems.append("filesystem is read-only")
        if problems:
            cleanup_safe = False
            findings.append(finding(f"{path}: " + "; ".join(problems) + ".", "error"))
            continue
        try:
            usage = os.statvfs(path)
            if usage.f_flag & os.ST_RDONLY:
                cleanup_safe = False
                findings.append(finding(f"{path}: filesystem is read-only.", "error"))
                continue
            free = usage.f_bavail * usage.f_frsize
            total = usage.f_blocks * usage.f_frsize
            if total <= 0:
                raise ValueError("filesystem reports zero capacity")
            ratio = free / total
            warn = (128 * 1024**2) if path == "/boot" else (5 * 1024**3)
            critical = (32 * 1024**2) if path == "/boot" else (1024**3)
            tone = (
                "error"
                if free < critical or ratio < 0.03
                else "warning"
                if free < warn or ratio < 0.1
                else "success"
            )
            findings.append(
                finding(
                    f"{path}: {free / 1024**3:.2f} GiB free ({ratio:.0%}), mount verified.", tone
                )
            )
            if usage.f_files > 0:
                inode_ratio = usage.f_favail / usage.f_files
                if inode_ratio < 0.05:
                    findings.append(
                        finding(
                            f"{path}: only {inode_ratio:.1%} of inodes remain.",
                            "error" if inode_ratio < 0.01 else "warning",
                        )
                    )
        except (OSError, ValueError) as error:
            cleanup_safe = False
            findings.append(finding(f"{path}: cannot inspect filesystem space: {error}", "error"))
    return report("Storage and mounts", findings, cleanup_safe=cleanup_safe)


def privileged_disk_check():
    result = command(["sudo", "-n", "--", HELPER, "disk-check"], timeout=15)
    data = json.loads(result.stdout)
    if not isinstance(data.get("findings"), list) or data.get("name") != "Storage and mounts":
        raise ValueError("Invalid disk check response")
    return data


def privileged_repair(action, units=None):
    payload = json.dumps({"units": units}) if units is not None else None
    result = command(
        ["sudo", "-n", "--", HELPER, action, "--apply"],
        timeout=35 * max(1, len(units or [])) + 30,
        input=payload,
    )
    data = json.loads(result.stdout)
    if not isinstance(data.get("findings"), list):
        raise ValueError("Invalid repair response")
    return data


def valid_service(unit):
    return (
        isinstance(unit, str)
        and len(unit) <= 255
        and not unit.startswith("-")
        and re.fullmatch(r"(?:[A-Za-z0-9:_.@-]|\\x[0-9a-fA-F]{2})+\.service", unit) is not None
    )


def failed_services(scope):
    data = json.loads(
        command(
            [
                "systemctl",
                f"--{scope}",
                "list-units",
                "--failed",
                "--type=service",
                "--all",
                "--output=json",
                "--no-pager",
            ]
        ).stdout
    )
    return [row["unit"] for row in data if valid_service(row.get("unit"))]


def service_check():
    findings, failed = [], []
    for scope in ("system", "user"):
        try:
            units = failed_services(scope)
            if not units:
                findings.append(
                    finding(f"{scope.capitalize()} services: no failed services.", "success")
                )
                continue
            details = command(
                [
                    "systemctl",
                    f"--{scope}",
                    "show",
                    "--no-pager",
                    "--property=Id,Result,ExecMainStatus,SubState",
                    "--",
                    *units,
                ]
            ).stdout
            entries = {
                entry.get("Id"): entry
                for block in details.strip().split("\n\n")
                if (entry := properties(block)).get("Id")
            }
            for unit in units:
                failed.append({"scope": scope, "unit": unit})
                detail = entries.get(unit, {})
                findings.append(
                    finding(
                        f"{scope}/{unit}: result={detail.get('Result', 'unknown')}, "
                        f"exit={detail.get('ExecMainStatus', 'unknown')}, "
                        f"state={detail.get('SubState', 'unknown')}.",
                        "warning",
                    )
                )
                journal = "sudo journalctl -b" if scope == "system" else "journalctl --user -b"
                findings.append(finding(f"Logs: {journal} -u '{unit}' -n 30 --no-pager"))
        except (OSError, ValueError, KeyError, RuntimeError, subprocess.TimeoutExpired) as error:
            findings.append(
                finding(f"{scope.capitalize()} service check unavailable: {error}", "warning")
            )
    return report("Service health", findings, failed=failed)


def time_check(wait=0):
    deadline = time.monotonic() + wait
    while True:
        state = properties(
            command(
                [
                    "timedatectl",
                    "show",
                    "--property=NTPSynchronized",
                    "--property=NTP",
                    "--property=Timezone",
                ],
                timeout=3,
            ).stdout
        )
        if not {"NTPSynchronized", "NTP", "Timezone"} <= state.keys():
            raise ValueError("timedatectl returned incomplete synchronization properties")
        synchronized = state.get("NTPSynchronized") == "yes"
        enabled = state.get("NTP") == "yes"
        if synchronized or not enabled or time.monotonic() >= deadline:
            break
        time.sleep(min(1, max(0, deadline - time.monotonic())))
    findings = [finding(f"Timezone: {state.get('Timezone', 'unknown')}.")]
    if synchronized:
        findings.append(finding("System clock is synchronized.", "success"))
    else:
        findings.append(
            finding("System clock is not synchronized; TLS and authentication may fail.", "warning")
        )
    if not enabled:
        findings.append(
            finding(
                "Automatic NTP synchronization is disabled; review the system time-sync setting.",
                "warning",
            )
        )
    return report("Time synchronization", findings, synchronized=synchronized, ntp_enabled=enabled)


def dns_check(host):
    try:
        result = command(["getent", "ahostsv4", host], timeout=5, check=False)
        addresses = sorted({line.split()[0] for line in result.stdout.splitlines() if line.split()})
        if result.returncode or not addresses:
            raise ValueError("no IPv4 address returned")
        return finding(f"DNS {host}: {', '.join(addresses[:3])}.", "success")
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        return finding(f"DNS {host}: failed ({error}).", "warning")


def https_check(label, url, expected):
    try:
        result = command(
            [
                "curl",
                "--silent",
                "--show-error",
                "--head",
                "--ipv4",
                "--noproxy",
                "*",
                "--connect-timeout",
                "3",
                "--max-time",
                "8",
                "--output",
                "/dev/null",
                "--write-out",
                "%{http_code} %{time_total}",
                url,
            ],
            timeout=10,
            check=False,
        )
        code, duration = result.stdout.split()
        if result.returncode or code != str(expected):
            raise ValueError(f"curl exit {result.returncode}, HTTP {code}")
        return finding(
            f"{label}: HTTPS {code}, {float(duration):.2f} s (system VPN route).", "success"
        )
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        return finding(f"{label}: HTTPS check failed ({error}).", "warning")


def connectivity_check():
    jobs = [(dns_check, (host,)) for host in ("www.baidu.com", "github.com", "cache.nixos.org")]
    jobs += [
        (https_check, args)
        for args in (
            ("VPN exit", "https://www.gstatic.com/generate_204", 204),
            ("GitHub", "https://github.com/", 200),
            ("Nix cache", "https://cache.nixos.org/nix-cache-info", 200),
        )
    ]
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
        pending = [executor.submit(operation, *args) for operation, args in jobs]
        findings = [future.result() for future in pending]
    return report(
        "DNS and service connectivity",
        [
            finding(
                "Direct Wi-Fi HTTPS transfer passed earlier with VPN stopped; DNS and endpoint checks below use the prepared VPN route.",
                "success",
            ),
            *findings,
        ],
    )


def restart_failed(scope, requested):
    if (
        scope not in ("system", "user")
        or not isinstance(requested, list)
        or not 1 <= len(requested) <= 64
    ):
        raise ValueError("Expected 1 through 64 failed service names")
    if not all(valid_service(unit) for unit in requested):
        raise ValueError("Invalid service name")
    requested = list(dict.fromkeys(requested))
    current = set(failed_services(scope))
    findings = []
    for unit in requested:
        if unit not in current:
            findings.append(finding(f"{scope}/{unit}: no longer failed; restart skipped."))
            continue
        try:
            command(["systemctl", f"--{scope}", "restart", "--", unit], timeout=30)
            state = command(
                ["systemctl", f"--{scope}", "show", "--property=ActiveState,Result", "--", unit]
            ).stdout
            state = properties(state)
            if (
                state.get("ActiveState") not in ("active", "inactive")
                or state.get("Result") != "success"
            ):
                raise RuntimeError("service did not recover successfully")
            findings.append(
                finding(
                    f"{scope}/{unit}: restart completed (state={state['ActiveState']}).", "success"
                )
            )
        except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
            findings.append(finding(f"{scope}/{unit}: restart failed ({error}).", "error"))
    return report("Service repair", findings)


def retry_time_sync():
    state = time_check()
    if not state["data"]["ntp_enabled"]:
        raise RuntimeError("NTP is disabled; automatic time synchronization was not enabled")
    if not state["data"]["synchronized"]:
        command(["systemctl", "--system", "restart", "systemd-timesyncd.service"], timeout=20)
    return time_check(wait=15)
