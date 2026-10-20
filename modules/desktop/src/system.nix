{ pkgs, lib, packages }:
context: {
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;
  security.pam.services.login.enableGnomeKeyring = true;
  security.pam.services.passwd.enableGnomeKeyring = true;
  programs.niri = { enable = true; package = packages.niri; useNautilus = false; };
  # A new login command must not close the desktop during system activation.
  systemd.services.greetd.restartIfChanged = false;
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --cmd ${packages.niri}/bin/niri-session";
      user = "greeter";
    };
  };
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = [ "gtk" ];
  };
}
