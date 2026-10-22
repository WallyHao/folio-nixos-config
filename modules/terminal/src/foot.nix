{ }:
let
  # Adapted from Sylphy modules/foot/src/config.nix, revision 9cba023d90c4485b.
  # Standalone rendering and managed preferences share Folio's palette catalogue.
  defaultTheme.colors = import ../../appearance/lib { };

  colorHex =
    lib: value:
    if builtins.isString value && builtins.match "#[0-9A-Fa-f]{6}" value != null then
      lib.removePrefix "#" value
    else
      throw "folio-terminal: theme colors must be six-digit hexadecimal values";

  defaultFont = "DejaVu Sans Mono:size=11";

  renderConfig =
    {
      lib,
      theme,
      font ? defaultFont,
      padding ? "2x2",
      colorsFile ? null,
      opacity ? "1",
    }:
    let
      colors = theme.colors or { };
      appearance = colors.appearance or "dark";
      palettes = colors.palettes or { };
      roles = colors.roles or { };
      paletteFor =
        name:
        if builtins.hasAttr name palettes then
          palettes.${name}
        else
          throw "folio-terminal: missing ${name} palette";
      dark = paletteFor "dark";
      light = paletteFor "light";
      resolve = palette: key: colorHex lib (palette.${roles.${key} or key} or (palette.${key} or null));
      colorSection = name: palette: ''
        [colors-${name}]
        background=${resolve palette "background"}
        foreground=${resolve palette "foreground"}
        cursor=${resolve palette "background"} ${resolve palette "foreground"}
        selection-background=${resolve palette "selection"}
        selection-foreground=${resolve palette "foreground"}
        regular0=${colorHex lib (palette.bg0 or null)}
        regular1=${colorHex lib (palette.red or null)}
        regular2=${colorHex lib (palette.green or null)}
        regular3=${colorHex lib (palette.yellow or null)}
        regular4=${colorHex lib (palette.blue or null)}
        regular5=${colorHex lib (palette.purple or null)}
        regular6=${colorHex lib (palette.aqua or null)}
        regular7=${resolve palette "foreground"}
        bright0=${colorHex lib (palette.grey0 or null)}
        bright1=${colorHex lib (palette.red or null)}
        bright2=${colorHex lib (palette.green or null)}
        bright3=${colorHex lib (palette.yellow or null)}
        bright4=${colorHex lib (palette.blue or null)}
        bright5=${colorHex lib (palette.purple or null)}
        bright6=${colorHex lib (palette.aqua or null)}
        bright7=${resolve palette "foreground"}
        alpha=${toString opacity}
      '';
    in
    if !builtins.isString font || font == "" || lib.hasInfix "\n" font || lib.hasInfix "\r" font then
      throw "folio-terminal: font must be a non-empty single-line string"
    else if !builtins.isString padding || builtins.match "[0-9]+x[0-9]+" padding == null then
      throw "folio-terminal: padding must be nonnegative horizontal x vertical pixels, for example 15x15"
    else if
      !(builtins.elem appearance [
        "dark"
        "light"
      ])
    then
      throw "folio-terminal: appearance must be dark or light"
    else
      ''
        [main]
        font=${font}
        pad=${padding}
        initial-color-theme=${appearance}
        ${if colorsFile == null then "" else "include=${colorsFile}"}

        [cursor]
        style=block
        blink=no

        ${if colorsFile != null then "" else colorSection "dark" dark + colorSection "light" light}
      '';
in
{
  inherit defaultTheme defaultFont renderConfig;
}
