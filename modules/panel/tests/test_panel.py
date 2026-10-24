"""Exercise the real HTTP boundary; fake clients do not establish hardware health."""

import copy
import json
import threading
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import pytest

from folio_panel.client import BackendError
from folio_panel.server import PanelServer, session, theme_css


class Store:
    def __init__(self):
        self.applications = []
        self.task = None

    def status(self):
        return {"applications": self.applications, "remotes": ["flathub"], "task": self.task}

    def search(self, query):
        return {
            "applications": [
                {
                    "id": "com.valvesoftware.Steam",
                    "name": "Steam",
                    "description": "Games <script>",
                    "version": "1.0",
                    "branch": "stable",
                    "remote": "flathub",
                }
            ]
        }

    def start(self, action, fields):
        if action not in {"install", "remove", "setup", "refresh"}:
            raise ValueError("Invalid operation")
        if action == "install":
            self.applications = [
                {
                    "id": "com.valvesoftware.Steam",
                    "name": "Steam",
                    "ref": "app/com.valvesoftware.Steam/x86_64/stable",
                    "version": "1.0",
                    "remote": "flathub",
                    "scope": "user",
                    "removable": True,
                }
            ]
        elif action == "remove":
            self.applications = []
        self.task = {
            "id": "fixture",
            "action": action,
            "fields": fields,
            "phase": "succeeded",
            "log": "Complete",
            "error": None,
        }
        return self.task


class Client:
    def __init__(self):
        self.calls = []
        self.fail = False
        self.proxy_mode = "global"
        self.proxy_groups = [
            {
                "name": "GLOBAL",
                "selected": "DIRECT",
                "type": "Selector",
                "nodes": ["DIRECT", "REJECT", "PROXY"],
            },
            {
                "name": "PROXY",
                "selected": "Hong Kong · 01",
                "type": "Selector",
                "nodes": ["Hong Kong · 01", "Tokyo · 02", "Singapore · 03", "DIRECT"],
            },
        ]
        self.wireless = {
            "enabled": True,
            "hardwareEnabled": True,
            "adapters": [
                {
                    "interface": "wlan0",
                    "state": "connected",
                    "addresses": ["192.168.1.24"],
                    "networks": [
                        {
                            "path": "/ap/1",
                            "ssid": "Everforest",
                            "signal": 92,
                            "security": "WPA Personal",
                            "active": True,
                            "profiles": ["saved-uuid"],
                        },
                        {
                            "path": "/ap/2",
                            "ssid": "Studio guest",
                            "signal": 68,
                            "security": "Open",
                            "active": False,
                            "profiles": [],
                        },
                        {
                            "path": "/ap/3",
                            "ssid": "<img src=x onerror=alert(1)>",
                            "signal": 30,
                            "security": "WPA Personal",
                            "active": False,
                            "profiles": [],
                        },
                    ],
                }
            ],
        }

    async def doctor(self):
        return {
            "health": "degraded",
            "findings": [
                {
                    "scope": "user",
                    "code": "deployment-pending",
                    "message": "Settings await deployment.",
                    "nextCommand": "folio plan",
                }
            ],
        }

    async def settings(self):
        values = {
            "appearance": "dark",
            "scheme": "everforest",
            "font-family": "Maple Mono NF CN",
            "font-size": 16,
        }
        preferences = getattr(self, "preferences", values)
        return {
            "digest": "a" * 64,
            "preferences": preferences,
            "defaults": values,
            "effective": {**values, **preferences},
            "origins": {
                key: "user override" if key in preferences else "system default" for key in values
            },
        }

    async def save_settings(self, digest, preferences):
        self.calls.append(("settings", "save", preferences))
        if digest != "a" * 64:
            raise BackendError("private backend detail", "conflict", "configuration-conflict")
        self.preferences = {k: v for k, v in preferences.items() if v is not None}
        return {"digest": "a" * 64}

    async def wifi(self, action="status", **fields):
        self.calls.append(("wifi", action, copy.deepcopy(fields)))
        if self.fail:
            raise BackendError("fixture-secret-only")
        return copy.deepcopy(self.wireless)

    async def devices(self, action="status", **fields):
        self.calls.append(("devices", action, fields))
        if self.fail:
            raise BackendError("Stopped")
        if action == "information":
            return {
                "model": "Folio workstation",
                "board": "MSI MAG B650M MORTAR WIFI",
                "cpu": "AMD Ryzen 7 9700X",
                "memoryKiB": 33554432,
                "availableMemoryKiB": 25165824,
                "os": "NixOS",
                "kernel": "6.18",
                "target": "folio",
                "uptimeSeconds": 5400,
                "gpus": [{"name": "NVIDIA RTX 3090", "driver": "nvidia"}],
                "displays": [{"name": "DP-1", "modes": ["2560×1440 @ 144 Hz"]}],
                "interfaces": ["wlan0", "eth0"],
                "batteries": [],
            }
        return {
            "audio": {
                "available": True,
                "default": "speaker",
                "sinks": [
                    {
                        "name": "speaker",
                        "description": "Built-in speakers",
                        "volume": 42,
                        "mute": False,
                    },
                    {
                        "name": "headphones",
                        "description": "USB headphones",
                        "volume": 30,
                        "mute": False,
                    },
                ],
            },
            "backlights": [{"name": "intel_backlight", "percent": 65}],
        }

    async def proxy(self, action, **fields):
        self.calls.append(("proxy", action, fields))
        if self.fail:
            raise BackendError("Stopped")
        if action == "status":
            return {"proxy": {"available": True, "mode": self.proxy_mode}}
        if action == "proxy-groups":
            return {"groups": copy.deepcopy(self.proxy_groups)}
        if action == "proxy-mode":
            self.proxy_mode = fields["mode"]
            return {}
        if action == "proxy-group-select":
            next(group for group in self.proxy_groups if group["name"] == fields["group"])[
                "selected"
            ] = fields["node"]
            return {}
        return {"delay": 24}


