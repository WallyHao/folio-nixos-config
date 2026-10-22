{ pkgs, lib }:
let packages = import ./src/package.nix { inherit pkgs; };
in {
  requirements.user.capabilities = [ "devices-provisioned" ];
  targetModules.folio = import ./src/folio.nix;
  inherit packages;
  migrations = import ./theme-migrations.nix { inherit pkgs; };
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
