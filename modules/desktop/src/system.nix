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
      # Use ANSI palette slots rather than RGB: the Linux console receives the
      # selected Everforest palette from the system module (also in light mode).
      command = lib.escapeShellArgs [
        "${pkgs.tuigreet}/bin/tuigreet"
        "--no-config"
        "--width" "60"
        "--container-padding" "2"
        "--prompt-padding" "1"
        "--asterisks"
        "--theme" "container=black;text=white;border=darkgray;title=yellow;greet=yellow;prompt=yellow;input=white;time=darkgray;action=white;button=yellow"
        "--cmd" "${packages.niri}/bin/niri-session"
      ];
      user = "greeter";
    };
  };
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = [ "gtk" ];
  };
}
