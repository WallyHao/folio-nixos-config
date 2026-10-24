"""Keep the pinned Yazi icon glyphs and rules, recoloring every icon consistently."""

from pathlib import Path
import sys
import tomllib

import tomli_w

preset, base, color, output = sys.argv[1:]
theme = tomllib.loads(Path(base).read_text())
icons = tomllib.loads(Path(preset).read_text())["icon"]
for rules in icons.values():
    for rule in rules:
        rule["fg"] = color
theme["icon"] = icons
with Path(output).open("wb") as stream:
    tomli_w.dump(theme, stream)
