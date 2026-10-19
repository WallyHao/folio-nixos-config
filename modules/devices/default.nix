{ pkgs, lib }:
let packages = import ./src/package.nix { inherit pkgs; };
in {
  targetModules.folio = import ./src/folio.nix;
  inherit packages;
  models.system = [ ./model/folio-devices.yang ];
  models.user = [ ./model/folio-devices.yang ];
  subscribers.user = [ "folio-devices.service" ];
  commands.devices = {
    path = "${packages.client}/bin/folio-devices";
    help = "${./cli/commands/devices/help.txt}";
    scopes = [ "user" ];
  };
  nixosModule = import ./src/system.nix { inherit pkgs lib; };
  homeManagerModule = import ./src/user.nix { inherit pkgs packages; };
}
