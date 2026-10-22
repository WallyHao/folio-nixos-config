# Adapted from Sylphy 9cba023d90c4485b33a91e2d12724b6920580580.
# Python/Pillow render assets during the build; neither is a runtime CLI dependency.
{ pkgs, theme }:
let
  palette = theme.colors.palettes.${theme.colors.appearance};
  name = "GoogleDot-Folio";
  colors = {
    inherit name;
    size = theme.cursor-size;
    baseColor = palette.bg0;
    outlineColor = palette.${theme.colors.roles.accent};
    successColor = palette.green;
    errorColor = palette.red;
    mutedColor = palette.grey1;
    animationColors = map (key: palette.${key}) [ "purple" "yellow" "green" "blue" ];
  };
  python = pkgs.python3.withPackages (p: [ p.pillow ]);
  renderer = pkgs.writeText "folio-cursor-render.py" ''
"""Render upstream static SVGs and recolor its existing animated frames at build time."""
import colorsys
import json
from pathlib import Path
import subprocess
import sys

from PIL import Image


def rgb(value):
    return tuple(int(value[i:i + 2], 16) for i in (1, 3, 5))


def recolor_animation(image, outline, accents):
    # Upstream busy frames have a white surround and four shaded Google colors.
    # Preserve alpha, shading and frame timing while mapping each hue to the theme.
    source_hues = (0.025, 0.114, 0.361, 0.591)
    pixels = []
    for red, green, blue, alpha in image.convert("RGBA").getdata():
        hue, saturation, value = colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)
        if saturation < 0.08:
            color = tuple(round(channel * value) for channel in outline)
        else:
            index = min(range(4), key=lambda i: min(abs(hue - source_hues[i]), 1 - abs(hue - source_hues[i])))
            accent = accents[index]
            # Do not carry Google's high saturation into the muted Everforest palette.
            color = tuple(round(channel * min(1, value / 0.75)) for channel in accent)
        pixels.append((*color, alpha))
    result = Image.new("RGBA", image.size)
    result.putdata(pixels)
    return result


def main():
    settings = json.loads(Path(sys.argv[1]).read_text())
    destination = Path("bitmaps/Folio")
    destination.mkdir(parents=True, exist_ok=True)
    for source in sorted(Path("svg/static").glob("*.svg")):
        svg = source.read_text()
        for original, replacement in {
            "#00FF00": settings["baseColor"],
            "#0000FF": settings["outlineColor"],
            "#00D161": settings["successColor"],
            "#FC3C36": settings["errorColor"],
            "#414141": settings["mutedColor"],
        }.items():
            svg = svg.replace(original, replacement)
        subprocess.run(["rsvg-convert", "-w", "200", "-h", "200", "-o", str(destination / (source.stem + ".png"))], input=svg.encode(), check=True)
    for source in sorted(Path("bitmaps/GoogleDot-White").glob("*-*.png")):
        if source.name.startswith(("wait-", "left_ptr_watch-")):
            with Image.open(source) as image:
                recolor_animation(image, rgb(settings["outlineColor"]), list(map(rgb, settings["animationColors"]))).save(destination / source.name)


if __name__ == "__main__":
    main()
  '';
in pkgs.stdenvNoCC.mkDerivation {
  pname = "googledot-folio";
  version = "2.0.0";
  src = pkgs.fetchzip {
    url = "https://codeload.github.com/ful1e5/Google_Cursor/tar.gz/refs/tags/v2.0.0";
    extension = "tar.gz";
    hash = "sha256-vzNtm3gwkGjHlC2G7dTsieQLOu67GnB3BIUSD6pZ6AA=";
  };
  nativeBuildInputs = [ python pkgs.librsvg pkgs.clickgen ];
  buildPhase = ''
    runHook preBuild
    python ${renderer} ${pkgs.writeText "folio-cursor-colors.json" (builtins.toJSON colors)}
    ctgen build.toml -p x11 -s ${pkgs.lib.concatMapStringsSep " " toString (pkgs.lib.unique ([ colors.size (colors.size * 2) ] ++ [ 22 24 28 32 40 44 48 56 64 72 80 88 96 ]))} \
      -d bitmaps/Folio -n ${name} -c 'GoogleDot with Folio Everforest colors'
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/icons $out/share/licenses/google-cursor
    cp -r themes/${name} $out/share/icons/
    cp LICENSE $out/share/licenses/google-cursor/
    runHook postInstall
  '';
  passthru = { cursorName = name; cursorSettings = colors; };
  meta = {
    description = "GoogleDot cursor assets with the selected Everforest palette";
    homepage = "https://github.com/ful1e5/Google_Cursor";
    license = pkgs.lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
  };
}
