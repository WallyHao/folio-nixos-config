{ pkgs, lib, packages }:
context: {
  programs.niri = { enable = true; package = packages.niri; useNautilus = false; };
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
