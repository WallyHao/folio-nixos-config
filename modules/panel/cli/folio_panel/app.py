"""English, text-first terminal controls. Domain effects belong to module clients."""
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
from textual.theme import Theme
from textual.widget import Widget
from textual.widgets import (
    Button,
    DataTable,
    Footer,
    Input,
    Select,
    Static,
    TabbedContent,
    TabPane,
)

from .client import BackendError, Client


def safe(value):
    """External SSIDs/node/device names are plain text, never terminal markup."""
    return re.sub(r"[\x00-\x1f\x7f-\x9f]", "", str(value))


# Follow the terminal palette instead of imposing a second application theme.
# Foot is configured with Everforest ANSI colours, so the same roles work there
# and remain readable in any other correctly configured terminal.
FOLIO_THEME = Theme(
    name="folio",
    primary="ansi_green",
    secondary="ansi_blue",
    accent="ansi_yellow",
    warning="ansi_yellow",
    error="ansi_red",
    success="ansi_green",
    foreground="ansi_default",
    background="ansi_default",
    surface="ansi_default",
    panel="ansi_default",
    boost="ansi_default",
    dark=True,
    ansi=True,
    variables={
        "ansi-background": "ansi_default",
        "ansi-foreground": "ansi_default",
        "border": "ansi_bright_black",
        "border-blurred": "ansi_bright_black",
        "text-muted": "ansi_bright_black",
        "text-disabled": "ansi_bright_black",
        "foreground-muted": "ansi_bright_black",
        "block-cursor-foreground": "ansi_default",
        "block-cursor-background": "ansi_bright_black",
        "block-cursor-text-style": "none",
        "block-cursor-blurred-foreground": "ansi_default",
        "block-cursor-blurred-background": "ansi_default",
        "block-cursor-blurred-text-style": "none",
        "block-hover-background": "ansi_bright_black",
        "footer-foreground": "ansi_default",
        "footer-background": "ansi_default",
        "footer-key-foreground": "ansi_yellow",
        "footer-key-background": "transparent",
        "footer-description-foreground": "ansi_bright_black",
        "footer-description-background": "transparent",
        "footer-item-background": "transparent",
        "input-selection-background": "ansi_blue",
        "input-selection-foreground": "ansi_default",
        "button-foreground": "ansi_default",
        "button-color-foreground": "ansi_default",
        "button-focus-text-style": "bold",
    },
)


def status_line(parts):
    """Compose one quiet text line from (value, style) fragments."""
    text = Text()
    for index, (value, style) in enumerate(parts):
        if index:
            text.append("  ·  ", style="dim")
        text.append(safe(value), style=style)
    return text


