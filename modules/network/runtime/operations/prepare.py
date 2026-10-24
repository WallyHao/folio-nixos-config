"""Boot-time saved Wi-Fi failover and restricted Mihomo node selection."""

import concurrent.futures
import contextlib
import http.client
import json
import math
import os
import re
import subprocess
import sys
import time
from urllib.parse import quote

from folio_proxy import Controller, execute as proxy_execute


class Failure(Exception):
    pass


def event(message, tone="info"):
    print(json.dumps({"message": message, "tone": tone}), flush=True)


def run(*args, timeout=40, check=True):
    result = subprocess.run(
        args,
        capture_output=True,
        text=True,
        timeout=timeout,
        env={**os.environ, "LC_ALL": "C"},
        stdin=subprocess.DEVNULL,
    )
    if check and result.returncode:
        raise Failure(f"{args[0]} failed (exit {result.returncode})")
    return result


def fields(line):
    """Decode nmcli's escaped terse fields, including colons in names."""
    result, value, escaped = [], "", False
    for char in line:
        if escaped:
            value += char
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == ":":
            result.append(value)
            value = ""
        else:
            value += char
    return result + [value]


def nm(*args):
    return run("nmcli", "--wait", "25", *args).stdout.strip()


def active_wifi():
    for line in nm("-t", "-f", "UUID,TYPE,DEVICE", "connection", "show", "--active").splitlines():
        uuid, kind, device = fields(line)
        if kind == "802-11-wireless" and device and device != "--":
            yield uuid, device


def saved_wifi():
    profiles = []
    for line in nm("-t", "-f", "UUID,TYPE,TIMESTAMP", "connection", "show").splitlines():
        uuid, kind, timestamp = fields(line)
        if kind == "802-11-wireless" and timestamp.isdigit() and int(timestamp) > 0:
            profiles.append((int(timestamp), uuid))
    return [uuid for _, uuid in sorted(profiles, reverse=True)]


def probe(interface):
    # TLS is verified, redirects/captive portals are rejected, and each transfer
    # is bound to the Wi-Fi interface. Mihomo is stopped during these probes.
    for url in ("https://www.baidu.com/", "https://www.qq.com/"):
        try:
            result = run(
                "curl",
                "--silent",
                "--show-error",
                "--fail",
                "--ipv4",
                "--noproxy",
                "*",
                "--interface",
                interface,
                "--connect-timeout",
                "4",
                "--max-time",
                "10",
                "--max-filesize",
                "2097152",
                "--output",
                "/dev/null",
                "--write-out",
                "%{http_code} %{size_download} %{speed_download} %{time_total}",
                url,
                timeout=12,
                check=False,
            )
            status, size, speed, duration = result.stdout.split()
            speed, duration = float(speed), float(duration)
            if (
                result.returncode == 0
                and status == "200"
                and int(size) >= 1024
                and math.isfinite(speed)
                and speed >= 16384
            ):
                event(
                    f"Wi-Fi transfer: {speed * 8 / 1_000_000:.2f} Mbps, {duration:.2f} s.",
                    "success",
                )
                return True
        except (ValueError, subprocess.TimeoutExpired):
            continue
    event("Wi-Fi test failed: HTTPS download unavailable or below 0.13 Mbps.", "warning")
    return False


def prepare_wifi():
    nm("radio", "wifi", "on")
    run("nm-online", "--quiet", "--timeout", "20", check=False, timeout=23)
    current = list(active_wifi())
    saved = saved_wifi()
    event(f"Found {len(saved)} previously used Wi-Fi profile(s).")
    attempted = set()
    for uuid, interface in current:
        attempted.add(uuid)
        name = nm("-g", "connection.id", "connection", "show", "uuid", uuid)
        event(f"Testing current Wi-Fi: {name} ({interface}).")
        if probe(interface):
            return
    for uuid in saved:
        if uuid in attempted:
            continue
        name = uuid
        try:
            name = nm("-g", "connection.id", "connection", "show", "uuid", uuid)
            event(f"Trying saved Wi-Fi: {name}.")
            nm("connection", "up", "uuid", uuid)
            interface = next(device for active, device in active_wifi() if active == uuid)
            if probe(interface):
                return
        except (Failure, StopIteration, subprocess.TimeoutExpired):
            event(f"Saved Wi-Fi unavailable: {name}.", "warning")
    raise Failure(
        "All saved Wi-Fi profiles failed. Check radio, signal, credentials or captive portal; then run folio prepare."
    )


def controller(method, path, data=None):
    with contextlib.closing(Controller()) as connection:
        connection.request(
            method,
            path,
            None if data is None else json.dumps(data),
            {"Content-Type": "application/json"},
        )
        response = connection.getresponse()
        body = response.read(1024 * 1024 + 1)
        if response.status not in (200, 204) or len(body) > 1024 * 1024:
            raise Failure("Mihomo controller rejected the request.")
        return json.loads(body) if body else {}


def eligible(name):
    # Match country labels, never arbitrary 'us' substrings such as 'Australia'.
    return bool(
        re.search(
            r"香港|美国|美國|🇭🇰|🇺🇸|(?<![a-z])(?:hong[ _-]*kong|united[ _-]*states|usa|hk|us)(?![a-z])",
            name,
            re.IGNORECASE,
        )
    )


