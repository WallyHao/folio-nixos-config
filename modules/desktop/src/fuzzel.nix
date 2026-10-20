{ }:
let
  defaultTheme = {
    colors = {
      appearance = "dark";
      roles = {
        background = "bg0";
        surface = "bg1";
        foreground = "fg";
        muted = "grey1";
        accent = "green";
        border = "grey0";
        selection = "bg_visual";
      };
      palettes = {
        dark = {
          bg0 = "#202124"; bg1 = "#292a2d"; bg_visual = "#3c4043";
          fg = "#e8eaed"; grey0 = "#5f6368"; grey1 = "#9aa0a6";
          green = "#81c995"; yellow = "#fdd663"; red = "#f28b82"; blue = "#8ab4f8";
        };
        light = {
          bg0 = "#f8f9fa"; bg1 = "#ffffff"; bg_visual = "#e8eaed";
          fg = "#202124"; grey0 = "#dadce0"; grey1 = "#5f6368";
          green = "#188038"; yellow = "#f9ab00"; red = "#d93025"; blue = "#1a73e8";
        };
      };
    };
  };
  defaultFont = "sans-serif:size=11";
  hex = value:
    if builtins.isString value && builtins.match "#[0-9A-Fa-f]{6}" value != null
    then "${builtins.substring 1 6 value}ff"
    else throw "folio-desktop: theme colors must be six-digit hexadecimal values";
  renderConfig = { lib, theme, font ? defaultFont, width ? 40, lines ? 8, borderWidth ? 2, borderRadius ? 0, horizontalPadding ? 16, verticalPadding ? 10, innerPadding ? 8 }:
    let
      colors = theme.colors or { };
      appearance = colors.appearance or "dark";
      palettes = colors.palettes or { };
      roles = colors.roles or { };
      palette = palettes.${appearance} or (throw "folio-desktop: missing ${appearance} palette");
      resolve = role: hex (palette.${roles.${role} or role} or null);
      singleLine = value: builtins.isString value && value != "" && !(lib.hasInfix "\n" value) && !(lib.hasInfix "\r" value) && !(lib.hasInfix "[" value) && !(lib.hasInfix "]" value);
      integerIn = low: high: value: builtins.isInt value && value >= low && value <= high;
    in
    if !(builtins.elem appearance [ "dark" "light" ]) then throw "folio-desktop: appearance must be dark or light"
    else if !singleLine font then throw "folio-desktop: font must be a non-empty single-line FontConfig string without brackets"
    else if !(integerIn 20 100 width) then throw "folio-desktop: width must be an integer from 20 through 100"
    else if !(integerIn 1 30 lines) then throw "folio-desktop: lines must be an integer from 1 through 30"
    else if !(integerIn 0 10 borderWidth) then throw "folio-desktop: borderWidth must be an integer from 0 through 10"
    else if !(integerIn 0 100 borderRadius) then throw "folio-desktop: borderRadius must be an integer from 0 through 100"
    else if !(integerIn 0 100 horizontalPadding && integerIn 0 100 verticalPadding && integerIn 0 100 innerPadding) then throw "folio-desktop: padding must be an integer from 0 through 100"
    else ''
      [main]
      icons-enabled=no
      font=${font}
      # Match Foot's scale-based font sizing instead of physical monitor DPI.
      dpi-aware=no
      prompt="Search> "
      match-counter=yes
      show-actions=no
      width=${toString width}
      lines=${toString lines}
      horizontal-pad=${toString horizontalPadding}
      vertical-pad=${toString verticalPadding}
      inner-pad=${toString innerPadding}
      layer=overlay
      exit-on-keyboard-focus-loss=yes

      [border]
      width=${toString borderWidth}
      radius=${toString borderRadius}

      [colors]
      background=${resolve "background"}
      text=${resolve "foreground"}
      prompt=${resolve "accent"}
      placeholder=${resolve "muted"}
      input=${resolve "foreground"}
      match=${resolve "accent"}
      selection=${resolve "surface"}
      selection-text=${resolve "foreground"}
      selection-match=${resolve "accent"}
      counter=${resolve "muted"}
      border=${resolve "accent"}
    '';
in { inherit defaultTheme defaultFont renderConfig; }