def action(label, button_id, variant="default"):
    """Render a command as text rather than as a bordered control."""
    button = Button(label, id=button_id, variant=variant, compact=True, flat=True)
    button.active_effect_duration = 0
    return button


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
            return Text("unavailable", style="dim")
        width = max(4, self.size.width - 10)
        filled = round(self.value * width / 100)
        return Text.assemble(
            ("━" * filled, "bold yellow" if self.has_focus else "yellow"),
            ("─" * (width - filled), "dim"),
            (f" {self.value:3d}%", "dim"),
        )

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
            yield Static(Text(self.message, style="bold"))
            with Horizontal(classes="dialog-actions"):
                yield action("cancel", "cancel")
                yield action("confirm", "confirm", "warning")

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
            yield Static(
                Text(
                    "connect to wi-fi" if self.network else "hidden network",
                    style="bold yellow",
                )
            )
            if self.network:
                yield Static(
                    Text(safe(self.network["ssid"]) + " · " + self.network["security"])
                )
                if self.network["profiles"]:
                    yield Static(
                        "leave password empty to reuse the saved profile.",
                        classes="note",
                    )
            else:
                yield Static("ssid", classes="field-label")
                yield Input(placeholder="network name", id="ssid", compact=True)
                yield Static("security", classes="field-label")
                yield Select(
                    [(v, v) for v in ("WPA Personal", "WPA3", "Open")],
                    value="WPA Personal",
                    allow_blank=False,
                    id="security",
                    compact=True,
                )
            yield Static("password", classes="field-label")
            yield Input(
                placeholder="network password",
                password=True,
                id="password",
                compact=True,
            )
            yield Static(
                "credentials are stored by NetworkManager for this user.",
                classes="note",
            )
            with Horizontal(classes="dialog-actions"):
                yield action("show", "toggle-password")
                yield action("cancel", "cancel")
                yield action("connect", "connect", "primary")

    @on(Button.Pressed)
    def choose(self, event):
        if event.button.id == "toggle-password":
            password = self.query_one("#password", Input)
            password.password = not password.password
            event.button.label = "show" if password.password else "hide"
        elif event.button.id == "cancel":
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
    Screen { background: $background; color: $foreground; }
    #title { height: 1; padding: 0 2; }
    TabbedContent { height: 1fr; }
    TabbedContent > ContentSwitcher { height: 1fr; }
    Tabs { height: 2; padding: 0 2; background: transparent; }
    Tab { height: 1; padding: 0 1; background: transparent; color: $text-muted; }
    Tab:hover { background: transparent; color: $foreground; }
    Tab.-active { color: $accent; text-style: bold; }
    Underline { height: 1; }
    Underline > .underline--bar { color: $accent; background: $text-muted; }
    TabPane { height: 1fr; padding: 1 0; align-horizontal: center; }
    .page { width: 100%; max-width: 110; height: 1fr; padding: 0 2; }
    .field { height: auto; min-height: 1; }
    .field-label { width: 10; height: 1; color: $text-muted; }
    .section-label { height: 1; margin-top: 1; color: $text-muted; }
    .note { height: auto; margin-top: 1; color: $text-muted; }
    .actions { height: 1; margin-top: 1; }
    #wifi-state, #proxy-state, #audio-state { height: auto; margin-bottom: 1; }
    #banner { height: 1; padding: 0 2; color: $text-muted; }
    DataTable.list {
        height: auto; max-height: 1fr; min-height: 3; padding: 0; border: none;
        background: transparent; background-tint: transparent;
    }
    DataTable.list > .datatable--header {
        background: transparent; color: $text-muted; text-style: none;
    }
    DataTable.list > .datatable--cursor {
        background: transparent; color: $accent; text-style: bold;
    }
    DataTable.list > .datatable--even-row,
    DataTable.list > .datatable--odd-row { background: transparent; }
    DataTable.list > .datatable--hover {
        background: transparent; color: $foreground;
    }
    DataTable.list:focus { background-tint: transparent; }
    DataTable.list:focus > .datatable--cursor {
        background: transparent; color: $accent; text-style: bold;
    }
    Button {
        height: 1; min-width: 0; padding: 0 1;
        border: none; background: transparent; color: $text-muted;
    }
    Button:hover { border: none; background: transparent; color: $foreground; }
    Button:focus {
        border: none; background: transparent; color: $accent; text-style: bold;
    }
    Button.-primary { border: none; background: transparent; color: $accent; }
    Button.-warning { border: none; background: transparent; color: $warning; }
    Button:disabled {
        border: none; background: transparent; color: $text-disabled;
    }
    Input { height: 1; padding: 0; border: none; background: transparent; }
    Input:focus {
        border: none; background: transparent; background-tint: transparent;
    }
    Select > SelectCurrent {
        border: none; background: transparent; padding: 0; height: 1;
    }
    Select:focus > SelectCurrent {
        border: none; background: transparent; background-tint: transparent;
    }
    SelectOverlay { border: none; background: $background; padding: 0; }
    OptionList { border: none; background: $background; padding: 0 1; }
    OptionList > .option-list--option-highlighted {
        background: transparent; color: $accent; text-style: bold;
    }
    Slider { height: 1; padding: 0; border: none; background: transparent; }
    Slider:focus { border: none; background: transparent; }
    Slider:disabled { opacity: 40%; }
    Footer { padding: 0 2; background: transparent; color: $text-muted; }
    FooterKey { background: transparent; }
    FooterKey > .footer-key--key { background: transparent; color: $accent; }
    FooterKey > .footer-key--description {
        background: transparent; color: $text-muted;
    }
    Confirm, Connect { align: center middle; background: $background; }
    .dialog {
        width: 60; max-width: 95%; height: auto; max-height: 95%;
        overflow-y: auto; padding: 1 2; border: none;
        border-left: thick $accent; background: $background;
    }
    .dialog .field-label { width: auto; margin-top: 1; }
    .dialog Static { height: auto; }
    .dialog Input, .dialog Select { margin-bottom: 1; }
    .dialog-actions { height: 1; margin-top: 1; align-horizontal: right; }
    #information { height: auto; }
    """
    BINDINGS: ClassVar = [
        ("q", "quit", "quit"),
        ("r", "refresh", "refresh"),
        ("?", "help", "help"),
    ]

    def __init__(self, client=None):
        super().__init__()
        self.register_theme(FOLIO_THEME)
        self.theme = "folio"
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
        yield Static(
            Text.assemble(("folio", "bold yellow"), ("  panel", "dim")),
            id="title",
        )
        with TabbedContent(initial="wifi"):
            with TabPane("wi-fi", id="wifi"):
                with Vertical(classes="page"):
                    with Horizontal(classes="field"):
                        yield Static("adapter", classes="field-label")
                        yield Select(
                            [], id="adapter", prompt="No Wi-Fi Adapter", compact=True
                        )
                    yield Static(
                        "Loading wireless state…", id="wifi-state", markup=False
                    )
                    yield DataTable(id="networks", cursor_type="row", classes="list")
                    with Horizontal(classes="actions"):
                        yield action("scan", "scan")
                        yield action("radio", "radio")
                        yield action("hidden", "hidden")
                        yield action("connect", "wifi-connect", "primary")
                        yield action("disconnect", "disconnect")
                        yield action("forget", "forget")
            with TabPane("proxy", id="proxy"):
                with Vertical(classes="page"):
                    yield Static("Loading proxy state…", id="proxy-state", markup=False)
                    with Horizontal(classes="field"):
                        yield Static("group", classes="field-label")
                        yield Select(
                            [],
                            id="group",
                            prompt="No selectable proxy group",
                            compact=True,
                        )
                        yield Static("mode", classes="field-label")
                        yield Select(
                            [(v, v) for v in ("rule", "global", "direct")],
                            value="rule",
                            allow_blank=False,
                            id="mode",
                            compact=True,
                        )
                    yield DataTable(id="nodes", cursor_type="row", classes="list")
                    with Horizontal(classes="actions"):
                        yield action("set mode", "set-mode")
                        yield action("select", "select-node", "primary")
                        yield action("latency", "test-node")
                        yield action("test all", "test-all")
                        yield action("refresh", "proxy-refresh")
            with TabPane("audio", id="controls"):
                with VerticalScroll(classes="page"):
                    yield Static("Loading audio state…", id="audio-state", markup=False)
                    with Horizontal(classes="field"):
                        yield Static("output", classes="field-label")
                        yield Select(
                            [], id="output", prompt="No audio output", compact=True
                        )
                    with Horizontal(classes="actions"):
                        yield action("set output", "set-output")
                        yield action("mute / unmute", "mute")
                    yield Static(
                        "volume · left/right to adjust", classes="section-label"
                    )
                    yield Slider(id="volume", disabled=True)
                    yield Static("backlight", classes="section-label")
                    with Horizontal(classes="field"):
                        yield Static("device", classes="field-label")
                        yield Select(
                            [],
                            id="backlight",
                            prompt="No supported backlight",
                            compact=True,
                        )
                    yield Slider(id="brightness", disabled=True)
                    yield Static(
                        "Runtime controls take effect immediately. They are not included in configuration rollback.",
                        classes="note",
                        markup=False,
                    )
            with TabPane("device", id="device"):
                with VerticalScroll(classes="page"):
                    yield Static(
                        "Loading device information…", id="information", markup=False
                    )
        yield Static("ready", id="banner", markup=False)
        yield Footer(compact=True, show_command_palette=False)

    async def on_mount(self):
        networks = self.query_one("#networks", DataTable)
        nodes = self.query_one("#nodes", DataTable)
        networks.add_columns("network", "signal", "security", "state")
        nodes.add_columns("node", "state", "latency")
        for table in (networks, nodes):
            table.show_row_labels = False
            table.zebra_stripes = False
            table.cell_padding = 1
        self.set_interval(8, self.poll)
        self.refresh_page()

    def message(self, value, style="dim"):
        self.query_one("#banner", Static).update(Text(safe(value), style=style))

    def action_help(self):
        self.message(
            "tab/shift+tab: focus · arrows: lists and sliders · enter: select · r: refresh · q: quit",
            "dim",
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
            self.message(str(error), "red")
            label = {
                "wifi": "wifi-state",
                "proxy": "proxy-state",
                "controls": "audio-state",
                "device": "information",
            }[page]
            self.query_one("#" + label, Static).update(
                Text("unavailable: " + safe(error), style="red")
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
        if not adapters:
            state = Text("No Wi-Fi Adapter", style="dim")
        else:
            link = adapter.get("state", "unavailable")
            parts = [
                (self.interface or "wireless", "bold"),
                (link, "green" if link == "connected" else "yellow"),
                (
                    "radio on" if data["enabled"] else "radio off",
                    "green" if data["enabled"] else "red",
                ),
            ]
            if not data["hardwareEnabled"]:
                parts.append(("hardware radio blocked", "red"))
            for address in adapter.get("addresses", [])[:2]:
                parts.append((address, "dim"))
            state = status_line(parts)
        self.query_one("#wifi-state", Static).update(state)
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
            status_line(
                [
                    ("mihomo", "bold"),
                    (status["proxy"]["mode"], "yellow"),
                    ("available", "green"),
                ]
            )
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
            status_line(
                [
                    (sink["description"], "bold"),
                    (
                        "muted" if sink["mute"] else "active",
                        "yellow" if sink["mute"] else "green",
                    ),
                    (f"{sink['volume']}%", "dim"),
                ]
            )
            if sink
            else Text("Audio backend or output unavailable", style="red")
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
        text = Text()

        def heading(label):
            text.append(label + "\n", style="bold yellow")

        def row(label, value):
            text.append(f"{label:<12}", style="dim")
            text.append(safe(value) + "\n")

        heading("device")
        row("model", data["model"])
        row("board", data["board"])
        row("cpu", data["cpu"])
        row(
            "memory",
            f"{memory / 1048576:.1f} GiB total · "
            f"{data['availableMemoryKiB'] / 1048576:.1f} GiB available"
            if memory
            else "unavailable",
        )
        row("os", data["os"])
        row("kernel", data["kernel"])
        row("target", data["target"])
        row("uptime", str(round(data["uptimeSeconds"] / 60)) + " minutes")

        text.append("\n")
        heading("graphics")
        for gpu in data["gpus"] or [{"name": "unavailable", "driver": ""}]:
            row("gpu", (gpu["name"] + " · " + gpu["driver"]).rstrip(" ·"))
        for display in data["displays"]:
            row("display", display["name"] + " · " + ", ".join(display["modes"][:3]))
        if not data["displays"]:
            row("display", "unavailable")

        text.append("\n")
        heading("network")
        row("interfaces", ", ".join(data["interfaces"]) or "unavailable")

        if data["batteries"]:
            text.append("\n")
            heading("power")
            for battery in data["batteries"]:
                row(
                    "battery",
                    battery["name"]
                    + " · "
                    + battery["capacity"]
                    + "% · "
                    + battery["status"],
                )
        self.query_one("#information", Static).update(text)

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
            self.message("another operation is in progress", "yellow")
            return
        self.busy = True
        self.message("connecting…" if action == "connect" else "working…")
        try:
            data = await getattr(self.client, domain)(action, **fields)
            if domain == "wifi":
                self.show_wifi(data)
            elif domain == "devices":
                self.show_devices(data)
            self.message(
                "connected" if action == "connect" else "operation completed", "green"
            )
        except (BackendError, OSError) as error:
            self.message("failed: " + str(error), "red")
        except Exception:  # noqa: BLE001 -- sanitize errors at the credential boundary.
            # Never expose locals/credential-bearing requests in a UI traceback.
            self.message("operation failed; refresh state before retrying", "red")
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
            self.message("another operation is in progress", "yellow")
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
                self.message("select a network first", "yellow")
            elif network and network["security"] not in (
                "Open",
                "WPA Personal",
                "WPA3",
            ):
                self.message(
                    "enterprise and legacy authentication are not supported", "red"
                )
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
                self.message("select a saved network first", "yellow")
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
        self.query_one("#test-all", Button).label = "stop tests"
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
            self.query_one("#test-all", Button).label = "test all"
            self.message(
                "latency tests stopped; results apply only to the configured test endpoint."
            )
