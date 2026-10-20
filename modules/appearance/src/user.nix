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
    colorScheme = theme.colors.appearance;
    # adw-gtk3 consumes the same named colors as our GTK 4 overrides.
    gtk3.theme = {
      package = pkgs.adw-gtk3;
      name = if theme.colors.appearance == "dark" then "adw-gtk3-dark" else "adw-gtk3";
    };
    # Keep libadwaita's stylesheet; its palette is overridden through CSS variables.
    gtk4.theme = null;
    gtk3.extraCss = css.gtk3;
    gtk4.extraCss = css.gtk4;
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
    document-font-name = "${theme.font-family} ${toString theme.font-size}";
    monospace-font-name = "${theme.font-family} ${toString theme.font-size}";
  };
  dconf.settings."org/gnome/desktop/wm/preferences".titlebar-font =
    "${theme.font-family} ${toString theme.font-size}";
  xdg.configFile."folio/appearance.json".text = builtins.toJSON {
    format = 1;
    appearance = theme.colors.appearance;
    inherit (theme) font-family font-size cursor-size origins;
    cursor = cursor.cursorName;
  };
}
