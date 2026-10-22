"""Guard contrast for Everforest's normal text surfaces and selected text."""
import json
from pathlib import Path
import sys


def luminance(color):
    channels = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return sum(c * weight for c, weight in zip(linear, (0.2126, 0.7152, 0.0722)))


def contrast(first, second):
    low, high = sorted((luminance(first), luminance(second)))
    return (high + 0.05) / (low + 0.05)


# Reference endpoints catch accidental changes to the luminance calculation.
assert contrast('#000000', '#ffffff') == 21
assert contrast('#808080', '#808080') == 1
palette = json.loads(Path(sys.argv[1]).read_text())
report = {}
for mode, colors in palette['palettes'].items():
    measurements = {}

    def require(foreground, background, minimum):
        ratio = contrast(colors[foreground], colors[background])
        assert ratio >= minimum, f'{mode}: {foreground}/{background} {ratio:.2f} < {minimum}'
        measurements[f'{foreground}/{background}'] = round(ratio, 2)

    for background in ('bg0', 'bg1'):
        require('fg', background, 7)
        for foreground in ('grey0', 'grey1', 'grey2', 'red', 'orange', 'yellow', 'green', 'aqua', 'blue', 'purple'):
            require(foreground, background, 4.5)
    require('fg', 'bg_visual', 4.5)
    require('bg_visual', 'bg0', 2 if mode == 'dark' else 1.5)
    levels = [luminance(colors[f'bg{i}']) for i in range(6)]
    assert levels == sorted(levels, reverse=mode == 'light'), f'{mode}: surface order is inverted'
    report[mode] = measurements
print(json.dumps(report, indent=2))
