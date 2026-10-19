"""UI contract checks; fake transport is not hardware acceptance evidence."""

import asyncio
import copy

from folio_panel.app import Confirm, Connect, Panel, Slider
from folio_panel.client import BackendError
from textual.widgets import Button, DataTable, Input, Static, TabbedContent


class Client:
    def __init__(self):
        self.calls = []
        self.wireless = {
            "enabled": True,
            "hardwareEnabled": True,
            "adapters": [
                {
                    "interface": "wlan0",
                    "state": "disconnected",
                    "addresses": [],
                    "profiles": [],
                    "networks": [
                        {
                            "path": "/ap/1",
                            "ssid": "[red]测试[/red]",
                            "signal": 80,
                            "security": "WPA Personal",
                            "active": False,
                            "profiles": [],
                        }
                    ],
                }
            ],
        }
        self.device = {
            "audio": {
                "available": True,
                "default": "sink1",
                "sinks": [
                    {
                        "name": "sink1",
                        "description": "Speakers",
                        "volume": 30,
                        "mute": False,
                    },
                    {
                        "name": "sink2",
                        "description": "Headphones",
                        "volume": 20,
                        "mute": False,
                    },
                ],
            },
            "backlights": [],
        }

    async def wifi(self, action="status", **fields):
        self.calls.append(("wifi", action, copy.deepcopy(fields)))
        return copy.deepcopy(self.wireless)

    async def devices(self, action="status", **fields):
        self.calls.append(("devices", action, fields))
        if action == "information":
            return {
                "model": "Fixture Computer",
                "board": "Fixture Board",
                "cpu": "Fixture CPU",
                "memoryKiB": 8388608,
                "availableMemoryKiB": 4194304,
                "gpus": [{"name": "Fixture Graphics", "driver": "amdgpu"}],
                "displays": [{"name": "DP-1", "modes": ["1920x1080"]}],
                "interfaces": ["eth0", "wlan0"],
                "batteries": [],
                "os": "NixOS",
                "kernel": "fixture-kernel",
                "uptimeSeconds": 600,
                "target": "folio",
            }
        if action == "volume":
            self.device["audio"]["sinks"][0]["volume"] = fields["level"]
        return copy.deepcopy(self.device)

    async def proxy(self, action, **fields):
        self.calls.append(("proxy", action, fields))
        if action == "status":
            return {"proxy": {"available": True, "mode": "rule"}}
        if action == "proxy-groups":
            return {
                "groups": [
                    {
                        "name": "PROXY",
                        "type": "Selector",
                        "selected": "DIRECT",
                        "nodes": ["DIRECT", "[blue]Node"],
                    }
                ]
            }
        if action == "proxy-delay":
            raise BackendError("Unavailable")
        return {}


def test_wifi_connect_password_is_masked_and_not_in_worker_description():
    async def scenario():
        client = Client()
        app = Panel(client)
        async with app.run_test(size=(110, 40)) as pilot:
            await pilot.pause()
            table = app.query_one("#networks", DataTable)
            assert table.get_row_at(0)[0].plain == "[red]测试[/red]"
            await pilot.click("#wifi-connect")
            await pilot.pause()
            assert isinstance(app.screen, Connect)
            password = app.screen.query_one("#password", Input)
            assert password.password
            password.value = "fixture-secret-only"
            await pilot.click("#connect")
            await pilot.pause()
            assert any(
                call[1] == "connect" and call[2]["password"] == "fixture-secret-only"
                for call in client.calls
            )
            assert all(
                "fixture-secret-only" not in worker.description
                for worker in app.workers
            )
            assert not isinstance(app.screen, Connect)

    asyncio.run(scenario())


def test_no_adapter_and_backend_error_remain_usable():
    async def scenario():
        client = Client()
        app = Panel(client)
        async with app.run_test(size=(80, 24)) as pilot:
            await pilot.pause()
            assert app.query_one("#networks", DataTable).row_count == 1
            client.wireless["adapters"] = []
            app.refresh_page()
            await pilot.pause()
            assert "No Wi-Fi Adapter" in str(
                app.query_one("#wifi-state", Static).render()
            )
            assert app.query_one("#wifi-connect", Button).disabled

            async def unavailable(*args, **kwargs):
                raise BackendError("Permission denied")

            client.wifi = unavailable
            app.refresh_page()
            await pilot.pause()
            assert "Permission denied" in str(app.query_one("#banner", Static).render())
            assert app.query_one("#radio", Button).disabled

    asyncio.run(scenario())


def test_backend_disappearance_clears_stale_audio_and_proxy_controls():
    async def scenario():
        client = Client()
        app = Panel(client)
        async with app.run_test(size=(100, 38)) as pilot:
            app.query_one(TabbedContent).active = "controls"
            await pilot.pause()
            assert not app.query_one("#volume", Slider).disabled

            async def unavailable(*args, **kwargs):
                raise BackendError("Backend stopped")

            client.devices = unavailable
            app.refresh_page()
            await pilot.pause()
            assert app.query_one("#volume", Slider).disabled
            assert app.query_one("#mute", Button).disabled
            assert "Unavailable" in app.query_one("#volume", Slider).render().plain
            app.query_one(TabbedContent).active = "proxy"
            await pilot.pause()
            assert app.query_one("#nodes", DataTable).row_count == 2
            client.proxy = unavailable
            app.refresh_page()
            await pilot.pause()
            assert app.query_one("#nodes", DataTable).row_count == 0
            assert app.query_one("#select-node", Button).disabled

    asyncio.run(scenario())


def test_slider_debounces_and_missing_backlight_is_disabled():
    async def scenario():
        client = Client()
        app = Panel(client)
        async with app.run_test(size=(100, 38)) as pilot:
            app.query_one(TabbedContent).active = "controls"
            await pilot.pause()
            assert app.query_one("#brightness", Slider).disabled
            slider = app.query_one("#volume", Slider)
            slider.focus()
            await pilot.press("right", "right", "right")
            await pilot.pause(0.6)
            writes = [c for c in client.calls if c[:2] == ("devices", "volume")]
            assert len(writes) == 1 and writes[0][2]["level"] == 33
            assert slider.value == 33

    asyncio.run(scenario())


def test_proxy_timeout_and_resize_do_not_change_selection():
    async def scenario():
        client = Client()
        app = Panel(client)
        async with app.run_test(size=(100, 38)) as pilot:
            app.query_one(TabbedContent).active = "proxy"
            await pilot.pause()
            assert app.query_one("#nodes", DataTable).row_count == 2
            await pilot.click("#test-node")
            await pilot.pause(0.5)
            assert app.delays["DIRECT"] == "Timeout / Unavailable"
            assert not any(c[1] == "proxy-group-select" for c in client.calls)
            await pilot.resize_terminal(65, 22)
            await pilot.pause()
            assert app.query_one("#nodes", DataTable).row_count == 2

    asyncio.run(scenario())


def test_forget_and_radio_require_confirmation():
    async def scenario():
        client = Client()
        client.wireless["adapters"][0]["networks"][0]["profiles"] = ["fixture-uuid"]
        app = Panel(client)
        async with app.run_test(size=(110, 40)) as pilot:
            await pilot.pause()
            await pilot.click("#forget")
            assert isinstance(app.screen, Confirm)
            await pilot.click("#cancel")
            await pilot.pause()
            assert not any(c[1] == "forget" for c in client.calls)
            await pilot.click("#radio")
            assert isinstance(app.screen, Confirm)
            await pilot.click("#confirm")
            await pilot.pause()
            assert any(
                c[1] == "radio" and c[2]["enabled"] is False for c in client.calls
            )

    asyncio.run(scenario())
