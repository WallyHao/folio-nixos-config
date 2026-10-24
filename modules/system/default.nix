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
  checks = {
    account-migration = import ./tests/account-migration.nix {
      inherit pkgs;
      migration = power.migration;
    };
    legacy-retirement-files = import ./tests/legacy-retirement-files.nix { inherit pkgs; };
  };
  targetModules.folio = import ./src/folio.nix;
  migrationModule = import ./src/migration.nix { migration = power.migration; };
  subscribers.system = [ "folio-system.service" ];
  packages = {
    runtime = power.runtime;
    migration = power.migration;
    keyring = power.keyring;
    retirement = power.retirement;
    legacy-cleanup = power.legacyCleanup;
  };
  commands.system = {
    help = "${./cli/commands/system/help.txt}";
    path = "${power.client}/bin/folio-system";
    scopes = [ "system" ];
  };
  models.system = [ currentModel ];
  migrations = (import ./theme-migrations.nix { inherit pkgs; }) ++ [
    {
      module = "folio-system";
      from = "2026-10-18";
      to = "2026-10-19";
      fromSha256 = builtins.hashFile "sha256" oldModel;
      toSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-19/folio-system.yang;
      transform = "${migration}/bin/folio-system-add-policy";
    }
  ];
  nixosModule = import ./src/system.nix { inherit power; };
}
