"""Check real focus-ring pixels in an isolated software-rendered Niri session."""

import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time

from PIL import Image


def wait_for(probe, processes, timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if any(process.poll() is not None for process in processes):
            raise RuntimeError("An isolated display process exited unexpectedly")
        result = probe()
        if result:
            return result
        time.sleep(0.02)
    raise TimeoutError("Timed out waiting for the isolated display")


out = Path(sys.argv[1]).resolve()
processes = []
with tempfile.TemporaryDirectory(prefix="folio-focus-") as directory:
    root = Path(directory)
    runtime = root / "runtime"
    runtime.mkdir(mode=0o700)
    env = os.environ.copy()
    for key in ("WAYLAND_DISPLAY", "DISPLAY", "NIRI_SOCKET", "DBUS_SESSION_BUS_ADDRESS"):
        env.pop(key, None)
    env.update(HOME=directory, XDG_RUNTIME_DIR=str(runtime), WINIT_UNIX_BACKEND="x11")
    config = root / "config.kdl"
    config.write_text('''
layout {
    gaps 32
    center-focused-column "never"
    default-column-width { proportion 0.4; }
    background-color "#000000"
    focus-ring {
        width 4
        active-color "#ff0000"
        inactive-color "#00000000"
    }
    border { off; }
}
prefer-no-csd
hotkey-overlay { skip-at-startup; }
window-rule { geometry-corner-radius 0; clip-to-geometry true; }
animations {
    slowdown 5
    window-open { off; }
    window-close { off; }
    horizontal-view-movement { off; }
    window-movement { off; }
    window-resize { off; }
}
''')
    try:
        # Let Xvfb choose a free display without touching the real session.
        read_fd, write_fd = os.pipe()
        with (out / "xvfb.log").open("w") as log:
            server = subprocess.Popen(
                ["Xvfb", "-displayfd", str(write_fd), "-screen", "0", "1280x800x24",
                 "-nolisten", "tcp", "-ac"],
                env=env, pass_fds=(write_fd,), stdout=log, stderr=log,
                start_new_session=True,
            )
        processes.append(server)
        os.close(write_fd)
        if not select.select([read_fd], [], [], 15)[0]:
            raise TimeoutError("Xvfb did not publish a display")
        with os.fdopen(read_fd) as display:
            env["DISPLAY"] = ":" + display.readline().strip()
        with (out / "niri.log").open("w") as log:
            compositor = subprocess.Popen(
                ["niri", "--config", str(config)], env=env,
                stdout=log, stderr=log, start_new_session=True,
            )
        processes.append(compositor)
        socket = wait_for(lambda: next(runtime.glob("niri.*.sock"), None), processes)
        env["NIRI_SOCKET"] = str(socket)
        env["WAYLAND_DISPLAY"] = wait_for(
            lambda: next((p.name for p in runtime.glob("wayland-*")
                          if not p.name.endswith(".lock")), None), processes,
        )

        def msg(*args):
            return subprocess.check_output(["niri", "msg", "--json", *args], env=env, text=True)

        def windows():
            return json.loads(msg("windows"))

        for name in ("fade-a", "fade-b"):
            with (out / (name + ".log")).open("w") as log:
                processes.append(subprocess.Popen(
                    ["foot", "--app-id", name, "-o", "colors-dark.background=000000",
                     "sleep", "60"], env=env, stdout=log, stderr=log,
                    start_new_session=True,
                ))
            wait_for(lambda: any(w["app_id"] == name for w in windows()), processes)
        ids = {w["app_id"]: w["id"] for w in windows()}

        def focus(name):
            msg("action", "focus-window", "--id", str(ids[name]))

        def capture(name):
            path = out / (name + ".png")
            msg("action", "screenshot-screen", "--show-pointer", "false", "--path", str(path))
            wait_for(lambda: path.exists(), processes)
            # Decode only after the compositor has finished writing the PNG.
            deadline = time.monotonic() + 5
            while True:
                try:
                    image = Image.open(path).convert("RGB")
                    image.load()
                    return image
                except OSError:
                    if time.monotonic() >= deadline:
                        raise
                    time.sleep(0.01)

        focus("fade-a")
        time.sleep(1.8)
        geometry = windows()
        (out / "geometry.json").write_text(json.dumps(geometry, indent=2) + "\n")
        points = {}
        # Tiled IPC geometry does not expose viewport positions in Niri 26.04.
        # This fixture has two columns that fit on screen, no struts and 32px gaps.
        x = 32
        for window in sorted(geometry, key=lambda w: w["layout"]["pos_in_scrolling_layout"]):
            layout = window["layout"]
            points[window["app_id"]] = (round(x - 2), round(32 + layout["tile_size"][1] / 2))
            x += layout["tile_size"][0] + 32
        before = capture("before")
        focus("fade-b")
        time.sleep(0.4)
        during = capture("during")
        time.sleep(1.5)
        after = capture("after")
        samples = {
            name: [image.getpixel(point) for image in (before, during, after)]
            for name, point in points.items()
        }
        (out / "samples.json").write_text(json.dumps(samples, indent=2) + "\n")
        a, b = samples["fade-a"], samples["fade-b"]
        assert a[0] == (255, 0, 0) and b[0] == (0, 0, 0), samples
        assert 0 < a[1][0] < 255 and 0 < b[1][0] < 255, samples
        assert a[2] == (0, 0, 0) and b[2] == (255, 0, 0), samples
        print("Actual focus-ring pixels fade out and in; final inactive ring is absent.")
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
        for process in reversed(processes):
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