def candidates(inventory, providers):
    groups = {"Selector", "URLTest", "Fallback", "LoadBalance", "Relay"}
    nodes = dict(inventory.get("proxies", {}))
    for provider in providers.get("providers", {}).values():
        for node in provider.get("proxies", []):
            nodes[node["name"]] = node
    return sorted(
        name
        for name, node in nodes.items()
        if eligible(name)
        and node.get("type") not in groups
        and node.get("type", "").lower()
        not in {"direct", "reject", "rejectdrop", "pass", "compatible"}
    )


def delay(node):
    try:
        value = proxy_execute({"action": "proxy-delay", "node": node})["delay"]
        if isinstance(value, (int, float)) and not isinstance(value, bool) and 0 < value < 2000:
            return value
    except (OSError, ValueError, KeyError, http.client.HTTPException):
        pass
    return None


def selection_path(inventory, node):
    """Reach provider nodes through selectors without enabling automatic groups."""
    proxies = inventory.get("proxies", {})
    pending, visited = [("GLOBAL", [])], set()
    while pending:
        name, path = pending.pop(0)
        if name in visited:
            continue
        visited.add(name)
        group = proxies.get(name, {})
        if group.get("type") != "Selector":
            continue
        for child in group.get("all", []):
            selected = path + [(name, child)]
            if child == node:
                return selected
            pending.append((child, selected))
    return None


def prepare_proxy():
    run("systemctl", "start", "folio-mihomo.service", timeout=35)
    for attempt in range(30):
        try:
            inventory = controller("GET", "/proxies")
            break
        except (OSError, ValueError, Failure, http.client.HTTPException):
            if attempt == 29:
                raise Failure(
                    "Mihomo controller is unavailable. Check folio-mihomo.service and its subscription."
                ) from None
            time.sleep(0.5)
    allowed = candidates(inventory, controller("GET", "/providers/proxies"))
    nodes = [node for node in allowed if selection_path(inventory, node)]
    if len(nodes) != len(allowed):
        event(
            "Some allowed nodes cannot be pinned through manual selectors and will be skipped.",
            "warning",
        )
    if not nodes:
        raise Failure(
            "No selectable Hong Kong or United States proxy nodes found in the subscription."
        )
    event(f"Testing {len(nodes)} Hong Kong / United States node(s), timeout 2000 ms.")
    measured = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
        jobs = {executor.submit(delay, node): node for node in nodes}
        for future in concurrent.futures.as_completed(jobs):
            node, latency = jobs[future], future.result()
            event(
                f"{node}: {latency:g} ms." if latency is not None else f"{node}: timed out.",
                "info" if latency is not None else "warning",
            )
            if latency is not None:
                measured.append((latency, node))
    if not measured:
        raise Failure(
            "All Hong Kong / United States nodes timed out. Check the subscription or upstream network."
        )
    # Pin every selector in the route, including provider-backed private groups.
    # Global mode prevents private rules from selecting another region.
    latency, node = min(measured)
    path = selection_path(inventory, node)
    for group, child in reversed(path):
        controller("PUT", "/proxies/" + quote(group, safe=""), {"name": child})
    controller(
        "PATCH",
        "/configs",
        {
            "mode": "global",
            "tun": {"enable": True, "auto-route": True, "auto-detect-interface": True},
        },
    )
    config = controller("GET", "/configs")
    if (
        config.get("mode") != "global"
        or not config.get("tun", {}).get("enable")
        or not config.get("tun", {}).get("auto-route")
    ):
        raise Failure("Mihomo did not enable the selected VPN node and TUN routing.")
    for group, child in path:
        if controller("GET", "/proxies/" + quote(group, safe="")).get("now") != child:
            raise Failure("Mihomo did not retain the selected VPN route.")
    if delay(node) is None:
        raise Failure("The selected VPN node failed its final connectivity test.")
    result = run(
        "curl",
        "--silent",
        "--show-error",
        "--fail",
        "--ipv4",
        "--noproxy",
        "*",
        "--connect-timeout",
        "4",
        "--max-time",
        "10",
        "--output",
        "/dev/null",
        "--write-out",
        "%{http_code}",
        "https://www.gstatic.com/generate_204",
        timeout=12,
        check=False,
    )
    if result.returncode or result.stdout != "204":
        raise Failure("VPN routing is configured, but the final HTTPS connectivity check failed.")
    event(f"VPN ready: {node}, {latency:g} ms (global mode, TUN enabled).", "success")


def prepare():
    was_active = (
        run("systemctl", "is-active", "--quiet", "folio-mihomo.service", check=False).returncode
        == 0
    )
    event("Temporarily stopping VPN for direct Wi-Fi testing.")
    run("systemctl", "stop", "folio-mihomo.service", timeout=35)
    try:
        prepare_wifi()
    finally:
        if was_active:
            run("systemctl", "start", "folio-mihomo.service", timeout=35)
    prepare_proxy()


def main():
    try:
        prepare()
        return 0
    except (
        Failure,
        OSError,
        ValueError,
        KeyError,
        subprocess.TimeoutExpired,
        http.client.HTTPException,
    ) as error:
        event(str(error), "error")
        return 1


if __name__ == "__main__":
    sys.exit(main())
