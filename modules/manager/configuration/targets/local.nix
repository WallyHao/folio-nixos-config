# Machine data stays under modules/ so reviewed deployment snapshots retain it.
let
  directory = ./local;
  host =
    if builtins.pathExists (directory + "/host.json") then
      builtins.fromJSON (builtins.readFile (directory + "/host.json"))
    else
      throw "Folio: local target is not initialized; run 'just init' on the installed NixOS machine";
in
{
  environment = {
    system = {
      name = host.hostname;
      users = [
        {
          name = host.username;
          inherit (host) uid home;
          groups = [
            "wheel"
            "networkmanager"
            "video"
            "kvm"
            "folio-operators"
          ];
          login-shell = host.shell;
        }
      ];
      modules = [
        {
          name = "system";
          "folio-system:system" = {
            prototype-password = false;
            time-zone = host.timezone;
            locale = host.locale;
          };
        }
      ];
    };
    user = {
      name = host.hostname;
      account = host.username;
    };
  };
  modules = [
    (directory + "/installation/configuration.nix")
    (directory + "/host.nix")
    (
      { lib, pkgs, ... }:
      {
        folio.manageStorage = false;
        networking.hostName = lib.mkForce host.hostname;
        users.mutableUsers = true;
        environment.systemPackages = [ pkgs.just ];
        # Niri uses greetd and NetworkManager, including on installer desktops.
        services.displayManager.gdm.enable = lib.mkForce false;
        services.displayManager.sddm.enable = lib.mkForce false;
        services.xserver.displayManager.lightdm.enable = lib.mkForce false;
        services.displayManager.autoLogin.enable = lib.mkForce false;
        networking.wireless.enable = lib.mkForce false;
      }
    )
  ];
}