@pytest.fixture
def panel():
    server = PanelServer(Client(), Store())
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield server
    server.shutdown()
    server.server_close()
    thread.join()


def request(server, path, data=None, token=True, headers=None, raw=None):
    body = json.dumps(data).encode() if data is not None else raw
    values = {"Authorization": "Bearer " + server.token} if token else {}
    if body is not None:
        values["Content-Type"] = "application/json"
    values.update(headers or {})
    req = Request(server.origin + path, data=body, headers=values)
    try:
        response = urlopen(req, timeout=5)
    except HTTPError as error:
        response = error
    with response:
        return response.status, response.read(), response.headers


def test_reads_and_assets(panel):
    for endpoint in ("wifi", "devices", "information", "proxy", "ping"):
        code, body, _ = request(panel, "/api/" + endpoint)
        assert code == 200 and "data" in json.loads(body)
    for path, mime in (
        ("/", "text/html"),
        ("/app.js", "text/javascript"),
        ("/style.css", "text/css"),
        ("/theme.css", "text/css"),
    ):
        code, body, headers = request(panel, path, token=False)
        assert code == 200 and body and headers["Content-Type"].startswith(mime)
        assert "frame-ancestors 'none'" in headers["Content-Security-Policy"]
    assert request(panel, "/../server.py")[0] == 404


def test_http_authentication_and_cross_site_requests(panel):
    assert request(panel, "/api/wifi", token=False)[0] == 403
    assert request(panel, "/api/wifi", headers={"Authorization": "Bearer invalid"})[0] == 403
    assert request(panel, "/api/wifi", headers={"Host": "evil.example"})[0] == 403
    assert request(panel, "/api/wifi", headers={"Origin": "https://evil.example"})[0] == 403
    assert request(panel, "/api/wifi", headers={"Origin": "null"})[0] == 403
    assert not panel.client.calls


