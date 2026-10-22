import json
import os
import sys

import gi

version, appearance = sys.argv[1:]
gi.require_version("Gtk", f"{version}.0")
from gi.repository import Gtk, GLib, Pango

if version == "4":
    gi.require_version("Adw", "1")
    from gi.repository import Adw

    Adw.init()
    Adw.StyleManager.get_default().set_color_scheme(
        Adw.ColorScheme.FORCE_DARK if appearance == "dark" else Adw.ColorScheme.FORCE_LIGHT
    )
else:
    Gtk.init([])

settings = Gtk.Settings.get_default()
settings.set_property("gtk-font-name", "Maple Mono NF CN 16")
if version == "3":
    settings.set_property("gtk-theme-name", "adw-gtk3-dark" if appearance == "dark" else "adw-gtk3")

# Reject parser errors as well as checking rendered widget properties.
provider = Gtk.CssProvider()
errors = []
provider.connect("parsing-error", lambda _provider, _section, error: errors.append(str(error)))
provider.load_from_path(os.path.join(os.environ["XDG_CONFIG_HOME"], f"gtk-{version}.0", "gtk.css"))
assert not errors, errors

window = Adw.Window() if version == "4" else Gtk.Window()
label = Gtk.Label(label="Folio GTK 字体")
if version == "4":
    window.set_content(label)
    window.present()
else:
    window.add(label)
    window.show_all()

context = GLib.MainContext.default()
for _ in range(30):
    while context.pending():
        context.iteration(False)

font = label.get_pango_context().get_font_description()
assert font.get_family() == "Maple Mono NF CN", font.to_string()
# CSS point sizes resolve to absolute pixels at Xvfb's default 96 DPI.
expected_size = 16 * Pango.SCALE * (96 / 72 if font.get_size_is_absolute() else 1)
assert abs(font.get_size() - expected_size) <= 1, font.to_string()
color = label.get_style_context().get_color() if version == "4" else label.get_style_context().get_color(Gtk.StateFlags.NORMAL)
palette = json.load(open(os.environ["FOLIO_TEST_PALETTE"]))["palettes"][appearance]
expected = palette["fg"]


def rgb(value):
    return "#" + "".join(f"{round(channel * 255):02x}" for channel in (value.red, value.green, value.blue))


assert rgb(color) == expected, (rgb(color), expected)
if version == "4":
    # libadwaita's accent class reads --accent-color, not the legacy named color.
    label.add_css_class("accent")
    while context.pending():
        context.iteration(False)
    accent = rgb(label.get_style_context().get_color())
    assert accent == palette["yellow"], accent

print(f"GTK {version} {appearance}: font={font.to_string()} foreground={rgb(color)}; CSS valid")
window.destroy()
