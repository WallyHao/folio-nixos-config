{ pkgs }:
let
  lib = pkgs.lib;
  catalogue = import ../lib/catalogue.nix;
  variants = lib.concatMap (
    scheme:
    map
      (
        appearance:
        let
          colors = import ../lib { preferences = { inherit scheme appearance; }; };
          palette = colors.palettes.${appearance};
          theme = {
            inherit colors;
            font-family = "Maple Mono NF CN";
            font-size = 16;
            cursor-size = 42;
          };
          cursor = import ../src/cursor.nix { inherit pkgs theme; };
          foot = (import ../../terminal/src/foot.nix { }).renderConfig { inherit lib theme; };
          fuzzel = (import ../../desktop/src/fuzzel.nix { }).renderConfig { inherit lib theme; };
          gtk = import ../src/gtk-style.nix { inherit theme; };
          niri = (import ../../desktop/src/niri.nix { }).themeColors theme;
          codex = import ../../agents/src/codex/theme.nix { inherit theme; };
          yazi = import ../../terminal/src/yazi-theme.nix { inherit palette; };
        in
        assert lib.all (color: builtins.match "#[0-9a-fA-F]{6}" color != null) (
          builtins.attrValues palette
        );
        assert lib.all (key: builtins.hasAttr key palette) (builtins.attrValues colors.roles);
        assert lib.hasInfix (lib.removePrefix "#" palette.bg0) foot;
        assert lib.hasInfix (lib.removePrefix "#" palette.bg0) fuzzel;
        assert lib.hasInfix palette.bg0 gtk.gtk3;
        assert lib.hasInfix palette.bg0 gtk.gtk4;
        assert lib.hasInfix palette.bg0 codex;
        assert niri.background == palette.bg0;
        assert niri.accent == colors.semantic.accent;
        assert cursor.cursorSettings.outlineColor == niri.accent;
        assert cursor.cursorSettings.size == 42;
        assert lib.hasInfix "accent_color ${colors.semantic.accent}" gtk.gtk3;
        assert lib.hasInfix (lib.removePrefix "#" colors.semantic.accent) fuzzel;
        assert yazi.app.overall.bg == palette.bg0;
        {
          inherit scheme appearance;
          background = palette.bg0;
        }
      )
      [
        "dark"
        "light"
      ]
  ) (builtins.attrNames catalogue);
  model = builtins.readFile ../../manager/model/folio-environment.yang;
  valid = lib.all (name: lib.hasInfix "enum ${name};" model) (builtins.attrNames catalogue);
in
assert valid;
pkgs.writeText "folio-theme-rendering-check" (builtins.toJSON variants)
