"""Render README wordmarks with fontTools and locally installed fonts."""

from pathlib import Path
import subprocess

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont


ROOT = Path(__file__).resolve().parents[1]
TITLE = "Folio"
SUBTITLE = "一份为日常使用而打磨的个人 NixOS 桌面配置。"


def outlines(text, family, size, baseline, spacing=0):
    filename = subprocess.check_output(["fc-match", "-f", "%{file}", family], text=True).strip()
    with TTFont(filename) as font:
        glyphs = font.getGlyphSet()
        cmap = font.getBestCmap()
        scale = size / font["head"].unitsPerEm
        names = [cmap[ord(char)] for char in text]
        width = sum(glyphs[name].width * scale for name in names)
        width += spacing * (len(names) - 1)
        x = (760 - width) / 2
        pen = SVGPathPen(glyphs, ntos=lambda number: f"{number:.2f}".rstrip("0").rstrip("."))
        for name in names:
            glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x, baseline)))
            x += glyphs[name].width * scale + spacing
        return pen.getCommands()


def main():
    title = outlines(TITLE, "TeX Gyre Pagella:style=Regular", 108, 117, spacing=2)
    subtitle = outlines(SUBTITLE, "LXGW WenKai GB:style=Regular", 22, 169)
    directory = ROOT / "assets" / "branding"
    directory.mkdir(parents=True, exist_ok=True)
    for mode, foreground in (
        ("light", "#40534a"),
        ("dark", "#d3c6aa"),
    ):
        (directory / f"header-{mode}.svg").write_text(
            '<svg xmlns="http://www.w3.org/2000/svg" width="760" height="204" '
            'viewBox="0 0 760 204" role="img" aria-labelledby="title description">\n'
            f'  <title id="title">{TITLE}</title>\n'
            f'  <desc id="description">{SUBTITLE}</desc>\n'
            "  <!-- TeX Gyre Pagella / LXGW WenKai GB; outlined for consistent rendering. -->\n"
            f'  <path fill="{foreground}" d="{title}"/>\n'
            f'  <path fill="{foreground}" d="{subtitle}"/>\n'
            "</svg>\n",
            encoding="utf-8",
        )


if __name__ == "__main__":
    main()
