"""Loopback-only web panel; native module clients retain all domain effects."""

import asyncio
import fcntl
import hmac
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import URLError
from urllib.request import Request, urlopen

from .client import BackendError, Client

ASSETS = Path(__file__).parent / "web"
FIELDS = {
    ("wifi", "scan"): {"interface"},
    ("wifi", "radio"): {"enabled"},
    ("wifi", "connect"): {"interface", "ap", "uuid", "password", "hidden", "ssid", "security"},
    ("wifi", "disconnect"): {"interface"},
    ("wifi", "forget"): {"interface", "uuid"},
    ("devices", "volume"): {"level"},
    ("devices", "brightness"): {"level", "device"},
    ("devices", "mute"): set(),
    ("devices", "output"): {"name"},
    ("proxy", "proxy-mode"): {"mode"},
    ("proxy", "proxy-group-select"): {"group", "node"},
    ("proxy", "proxy-delay"): {"node"},
}


def validate(request):
    if not isinstance(request, dict) or set(request) != {"domain", "action", "fields"}:
        raise ValueError("Invalid operation")
    domain, action, fields = request["domain"], request["action"], request["fields"]
    if not isinstance(domain, str) or not isinstance(action, str):
        raise ValueError("Invalid operation")
    allowed = FIELDS.get((domain, action))
    if allowed is None or not isinstance(fields, dict) or not set(fields) <= allowed:
        raise ValueError("Unsupported operation or fields")
    optional = {"password", "ap", "uuid", "hidden", "ssid", "security"} if action == "connect" else set()
    if not allowed - optional <= set(fields):
        raise ValueError("Missing operation fields")
    for key, value in fields.items():
        if key in {"hidden", "enabled"}:
            valid = type(value) is bool
        elif key == "level":
            valid = type(value) is int and 0 <= value <= 100
        else:
            valid = isinstance(value, str) and len(value) <= 2048 and "\0" not in value
        if not valid:
            raise ValueError("Invalid operation field")
    return domain, action, fields


def theme_css():
    try:
        config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
        settings = json.loads((config / "folio/appearance.json").read_text())
        family = settings["font-family"]
        size = settings["font-size"]
        if not isinstance(family, str) or any(c in family for c in "\r\n\0"):
            raise ValueError
        if type(size) is not int or not 6 <= size <= 72:
            raise ValueError
        appearance = settings["appearance"]
    except (OSError, KeyError, ValueError, TypeError):
        family, size, appearance = "Maple Mono NF CN", 16, "dark"
    palette = ("--bg:#fffbef;--surface:#f8f5e4;--raised:#f2efdf;--fg:#5c6a72;"
               "--muted:#939f91;--line:#e8e5d5;--accent:#dfa000;--green:#8da101;--red:#f85552;"
               "color-scheme:light;") if appearance == "light" else ""
    return f":root{{{palette}--font:{json.dumps(family, ensure_ascii=False)},monospace;--font-size:{size}pt;}}".encode()


class PanelServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, client=None):
        self.token = secrets.token_urlsafe(32)
        self.client = client or Client()
        self.operation = threading.Lock()
        super().__init__(("127.0.0.1", 0), Handler)
        self.origin = f"http://127.0.0.1:{self.server_port}"


