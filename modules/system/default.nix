{ pkgs, lib }:
let power = import ./src/package.nix { inherit pkgs; };
in
{
  subscribers.system = [ "folio-system.service" ];
  packages = {
    runtime = power.runtime;
  };
  commands.system = {
    help = "${./cli/commands/system/help.txt}";
    path = "${power.client}/bin/folio-system";
    scopes = [ "system" ];
  };
  models.system = [ ./model/folio-system.yang ];
  nixosModule = import ./src/system.nix { inherit power; };
}