def test_actions_reach_module_clients_and_secrets_are_not_reflected(panel):
    fields = {"interface": "wlan0", "ap": "/ap/1", "password": "fixture-secret-only"}
    body = {"domain": "wifi", "action": "connect", "fields": fields}
    code, response, _ = request(panel, "/api/action", body)
    assert code == 200 and b"fixture-secret-only" not in response
    assert panel.client.calls[-1] == ("wifi", "connect", fields)
    panel.client.fail = True
    code, response, _ = request(panel, "/api/action", body)
    assert code == 503 and b"fixture-secret-only" not in response
    assert request(panel, "/api/wifi")[0] == 503


@pytest.mark.parametrize(
    "body",
    [
        {"domain": "system", "action": "reboot", "fields": {}},
        {"domain": "devices", "action": "volume", "fields": {"level": 101}},
        {"domain": "devices", "action": "volume", "fields": {"level": True}},
        {"domain": "wifi", "action": "radio", "fields": {"enabled": "false"}},
        {"domain": "devices", "action": "output", "fields": {}},
        {
            "domain": "wifi",
            "action": "scan",
            "fields": {"interface": "wlan0", "command": "touch /tmp/escape"},
        },
        {"domain": [], "action": "scan", "fields": {}},
        [],
    ],
)
def test_invalid_operations_have_no_effect(panel, body):
    assert request(panel, "/api/action", body)[0] == 400
    assert not panel.client.calls


def test_invalid_json_and_concurrent_mutations(panel):
    assert request(panel, "/api/action", raw=b"{")[0] == 400
    assert request(panel, "/api/action", raw=b"x" * 17000)[0] == 400
    with panel.operation:
        code, _, _ = request(
            panel, "/api/action", {"domain": "devices", "action": "mute", "fields": {}}
        )
    assert code == 409 and not panel.client.calls


def test_runtime_record_requires_a_matching_live_server(panel, tmp_path):
    record = {"origin": panel.origin, "token": panel.token, "source": "fixture"}
    path = tmp_path / "session.json"
    path.write_text(json.dumps(record))
    assert session(tmp_path) == record
    record["token"] = "wrong-token"
    path.write_text(json.dumps(record))
    assert session(tmp_path) is None
    path.write_text(json.dumps({"origin": "https://example.com", "token": panel.token}))
    assert session(tmp_path) is None


def test_theme_uses_installed_appearance(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))
    (tmp_path / "folio").mkdir()
    path = tmp_path / "folio/appearance.json"
    path.write_text(
        json.dumps({"appearance": "light", "font-family": "Maple Mono NF CN", "font-size": 18})
    )
    css = theme_css()
    assert b"--bg:#fffbef" in css and b"18pt" in css and b"Maple Mono NF CN" in css
    path.write_text("invalid json")
    assert b"16pt" in theme_css()


def test_theme_uses_palette_and_roles(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))
    (tmp_path / "folio").mkdir()
    path = tmp_path / "folio/appearance.json"
    palette = {
        key: "#123456"
        for key in ["bg0", "bg1", "bg2", "bg3", "fg", "grey1", "yellow", "green", "red"]
    }
    palette["green"] = "#abcdef"
    settings = {
        "appearance": "dark",
        "font-family": "Maple Mono NF CN",
        "font-size": 16,
        "palette": palette,
        "roles": {"accent": "green"},
    }
    path.write_text(json.dumps(settings))
    css = theme_css()
    assert b"--bg:#123456" in css and b"--accent:#abcdef" in css
    palette["bg0"] = "red;}body{display:none}"
    path.write_text(json.dumps(settings))
    css = theme_css()
    assert b"display:none" not in css and b"--bg:#1b2521" in css


def test_store_http_boundary(panel):
    assert request(panel, "/api/apps", token=False)[0] == 403
    assert (
        request(panel, "/api/apps/action", {"action": "setup", "fields": {}}, token=False)[0] == 403
    )
    assert request(panel, "/api/apps")[0] == 200
    assert request(panel, "/api/apps/search?q=Steam")[0] == 200
    assert request(panel, "/api/apps/action", {"action": "setup", "fields": {}})[0] == 202
    assert request(panel, "/api/apps/action", {"action": [], "fields": {}})[0] == 400
    for path in ("/store.js", "/store.css"):
        assert request(panel, path, token=False)[0] == 200


