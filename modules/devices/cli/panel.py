"""Bounded user-session device operations for the panel client."""

import glob
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path


def command(arguments):
    result = subprocess.run(arguments, capture_output=True, text=True, timeout=5, check=False)
    if result.returncode:
        raise OSError("Device service rejected the operation")
    return result.stdout


def text(path, default="Unavailable"):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return default


def snapshot():
    audio = {"available": False, "sinks": [], "default": None}
    try:
        sinks = json.loads(command(["pactl", "--format=json", "list", "sinks"]))
        audio = {
            "available": True,
            "default": command(["pactl", "get-default-sink"]).strip(),
            "sinks": [
                {
                    "name": s["name"],
                    "description": s.get("description", s["name"]),
                    "mute": s["mute"],
                    "volume": round(
                        sum(v["value"] for v in s["volume"].values())
                        / max(1, len(s["volume"]))
                        / 65536
                        * 100
                    ),
                }
                for s in sinks
            ],
        }
    except (OSError, ValueError, KeyError, subprocess.SubprocessError):
        pass
    brightness = []
    for name in sorted(glob.glob("/sys/class/backlight/*")):
        try:
            current, maximum = (
                int(text(name + "/brightness")),
                int(text(name + "/max_brightness")),
            )
            if maximum > 0:
                brightness.append(
                    {"name": Path(name).name, "percent": round(current * 100 / maximum)}
                )
        except ValueError:
            pass
    return {"audio": audio, "backlights": brightness}


def information():
    memory = {
        line.split(":", 1)[0]: int(line.split()[1])
        for line in text("/proc/meminfo", "").splitlines()
        if len(line.split()) >= 2
    }
    cpu = next(
        (
            line.split(":", 1)[1].strip()
            for line in text("/proc/cpuinfo", "").splitlines()
            if line.startswith("model name")
        ),
        "Unavailable",
    )
    gpus = []
    names = {}
    try:
        for line in command(["lspci", "-Dmm"]).splitlines():
            fields = shlex.split(line)
            if len(fields) >= 4:
                names[fields[0]] = " ".join(fields[2:4])
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    for device in Path("/sys/bus/pci/devices").glob("*"):
        if text(device / "class", "").startswith("0x03"):
            driver = device / "driver"
            gpus.append(
                {
                    "name": names.get(
                        device.name,
                        text(device / "vendor") + ":" + text(device / "device"),
                    ),
                    "driver": driver.resolve().name if driver.is_symlink() else "Unavailable",
                }
            )
    displays = [
        {
            "name": Path(path).parent.name,
            "modes": text(Path(path).parent / "modes", "Unavailable").splitlines(),
        }
        for path in glob.glob("/sys/class/drm/card*-*/status")
        if text(path) == "connected"
    ]
    batteries = [
        {
            "name": Path(path).name,
            "capacity": text(path + "/capacity"),
            "status": text(path + "/status"),
        }
        for path in glob.glob("/sys/class/power_supply/*")
        if text(path + "/type") == "Battery"
    ]
    target = "Unavailable"
    try:
        metadata = json.loads(Path("/run/current-system/folio-system.json").read_text())
        target = json.loads(Path(metadata["bootstrap"], "target.json").read_text())["name"]
    except (OSError, ValueError, KeyError):
        pass
    os_name = "Unavailable"
    for line in text("/etc/os-release", "").splitlines():
        if line.startswith("PRETTY_NAME="):
            os_name = line.split("=", 1)[1].strip('"')
    return {
        "model": text("/sys/class/dmi/id/product_name"),
        "board": text("/sys/class/dmi/id/board_name"),
        "cpu": cpu,
        "memoryKiB": memory.get("MemTotal"),
        "availableMemoryKiB": memory.get("MemAvailable"),
        "gpus": gpus,
        "displays": displays,
        "interfaces": sorted(os.listdir("/sys/class/net")),
        "batteries": batteries,
        "os": os_name,
        "kernel": os.uname().release,
        "uptimeSeconds": float(text("/proc/uptime", "0 0").split()[0]),
        "target": target,
    }


def execute(request):
    if os.geteuid() == 0:
        raise OSError("Device controls must run as the desktop user")
    action = request.get("action", "status")
    if action == "information":
        return information()
    if action == "status":
        return snapshot()
    if action in ("volume", "brightness"):
        level = request.get("level")
        if type(level) is not int or not 0 <= level <= 100:
            raise ValueError("Level must be an integer from 0 through 100")
        if action == "volume":
            command(
                [
                    "wpctl",
                    "set-volume",
                    "--limit",
                    "1.0",
                    "@DEFAULT_AUDIO_SINK@",
                    f"{level}%",
                ]
            )
        else:
            device = request.get("device", "")
            if (
                not isinstance(device, str)
                or not re.fullmatch(r"[A-Za-z0-9_.:-]+", device)
                or not Path("/sys/class/backlight", device).is_dir()
            ):
                raise ValueError("Select an available backlight")
            command(["brightnessctl", "--device", device, "--quiet", "set", f"{level}%"])
    elif action == "mute":
        command(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
    elif action == "output":
        name = request.get("name")
        if name not in {s["name"] for s in snapshot()["audio"]["sinks"]}:
            raise ValueError("Select an available audio output")
        command(["pactl", "set-default-sink", name])
    else:
        raise ValueError("Unknown device operation")
    return snapshot()


def main():
    try:
        request = json.loads(sys.stdin.buffer.read(65537))
        if not isinstance(request, dict):
            raise TypeError("Expected a request object")
        result = {"status": "success", "data": execute(request), "error": None}
        code = 0
    except (ValueError, KeyError, TypeError):
        result = {"status": "invalid", "data": None, "error": "Invalid device request"}
        code = 2
    except (OSError, subprocess.SubprocessError):
        result = {
            "status": "unavailable",
            "data": None,
            "error": "Device backend or authorization is unavailable",
        }
        code = 3
    json.dump(result, sys.stdout)
    sys.stdout.write("\n")
    return code


if __name__ == "__main__":
    sys.exit(main())
