{ pkgs, lib }:
let packages = import ./src/package.nix { inherit pkgs; };
in {
  inherit packages;
  models.system = [ ./model/folio-network.yang ./model/folio-network-panel.yang ];
  subscribers.system = [ "folio-network.service" ];
  commands.network = {
    path = "${packages.client}/bin/folio-network";
    help = "${./cli/commands/network/help.txt}";
    scopes = [ "system" ];
  };
  nixosModule = import ./src/system.nix { inherit pkgs lib packages; };
  targetModules.folio = import ./src/folio.nix { inherit pkgs; };
}
