{ pkgs }:
let
  colors = builtins.fromJSON (builtins.readFile ../src/colors.json);
  styles = appearance: import ../src/gtk-style.nix {
    theme = { colors = colors // { inherit appearance; }; font-family = "Maple Mono NF CN"; font-size = 16; };
  };
in pkgs.runCommand "folio-gtk-appearance" {
  nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.pygobject3 ])) pkgs.gobject-introspection pkgs.xvfb-run ];
  buildInputs = [ pkgs.gtk3 pkgs.gtk4 pkgs.libadwaita ];
  FOLIO_TEST_PALETTE = ../lib/everforest.json;
  FONTCONFIG_FILE = pkgs.makeFontsConf { fontDirectories = [ pkgs.maple-mono.NF-CN ]; };
  GSETTINGS_SCHEMA_DIR = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas";
} ''
  mkdir -p "$out"
  export HOME="$TMPDIR/home"
  export XDG_DATA_DIRS="${pkgs.adw-gtk3}/share:$XDG_DATA_DIRS"
  export GSETTINGS_BACKEND=memory GSK_RENDERER=cairo GTK_A11Y=none
  ${pkgs.lib.concatMapStringsSep "\n" (appearance: let s = styles appearance; in ''
    export XDG_CONFIG_HOME="$TMPDIR/config-${appearance}"
    mkdir -p "$XDG_CONFIG_HOME/gtk-3.0" "$XDG_CONFIG_HOME/gtk-4.0"
    cp ${pkgs.writeText "gtk3-${appearance}.css" s.gtk3} "$XDG_CONFIG_HOME/gtk-3.0/gtk.css"
    cp ${pkgs.writeText "gtk4-${appearance}.css" s.gtk4} "$XDG_CONFIG_HOME/gtk-4.0/gtk.css"
    xvfb-run -a python ${./gtk.py} 3 ${appearance} > "$out/gtk3-${appearance}.txt"
    xvfb-run -a python ${./gtk.py} 4 ${appearance} > "$out/gtk4-${appearance}.txt"
  '') [ "dark" "light" ]}
''
