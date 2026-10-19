"""English, bordered terminal controls. Domain effects belong to module clients."""
# ruff: noqa: SIM117 -- nested contexts document the widget hierarchy.

import asyncio
import re
import time
from typing import ClassVar

from rich.text import Text
from textual import on, work
from textual.app import App, ComposeResult
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.message import Message
from textual.reactive import reactive
from textual.screen import ModalScreen
from textual.widget import Widget
from textual.widgets import (
    Button,
    DataTable,
    Footer,
    Input,
    Label,
    Select,
    Static,
    Switch,
    TabbedContent,
    TabPane,
)

from .client import BackendError, Client


def safe(value):
    """External SSIDs/node/device names are plain text, never terminal markup."""
    return re.sub(r"[\x00-\x1f\x7f-\x9f]", "", str(value))


class Slider(Widget):
    can_focus = True
    value = reactive(0)
    BINDINGS: ClassVar = [
        ("left", "decrease", "Decrease"),
        ("right", "increase", "Increase"),
        ("home", "minimum", "Minimum"),
        ("end", "maximum", "Maximum"),
    ]

    class Changed(Message):
        def __init__(self, slider):
            super().__init__()
            self.slider, self.value = slider, slider.value

    def render(self):
        if self.disabled:
            return Text("Unavailable")
        width = max(4, self.size.width - 10)
        filled = round(self.value * width / 100)
        return Text("━" * filled + "─" * (width - filled) + f" {self.value:3d}%")

    def change(self, value):
        value = max(0, min(100, round(value)))
        if value != self.value:
            self.value = value
            self.post_message(self.Changed(self))

    def action_decrease(self):
        self.change(self.value - 1)

    def action_increase(self):
        self.change(self.value + 1)

    def action_minimum(self):
        self.change(0)

    def action_maximum(self):
        self.change(100)

    def on_mouse_down(self, event):
        if event.button == 1:
            self.focus()
            self.capture_mouse()
            self.change(event.x / max(1, self.size.width - 10) * 100)

    def on_mouse_move(self, event):
        if event.button == 1:
            self.change(event.x / max(1, self.size.width - 10) * 100)

    def on_mouse_up(self, event):
        self.release_mouse()


class Confirm(ModalScreen):
    def __init__(self, message):
        super().__init__()
        self.message = message

    def compose(self):
        with Vertical(classes="dialog"):
            yield Static(Text(self.message))
            with Horizontal():
                yield Button("Cancel", id="cancel")
                yield Button("Confirm", id="confirm", variant="warning")

    @on(Button.Pressed)
    def choose(self, event):
        self.dismiss(event.button.id == "confirm")

    def key_escape(self):
        self.dismiss(False)


class Connect(ModalScreen):
    def __init__(self, network=None):
        super().__init__()
        self.network = network

    def compose(self):
        with Vertical(classes="dialog"):
            yield Label("Connect to Wi-Fi" if self.network else "Hidden Network")
            if self.network:
                yield Static(
                    Text(safe(self.network["ssid"]) + " · " + self.network["security"])
                )
                if self.network["profiles"]:
                    yield Label("Leave password empty to reuse the saved profile.")
            else:
                yield Input(placeholder="SSID", id="ssid")
                yield Select(
                    [(v, v) for v in ("WPA Personal", "WPA3", "Open")],
                    value="WPA Personal",
                    allow_blank=False,
                    id="security",
                )
            yield Input(placeholder="Network password", password=True, id="password")
            with Horizontal():
                yield Switch(id="show-password")
                yield Label("Show password")
            yield Static("Credentials are stored by NetworkManager for this user.")
            with Horizontal():
                yield Button("Cancel", id="cancel")
                yield Button("Connect", id="connect", variant="primary")

    @on(Switch.Changed)
    def show_password(self, event):
        self.query_one("#password", Input).password = not event.value

    @on(Button.Pressed)
    def choose(self, event):
        if event.button.id == "cancel":
            self.query_one("#password", Input).value = ""
            self.dismiss(None)
        elif event.button.id == "connect":
            password = self.query_one("#password", Input).value
            data = {"password": password}
            if self.network:
                data["ap"] = self.network["path"]
                if self.network["profiles"]:
                    data["uuid"] = self.network["profiles"][0]
            else:
                data.update(
                    hidden=True,
                    ssid=self.query_one("#ssid", Input).value,
                    security=self.query_one("#security", Select).value,
                )
            self.query_one("#password", Input).value = ""
            self.dismiss(data)

    def key_escape(self):
        self.query_one("#password", Input).value = ""
        self.dismiss(None)


