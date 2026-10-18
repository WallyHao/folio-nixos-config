{ pkgs, client, runtime }:
let userService = import ./user-service.nix { inherit pkgs runtime; };
in
context: { folioBootstrap, ... }: {
    home.packages = [
      client.cli
      runtime
    ];
    systemd.user.services.folio-manager = {
      Unit = {
        Description = "Folio user configuration subscriber";
      };
      Service = userService folioBootstrap;
      Install.WantedBy = [ "default.target" ];
    };
  }