class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(10)

    def log_message(self, *_args):
        pass  # Requests, credentials and session tokens never enter access logs.

    def send(self, status, data, content_type="application/json"):
        if content_type == "application/json":
            data = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type + "; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'")
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def authorized(self):
        if self.headers.get("Host") != self.server.origin.removeprefix("http://"):
            self.send(403, {"error": "Invalid host"})
            return False
        origin = self.headers.get("Origin")
        if origin is not None and origin != self.server.origin:
            self.send(403, {"error": "Invalid origin"})
            return False
        expected = "Bearer " + self.server.token
        if not hmac.compare_digest(self.headers.get("Authorization", "").encode(), expected.encode()):
            self.send(403, {"error": "Open the panel using folio panel"})
            return False
        return True

    def do_GET(self):
        if self.path.startswith("/api/"):
            if not self.authorized():
                return
            try:
                async def read():
                    client = self.server.client
                    if self.path == "/api/ping":
                        return {"source": str(Path(__file__).resolve())}
                    if self.path == "/api/wifi":
                        return await client.wifi()
                    if self.path == "/api/devices":
                        return await client.devices()
                    if self.path == "/api/information":
                        return await client.devices("information")
                    if self.path == "/api/proxy":
                        status = await client.proxy("status")
                        if not status.get("proxy", {}).get("available"):
                            raise BackendError("Mihomo is unavailable")
                        return {**status, **await client.proxy("proxy-groups")}
                    raise ValueError("Unknown endpoint")
                self.send(200, {"data": asyncio.run(read())})
            except ValueError:
                self.send(404, {"error": "Unknown endpoint"})
            except (BackendError, OSError):
                self.send(503, {"error": "Service unavailable. Check the installed backend and your desktop permissions."})
            except Exception:
                self.send(500, {"error": "Unable to read current state"})
            return
        if self.headers.get("Host") != self.server.origin.removeprefix("http://"):
            self.send(403, {"error": "Invalid host"})
            return
        if self.path == "/theme.css":
            self.send(200, theme_css(), "text/css")
            return
        assets = {"/": ("index.html", "text/html"), "/app.js": ("app.js", "text/javascript"), "/style.css": ("style.css", "text/css")}
        if self.path not in assets:
            self.send(404, {"error": "Not found"})
            return
        name, kind = assets[self.path]
        self.send(200, (ASSETS / name).read_bytes(), kind)

    def do_POST(self):
        if not self.authorized():
            return
        if self.path == "/api/shutdown":
            self.send(200, {"data": {"stopped": True}})
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return
        if self.path != "/api/action":
            self.send(404, {"error": "Unknown endpoint"})
            return
        if self.headers.get("Content-Type") != "application/json":
            self.send(415, {"error": "Expected JSON"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 16384:
                raise ValueError
            domain, action, fields = validate(json.loads(self.rfile.read(length)))
        except (ValueError, TypeError):
            self.send(400, {"error": "Invalid operation"})
            return
        if not self.server.operation.acquire(blocking=False):
            self.send(409, {"error": "Another operation is running. Try again shortly."})
            return
        try:
            data = asyncio.run(getattr(self.server.client, domain)(action, **fields))
            self.send(200, {"data": data})
        except Exception:
            # A backend diagnostic must never echo a credential-bearing request.
            self.send(503, {"error": "Operation failed. Refresh state and check service availability or permissions."})
        finally:
            fields.pop("password", None)
            self.server.operation.release()


def runtime():
    base = os.environ.get("XDG_RUNTIME_DIR")
    if not base:
        raise RuntimeError("A desktop runtime directory is required")
    directory = Path(base) / "folio-panel"
    directory.mkdir(mode=0o700, exist_ok=True)
    if directory.is_symlink() or directory.stat().st_uid != os.getuid():
        raise RuntimeError("Invalid panel runtime directory")
    directory.chmod(0o700)
    return directory


def serve():
    directory = runtime()
    with (directory / "server.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        with PanelServer() as server:
            record = directory / "session.json"
            temporary = directory / "session.tmp"
            temporary.write_text(json.dumps({"origin": server.origin, "token": server.token,
                                             "source": str(Path(__file__).resolve())}))
            temporary.chmod(0o600)
            temporary.replace(record)
            server.serve_forever()


def session(directory):
    try:
        record = json.loads((directory / "session.json").read_text())
        origin = record["origin"]
        if not origin.startswith("http://127.0.0.1:") or not origin[17:].isdigit():
            return None
        request = Request(origin + "/api/ping", headers={"Authorization": "Bearer " + record["token"]})
        with urlopen(request, timeout=1) as response:
            if response.status == 200:
                return record
    except (OSError, ValueError, KeyError, URLError):
        pass
    return None


def launch():
    from .paths import OPENER

    directory = runtime()
    record = session(directory)
    if record and record.get("source") != str(Path(__file__).resolve()):
        request = Request(record["origin"] + "/api/shutdown", data=b"",
                          headers={"Authorization": "Bearer " + record["token"]})
        with urlopen(request, timeout=2):
            pass
        time.sleep(0.7)
        record = None
    if record is None:
        subprocess.Popen([sys.executable, "-m", "folio_panel", "--serve"],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        for _ in range(50):
            time.sleep(0.1)
            record = session(directory)
            if record:
                break
    if record is None:
        print("Unable to start the local panel service", file=sys.stderr)
        return 1
    url = record["origin"] + "/#" + record["token"]
    subprocess.Popen([OPENER, url], stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    print("Panel opened in your browser.")
    return 0