class Panel(App):
    TITLE = "Folio"
    CSS = """
    Screen { background: #272e33; color: #d3c6aa; }
    TabbedContent { height: 1fr; }
    TabPane { padding: 0 1; }
    .section { border: round #859289; padding: 0 1; height: auto; }
    .toolbar { height: auto; min-height: 3; }
    .toolbar Button { min-width: 10; margin-right: 1; }
    Select { width: 1fr; }
    DataTable { height: 1fr; min-height: 5; border: round #859289; }
    #banner { height: auto; max-height: 4; padding: 0 1; color: #a7c080; }
    #wifi-state, #proxy-state, #audio-state { height: auto; margin-bottom: 1; }
    Slider { height: 3; border: round #859289; padding: 0 1; }
    Slider:focus { border: round #a7c080; }
    Slider:disabled { opacity: 40%; }
    Button:focus, Input:focus { border: tall #a7c080; }
    Confirm, Connect { align: center middle; }
    .dialog { width: 64; max-width: 95%; height: auto; max-height: 95%; overflow-y: auto;
              padding: 1 2; border: round #a7c080; background: #2d353b; }
    .dialog Horizontal { height: auto; min-height: 3; }
    .dialog Static, .dialog Label { margin-bottom: 1; height: auto; }
    #information { height: auto; }
    """
    BINDINGS: ClassVar = [
        ("q", "quit", "Quit"),
        ("r", "refresh", "Refresh"),
        ("?", "help", "Help"),
    ]

    def __init__(self, client=None):
        super().__init__()
        self.client = client or Client()
        self.interface = ""
        self.wifi_data = {}
        self.groups = []
        self.group = ""
        self.delays = {}
        self.busy = False
        self.testing = False
        self.slider_timers = {}

    def compose(self) -> ComposeResult:
        with TabbedContent(initial="wifi"):
            with TabPane("Wi-Fi", id="wifi"):
                with Vertical(classes="section"):
                    yield Label("Wireless adapter")
                    yield Select([], id="adapter", prompt="No Wi-Fi Adapter")
                    yield Static(
                        "Loading wireless state…", id="wifi-state", markup=False
                    )
                    with Horizontal(classes="toolbar"):
                        yield Button("Refresh", id="scan")
                        yield Button("Radio On/Off", id="radio")
                        yield Button("Hidden Network", id="hidden")
                yield DataTable(id="networks", cursor_type="row")
                with Horizontal(classes="toolbar"):
                    yield Button("Connect", id="wifi-connect", variant="primary")
                    yield Button("Disconnect", id="disconnect")
                    yield Button("Forget Network", id="forget")
            with TabPane("Proxy", id="proxy"):
                with Vertical(classes="section"):
                    yield Static("Loading proxy state…", id="proxy-state", markup=False)
                    yield Select([], id="group", prompt="No selectable proxy group")
                    with Horizontal(classes="toolbar"):
                        yield Select(
                            [(v.title(), v) for v in ("rule", "global", "direct")],
                            value="rule",
                            allow_blank=False,
                            id="mode",
                        )
                        yield Button("Set Mode", id="set-mode")
                        yield Button("Refresh", id="proxy-refresh")
                yield DataTable(id="nodes", cursor_type="row")
                with Horizontal(classes="toolbar"):
                    yield Button("Select Node", id="select-node", variant="primary")
                    yield Button("Test Latency", id="test-node")
                    yield Button("Test All", id="test-all")
            with TabPane("Display & Audio", id="controls"):
                with VerticalScroll():
                    with Vertical(classes="section"):
                        yield Label("Audio Output")
                        yield Select([], id="output", prompt="No audio output")
                        yield Static(
                            "Loading audio state…", id="audio-state", markup=False
                        )
                        yield Label("Volume · Left/Right to adjust")
                        yield Slider(id="volume", disabled=True)
                        with Horizontal(classes="toolbar"):
                            yield Button("Set Output", id="set-output")
                            yield Button("Mute / Unmute", id="mute")
                    with Vertical(classes="section"):
                        yield Label("Display Backlight")
                        yield Select(
                            [], id="backlight", prompt="No supported backlight"
                        )
                        yield Slider(id="brightness", disabled=True)
                        yield Static(
                            "External monitor DDC/CI control is not included.",
                            markup=False,
                        )
                    yield Static(
                        "Runtime controls take effect immediately. They are not included in configuration rollback.",
                        markup=False,
                    )
            with TabPane("Device", id="device"):
                with VerticalScroll(classes="section"):
                    yield Static(
                        "Loading device information…", id="information", markup=False
                    )
        yield Static("Ready", id="banner", markup=False)
        yield Footer()

    async def on_mount(self):
        self.query_one("#networks", DataTable).add_columns(
            "Network", "Signal", "Security", "State"
        )
        self.query_one("#nodes", DataTable).add_columns("Node", "State", "Latency")
        self.set_interval(8, self.poll)
        self.refresh_page()

    def message(self, value):
        self.query_one("#banner", Static).update(Text(safe(value)))

    def action_help(self):
        self.message(
            "Tab: focus · arrows: lists/sliders · Enter: select · r: refresh · q: quit. Runtime controls act immediately."
        )

    def action_refresh(self):
        self.refresh_page()

    def poll(self):
        if (
            not self.busy
            and not self.testing
            and len(self.screen_stack) == 1
            and not any(self.is_slider_focused(s) for s in ("volume", "brightness"))
        ):
            self.refresh_page()

    def is_slider_focused(self, name):
        return self.query_one("#" + name, Slider).has_focus

    @on(TabbedContent.TabActivated)
    def tab_changed(self):
        self.refresh_page()

    def select_options(self, name, options, value=None):
        select = self.query_one("#" + name, Select)
        options = [(Text(safe(label)), key) for label, key in options]
        # Preserve selection/focus on periodic observations.
        keys = [key for _, key in options]
        previous = select.value
        select.set_options(options)
        desired = (
            value
            if value in keys
            else previous
            if previous in keys
            else keys[0]
            if keys
            else Select.NULL
        )
        select.value = desired
        select.disabled = not keys

    def table_rows(self, name, rows):
        table = self.query_one("#" + name, DataTable)
        key = None
        if table.row_count:
            key = table.coordinate_to_cell_key(table.cursor_coordinate).row_key.value
        table.clear()
        for row_key, cells in rows:
            table.add_row(*(Text(safe(cell)) for cell in cells), key=row_key)
        keys = [key for key, _ in rows]
        if key in keys:
            table.move_cursor(row=keys.index(key))

    def selected(self, name):
        table = self.query_one("#" + name, DataTable)
        return (
            table.coordinate_to_cell_key(table.cursor_coordinate).row_key.value
            if table.row_count
            else None
        )

    def adapter_data(self):
        return next(
            (
                a
                for a in self.wifi_data.get("adapters", [])
                if a["interface"] == self.interface
            ),
            {},
        )

    def network(self):
        return next(
            (
                a
                for a in self.adapter_data().get("networks", [])
                if a["path"] == self.selected("networks")
            ),
            None,
        )

    @work(group="refresh", exclusive=True)
    async def refresh_page(self):
        if self.busy or not self.is_mounted:
            return
        page = self.query_one(TabbedContent).active
        try:
            if page == "wifi":
                self.show_wifi(await self.client.wifi())
            elif page == "proxy":
                await self.load_proxy()
            elif page == "controls":
                self.show_devices(await self.client.devices())
            elif page == "device":
                self.show_information(await self.client.devices("information"))
        except (BackendError, OSError) as error:
            if page == "wifi":
                self.show_wifi(
                    {"enabled": False, "hardwareEnabled": True, "adapters": []}
                )
                self.query_one("#radio", Button).disabled = True
            elif page == "proxy":
                self.groups = []
                self.select_options("group", [])
                self.show_nodes()
                for name in ("set-mode", "select-node", "test-node", "test-all"):
                    self.query_one("#" + name, Button).disabled = True
            elif page == "controls":
                self.show_devices(
                    {
                        "audio": {"available": False, "default": None, "sinks": []},
                        "backlights": [],
                    }
                )
            self.message(str(error))
            label = {
                "wifi": "wifi-state",
                "proxy": "proxy-state",
                "controls": "audio-state",
                "device": "information",
            }[page]
            self.query_one("#" + label, Static).update(
                Text("Unavailable: " + safe(error))
            )

    def show_wifi(self, data):
        self.query_one("#radio", Button).disabled = False
        self.wifi_data = data
        adapters = data["adapters"]
        if self.interface not in {a["interface"] for a in adapters}:
            self.interface = adapters[0]["interface"] if adapters else ""
        self.select_options(
            "adapter",
            [(a["interface"], a["interface"]) for a in adapters],
            self.interface,
        )
        adapter = self.adapter_data()
        state = (
            "No Wi-Fi Adapter"
            if not adapters
            else ("Radio On" if data["enabled"] else "Radio Off")
        )
        if not data["hardwareEnabled"]:
            state += " · Hardware radio blocked"
        state += " · " + adapter.get("state", "Unavailable")
        state += " · " + ", ".join(adapter.get("addresses", []))
        self.query_one("#wifi-state", Static).update(Text(safe(state)))
        rows = [
            (
                a["path"],
                [
                    a["ssid"] or "Hidden Network",
                    str(a["signal"]) + "%",
                    a["security"],
                    "Connected"
                    if a["active"]
                    else "Saved"
                    if a["profiles"]
                    else "Available",
                ],
            )
            for a in adapter.get("networks", [])
        ]
        self.table_rows("networks", rows)
        for button in ("scan", "hidden", "wifi-connect", "disconnect", "forget"):
            self.query_one("#" + button, Button).disabled = not adapters

    async def load_proxy(self):
        status = await self.client.proxy("status")
        if not status["proxy"]["available"]:
            raise BackendError(
                "Mihomo is unavailable; enable the system proxy contribution"
            )
        self.groups = (await self.client.proxy("proxy-groups"))["groups"]
        for name in ("set-mode", "select-node", "test-node", "test-all"):
            self.query_one("#" + name, Button).disabled = False
        if self.group not in {g["name"] for g in self.groups}:
            self.group = self.groups[0]["name"] if self.groups else ""
        self.select_options(
            "group", [(g["name"], g["name"]) for g in self.groups], self.group
        )
        self.query_one("#mode", Select).value = status["proxy"]["mode"]
        self.query_one("#proxy-state", Static).update(
            Text("Mihomo Available · " + safe(status["proxy"]["mode"]))
        )
        self.show_nodes()

    def show_nodes(self):
        group = next((g for g in self.groups if g["name"] == self.group), {})
        self.table_rows(
            "nodes",
            [
                (
                    name,
                    [
                        name,
                        "Selected" if group.get("selected") == name else "",
                        self.delays.get(name, "Not Tested"),
                    ],
                )
                for name in group.get("nodes", [])
            ],
        )

    def show_devices(self, data):
        self.device_data = data
        audio = data["audio"]
        self.select_options(
            "output",
            [(s["description"], s["name"]) for s in audio["sinks"]],
            audio["default"],
        )
        sink = next((s for s in audio["sinks"] if s["name"] == audio["default"]), None)
        self.query_one("#volume", Slider).disabled = sink is None
        self.query_one("#mute", Button).disabled = sink is None
        self.query_one("#set-output", Button).disabled = not audio["sinks"]
        if sink:
            self.query_one("#volume", Slider).value = min(100, sink["volume"])
        self.query_one("#audio-state", Static).update(
            Text(
                "Muted"
                if sink and sink["mute"]
                else "Ready"
                if sink
                else "Audio backend or output unavailable"
            )
        )
        self.select_options(
            "backlight", [(b["name"], b["name"]) for b in data["backlights"]]
        )
        self.update_backlight()

    def update_backlight(self):
        name = self.query_one("#backlight", Select).value
        backlight = next(
            (
                b
                for b in getattr(self, "device_data", {}).get("backlights", [])
                if b["name"] == name
            ),
            None,
        )
        self.query_one("#brightness", Slider).disabled = backlight is None
        if backlight:
            self.query_one("#brightness", Slider).value = backlight["percent"]

    def show_information(self, data):
        memory = data["memoryKiB"]
        lines = [
            "Current Device",
            "",
            "Model       " + data["model"],
            "Board       " + data["board"],
            "CPU         " + data["cpu"],
            "Memory      "
            + (
                f"{memory / 1048576:.1f} GiB total · {data['availableMemoryKiB'] / 1048576:.1f} GiB available"
                if memory
                else "Unavailable"
            ),
            "OS          " + data["os"],
            "Kernel      " + data["kernel"],
            "Folio Target " + data["target"],
            "Uptime      " + str(round(data["uptimeSeconds"] / 60)) + " minutes",
            "",
            "Graphics",
        ]
        lines += [g["name"] + " · " + g["driver"] for g in data["gpus"]] or [
            "Unavailable"
        ]
        lines += ["", "Connected Displays"] + [
            d["name"] + " · " + ", ".join(d["modes"][:3]) for d in data["displays"]
        ]
        lines += ["", "Network Interfaces", ", ".join(data["interfaces"])]
        if data["batteries"]:
            lines += ["", "Battery"] + [
                b["name"] + " · " + b["capacity"] + "% · " + b["status"]
                for b in data["batteries"]
            ]
        self.query_one("#information", Static).update(
            Text("\n".join(safe(line) for line in lines))
        )

    @on(Select.Changed)
    def selection(self, event):
        if (
            event.select.id == "adapter"
            and event.value != Select.NULL
            and event.value != self.interface
        ):
            self.interface = event.value
            self.show_wifi(self.wifi_data)
        elif (
            event.select.id == "group"
            and event.value != Select.NULL
            and event.value != self.group
        ):
            self.group = event.value
            self.show_nodes()
        elif event.select.id == "backlight":
            self.update_backlight()

    @work(group="operation", exclusive=False, description="Module operation")
    async def operate(self, domain, action, **fields):
        if self.busy:
            self.message("Another operation is in progress")
            return
        self.busy = True
        self.message("Connecting…" if action == "connect" else "Working…")
        try:
            data = await getattr(self.client, domain)(action, **fields)
            if domain == "wifi":
                self.show_wifi(data)
            elif domain == "devices":
                self.show_devices(data)
            self.message("Connected" if action == "connect" else "Operation completed")
        except (BackendError, OSError) as error:
            self.message("Failed: " + str(error))
        except Exception:  # noqa: BLE001 -- sanitize errors at the credential boundary.
            # Never expose locals/credential-bearing requests in a UI traceback.
            self.message("Operation failed; refresh state before retrying")
        finally:
            fields.pop("password", None)
            self.busy = False
            self.refresh_page()

    @on(Slider.Changed)
    def slider_changed(self, event):
        name = event.slider.id
        if name in self.slider_timers:
            self.slider_timers[name].stop()

        def send():
            if self.busy:
                self.slider_timers[name] = self.set_timer(0.3, send)
                return
            if name == "volume":
                self.operate("devices", "volume", level=event.slider.value)
            else:
                device = self.query_one("#backlight", Select).value
                if device != Select.NULL:
                    self.operate(
                        "devices", "brightness", level=event.slider.value, device=device
                    )

        self.slider_timers[name] = self.set_timer(0.3, send)

    @on(Button.Pressed)
    def button(self, event):
        name = event.button.id
        if self.busy:
            self.message("Another operation is in progress")
            return
        if name == "scan":
            self.operate("wifi", "scan", interface=self.interface)
        elif name == "radio":
            enabled = not self.wifi_data.get("enabled", False)
            self.push_screen(
                Confirm(
                    "Turn Wi-Fi "
                    + (
                        "on?"
                        if enabled
                        else "off? Active connections will be interrupted."
                    )
                ),
                lambda yes: (
                    self.operate("wifi", "radio", enabled=enabled) if yes else None
                ),
            )
        elif name in ("wifi-connect", "hidden"):
            network = self.network() if name == "wifi-connect" else None
            if name == "wifi-connect" and not network:
                self.message("Select a network first")
            elif network and network["security"] not in (
                "Open",
                "WPA Personal",
                "WPA3",
            ):
                self.message("Enterprise and legacy authentication are not supported")
            else:
                self.push_screen(
                    Connect(network),
                    lambda data: (
                        self.operate(
                            "wifi", "connect", interface=self.interface, **data
                        )
                        if data
                        else None
                    ),
                )
        elif name == "disconnect":
            self.push_screen(
                Confirm("Disconnect Wi-Fi? This may interrupt remote access."),
                lambda yes: (
                    self.operate("wifi", "disconnect", interface=self.interface)
                    if yes
                    else None
                ),
            )
        elif name == "forget":
            network = self.network()
            if not network or not network["profiles"]:
                self.message("Select a saved network first")
            else:
                profile = network["profiles"][0]
                self.push_screen(
                    Confirm(
                        "Forget "
                        + safe(network["ssid"])
                        + "?\nProfile: "
                        + profile
                        + "\nThe active connection may be affected."
                    ),
                    lambda yes: (
                        self.operate(
                            "wifi", "forget", interface=self.interface, uuid=profile
                        )
                        if yes
                        else None
                    ),
                )
        elif name == "proxy-refresh":
            self.refresh_page()
        elif name == "set-mode":
            self.operate(
                "proxy", "proxy-mode", mode=self.query_one("#mode", Select).value
            )
        elif name == "select-node":
            node = self.selected("nodes")
            if node and self.group:
                self.operate("proxy", "proxy-group-select", group=self.group, node=node)
        elif name == "test-node":
            self.test_nodes([self.selected("nodes")])
        elif name == "test-all":
            if self.testing:
                self.testing = False
            else:
                nodes = next(
                    (g["nodes"] for g in self.groups if g["name"] == self.group), []
                )
                self.test_nodes(nodes)
        elif name == "mute":
            self.operate("devices", "mute")
        elif name == "set-output":
            output = self.query_one("#output", Select).value
            if output != Select.NULL:
                self.operate("devices", "output", name=output)

    @work(group="probes", exclusive=False)
    async def test_nodes(self, nodes):
        if self.testing:
            return
        self.testing = True
        deadline = time.monotonic() + 120
        self.query_one("#test-all", Button).label = "Stop Tests"
        try:
            for node in nodes:
                if not node or not self.testing or time.monotonic() > deadline:
                    break
                self.delays[node] = "Testing"
                self.show_nodes()
                try:
                    result = await self.client.proxy("proxy-delay", node=node)
                    self.delays[node] = str(result["delay"]) + " ms"
                except (BackendError, OSError):
                    self.delays[node] = "Timeout / Unavailable"
                self.show_nodes()
                await asyncio.sleep(0.1)
        finally:
            self.testing = False
            self.query_one("#test-all", Button).label = "Test All"
            self.message(
                "Latency tests stopped. Results apply only to the configured test endpoint."
            )