def test_no_standalone_store_page(panel):
    assert request(panel, "/apps", token=False)[0] == 404


def test_settings_validation_conflict_and_diagnostics(panel):
    assert request(panel, "/api/settings", token=False)[0] == 403
    assert request(panel, "/api/doctor", token=False)[0] == 403
    assert request(panel, "/api/settings")[0] == 200
    assert request(panel, "/api/doctor")[0] == 200
    assert request(panel, "/settings.js", token=False)[0] == 200
    for preferences in (
        {"font-size": True},
        {"font-size": 73},
        {"account": "root"},
        {"scheme": "graphite"},
        {"appearance": "light"},
        {"font-family": "bad\nfont"},
    ):
        assert (
            request(panel, "/api/settings", {"digest": "a" * 64, "preferences": preferences})[0]
            == 400
        )
    assert not panel.client.calls
    code, body, _ = request(
        panel, "/api/settings", {"digest": "b" * 64, "preferences": {"font-size": 18}}
    )
    reply = json.loads(body)
    assert code == 409 and reply["code"] == "configuration-conflict" and reply["hint"]
    assert b"private backend detail" not in body
    assert (
        request(panel, "/api/settings", {"digest": "a" * 64, "preferences": {"font-size": 18}})[0]
        == 200
    )


def test_settings_client_preserves_other_fields_and_binds_digest(monkeypatch):
    import asyncio
    from pathlib import Path
    from folio_panel import client

    original = {
        "folio-environment:environment": {
            "account": "folio",
            "modules": [],
            "preferences": {"font-size": 16},
        }
    }
    calls = []

    async def process(arguments, **kwargs):
        calls.append(arguments)
        if arguments[-1] == "show":
            return {
                "status": "success",
                "data": {"configuration": copy.deepcopy(original), "digest": "a" * 64},
            }
        path = Path(arguments[arguments.index("import") + 1])
        saved = json.loads(path.read_text())["folio-environment:environment"]
        assert saved["account"] == "folio" and saved["modules"] == []
        assert saved["preferences"]["font-size"] == 18
        assert arguments[-2:] == ["--expected-digest", "a" * 64]
        return {"status": "success", "data": {"digest": "c" * 64}}

    monkeypatch.setattr(client, "process", process)
    monkeypatch.setattr(client.paths, "LEGACY", "/fake/folio")
    assert (
        asyncio.run(client.Client().save_settings("a" * 64, {"font-size": 18}))["digest"]
        == "c" * 64
    )
    with pytest.raises(BackendError):
        asyncio.run(client.Client().save_settings("b" * 64, {"font-size": 19}))
    assert len(calls) == 3


@pytest.mark.parametrize(
    "action,fields",
    [
        ("proxy-group-select", {"group": "PROXY", "node": "🇯🇵 日本Y01 | IEPL"}),
        ("proxy-delay", {"node": "🇺🇲 美国Y01 | IEPL | x1.5"}),
    ],
)
def test_proxy_rpc_keeps_emoji_names_as_utf8(monkeypatch, action, fields):
    import asyncio
    from pathlib import Path
    from folio_panel import client

    async def process(arguments, **kwargs):
        path = next(
            argument.removeprefix("--rpc=")
            for argument in arguments
            if argument.startswith("--rpc=")
        )
        raw = Path(path).read_bytes()
        assert fields["node"].encode("utf-8") in raw
        assert b"\\ud83c" not in raw
        assert json.loads(raw)["folio-network-panel:control"] == {"action": action, **fields}
        return {
            "output": {"result-json": json.dumps({"status": "success", "data": {"accepted": True}})}
        }

    monkeypatch.setattr(client, "process", process)
    assert asyncio.run(client.Client().proxy(action, **fields)) == {"accepted": True}
