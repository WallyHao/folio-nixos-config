{ pkgs, lib }:
let
  power = import ./src/package.nix { inherit pkgs; };
  oldModel = ./model/revisions/2026-10-18/folio-system.yang;
  currentModel = ./model/folio-system.yang;
  migration = pkgs.writeShellApplication {
    name = "folio-system-add-policy";
    runtimeInputs = [ pkgs.jq ];
    text = "jq -ceS .";
  };
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
  models.system = [ currentModel ];
  migrations = [{
    module = "folio-system";
    from = "2026-10-18"; to = "2026-10-19";
    fromSha256 = builtins.hashFile "sha256" oldModel;
    toSha256 = builtins.hashFile "sha256" currentModel;
    transform = "${migration}/bin/folio-system-add-policy";
  }];
  nixosModule = import ./src/system.nix { inherit power; };
}
