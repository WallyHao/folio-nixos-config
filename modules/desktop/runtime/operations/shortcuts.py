"""Show the active Niri bindings in a compact, theme-aware reference window."""
import json
import os
from pathlib import Path
import re
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango


def bindings(path):
    groups = {name: [] for name in ("Apps & Desktop", "Windows & Layout", "Workspaces", "Capture & Session")}
    workspace = set()
    for key, title, action in re.findall(
        r'^\s*([\w+]+)\s+[^\n]*?hotkey-overlay-title="([^"]+)"\s*\{([^\n]+)\}',
        path.read_text(), re.M,
    ):
        if "workspace" in action and re.search(r'\+(?:[0-9])$', key):
            shifted = "+Shift+" in key
            if shifted in workspace:
                continue
            workspace.add(shifted)
            key = re.sub(r'[0-9]$', '1…9 / 0', key)
            title = "Move window to workspace 1–10" if shifted else "Focus workspace 1–10"
            group = "Workspaces"
        elif "screenshot" in action or "session" in action or "quit;" in action:
            group = "Capture & Session"
        elif "spawn" in action or "overview" in action:
            group = "Apps & Desktop"
        else:
            group = "Windows & Layout"
        key = re.sub(r'^(Super|Mod|Win)', 'Win', key)
        key = key.replace("Return", "Enter").replace("Slash", "/")
        for word, arrow in (("Left", "←"), ("Right", "→"), ("Up", "↑"), ("Down", "↓")):
            key = key.replace(word, arrow)
        groups[group].append((key.replace("+", " + "), LABELS.get(title, title)))
    return groups


LABELS = {
    "Open application and window launcher": "Application launcher",
    "Open clipboard history": "Clipboard history",
    "Open Folio panel": "Folio panel",
    "Open terminal": "Terminal",
    "Close window": "Close window",
    "Show workspace overview": "Workspace overview",
    "Show all keyboard shortcuts": "Keyboard Shortcuts",
    "Toggle half/full workspace width": "Toggle half / full width",
    "Toggle workspace centering": "Center column",
    "Capture full screen": "Full screen capture",
    "Capture screen region": "Region capture",
    "Focus column left": "Focus left column",
    "Focus column right": "Focus right column",
    "Focus window above": "Focus window above",
    "Focus window below": "Focus window below",
    "Move column left": "Move column left",
    "Move column right": "Move column right",
    "Exit Niri (confirm)": "Exit Niri (confirm)",
    "Reboot (confirm)": "Reboot now (confirm)",
    "Power off (confirm)": "Power off now (confirm)",
}


class Shortcuts(Gtk.Application):
    def __init__(self, theme):
        super().__init__(application_id="org.folio.Shortcuts", flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.theme = theme

    def do_activate(self):
        if self.get_active_window():
            self.get_active_window().present()
            return
        theme = self.theme
        css = Gtk.CssProvider()
        css.load_from_data(('''
            window { background: %(background)s; color: %(foreground)s; }
            * { font-family: %(font)s; font-size: %(size)spx; }
            .title { font-size: 22px; font-weight: bold; color: %(accent)s; }
            .hint { color: %(muted)s; }
            .card { background: %(surface)s; border: 1px solid %(border)s;
                    border-radius: 12px; padding: 16px; }
            .section { color: %(accent)s; font-weight: bold; margin-bottom: 10px; }
            .key { color: %(accent)s; font-weight: bold; }
        ''' % theme).encode())
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        window = Gtk.ApplicationWindow(application=self, title="Shortcuts · Folio")
        window.set_default_size(640, 600)
        def fit_monitor(widget, event=None):
            monitor = widget.get_display().get_monitor_at_window(widget.get_window())
            area = monitor.get_workarea()
            # Leave room for decorations and compositor borders within half an output.
            width = max(1, area.width // 2 - 24)
            height = max(1, int(area.height * 0.8) - 24)
            geometry = Gdk.Geometry()
            geometry.max_width, geometry.max_height = width, height
            widget.set_geometry_hints(None, geometry, Gdk.WindowHints.MAX_SIZE)
            current_width, current_height = widget.get_size()
            if current_width > width or current_height > height:
                widget.resize(min(current_width, width), min(current_height, height))
            return False
        window.connect("map-event", fit_monitor)
        window.connect("configure-event", fit_monitor)
        window.connect("key-press-event", lambda w, event: w.close() if event.keyval == Gdk.KEY_Escape else False)
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=16)
        window.add(outer)
        heading = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        outer.pack_start(heading, False, False, 0)
        title = Gtk.Label(label="Keyboard Shortcuts", xalign=0)
        title.set_line_wrap(True)
        title.set_width_chars(1)
        title.get_style_context().add_class("title")
        heading.pack_start(title, True, True, 0)
        hint = Gtk.Label(label="Win = Super  ·  Esc to close", xalign=0)
        hint.set_line_wrap(True)
        hint.set_width_chars(1)
        hint.get_style_context().add_class("hint")
        heading.pack_end(hint, False, False, 0)
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        outer.pack_start(scroll, True, True, 0)
        grid = Gtk.Grid(column_spacing=16, row_spacing=16, column_homogeneous=True)
        scroll.add(grid)
        config = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "niri/config.kdl"
        cards = []

        def wrapped_label(value, style=None):
            label = Gtk.Label(label=value, xalign=0)
            label.set_line_wrap(True)
            label.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR)
            label.set_width_chars(1)
            label.set_hexpand(True)
            if style:
                label.get_style_context().add_class(style)
            return label

        for index, (name, rows) in enumerate(bindings(config).items()):
            card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=7)
            card.get_style_context().add_class("card")
            label = wrapped_label(name, "section")
            card.pack_start(label, False, False, 0)
            table = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
            card.pack_start(table, False, False, 0)
            for row, (key, description) in enumerate(rows):
                entry = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
                entry.pack_start(wrapped_label(key, "key"), False, False, 0)
                entry.pack_start(wrapped_label(description), False, False, 0)
                table.pack_start(entry, False, False, 0)
            cards.append(card)
            grid.attach(card, index % 2, index // 2, 1, 1)

        columns = 2

        def reflow(widget, allocation):
            nonlocal columns
            count = 2 if allocation.width >= 760 else 1
            if count == columns:
                return
            columns = count

            def arrange():
                for index, card in enumerate(cards):
                    grid.child_set_property(card, "left-attach", index % columns)
                    grid.child_set_property(card, "top-attach", index // columns)
                grid.queue_resize()
                return False

            GLib.idle_add(arrange)

        window.connect("size-allocate", reflow)
        window.show_all()
        window.present()


if __name__ == "__main__":
    Shortcuts(json.loads(Path(sys.argv[1]).read_text())).run([sys.argv[0]])
