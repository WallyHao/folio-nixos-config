{ pkgs, lib }:
context:
let
  theme = import ./theme.nix { inherit context; };
  cursor = import ./cursor.nix { inherit pkgs theme; };
  css = import ./gtk-style.nix { inherit theme; };
in {
  home.packages = [ cursor pkgs.maple-mono.NF-CN ];
  gtk = {
    enable = true;
    font = { name = theme.font-family; size = theme.font-size; };
    gtk3.extraCss = css;
    gtk4.extraCss = css;
    gtk3.extraConfig.gtk-application-prefer-dark-theme = theme.colors.appearance == "dark";
    gtk4.extraConfig.gtk-application-prefer-dark-theme = theme.colors.appearance == "dark";
  };
  home.pointerCursor = {
    enable = true;
    package = cursor;
    name = cursor.cursorName;
    size = theme.cursor-size;
    gtk.enable = true;
    x11.enable = true;
  };
  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = if theme.colors.appearance == "dark" then "prefer-dark" else "prefer-light";
    cursor-theme = cursor.cursorName;
    cursor-size = theme.cursor-size;
    font-name = "${theme.font-family} ${toString theme.font-size}";
  };
  xdg.configFile."folio/appearance.json".text = builtins.toJSON {
    format = 1;
    appearance = theme.colors.appearance;
    inherit (theme) font-family font-size cursor-size origins;
    cursor = cursor.cursorName;
  };
}
