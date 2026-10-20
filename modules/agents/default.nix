{ pkgs, lib }:
let
  codex = import ./src/codex/package.nix { inherit pkgs; };
  pi = import ./src/pi/package.nix { inherit pkgs; };
  legacy = ./model/revisions/2026-10-19/folio-codex.yang;
  harness = ./model/revisions/2026-10-22/folio-agents.yang;
  current = ./model/folio-agents.yang;
  migrate = pkgs.writeShellApplication {
    name = "folio-agents-migrate-codex";
    runtimeInputs = [ pkgs.jq ];
    text = "jq -ceS -f ${./src/migrate.jq}";
  };
  replaceHarness = pkgs.writeShellApplication {
    name = "folio-agents-replace-dsh";
    runtimeInputs = [ pkgs.jq ];
    text = "jq -ceS -f ${./src/migrate-pi.jq}";
  };
in {
  models.user = [ current ];
  packages = {
    inherit codex pi;
    migration = migrate;
    schema-history = pkgs.linkFarm "folio-agents-schema-history" [
      { name = "2026-10-19/folio-codex.yang"; path = legacy; }
      { name = "2026-10-22/folio-agents.yang"; path = harness; }
    ];
  };
  migrations = [{
    module = "folio-codex"; toModule = "folio-agents";
    from = "2026-10-19"; to = "2026-10-22";
    fromSha256 = builtins.hashFile "sha256" legacy;
    toSha256 = builtins.hashFile "sha256" harness;
    transform = "${migrate}/bin/folio-agents-migrate-codex";
  } {
    module = "folio-agents";
    from = "2026-10-22"; to = "2026-10-23";
    fromSha256 = builtins.hashFile "sha256" harness;
    toSha256 = builtins.hashFile "sha256" current;
    transform = "${replaceHarness}/bin/folio-agents-replace-dsh";
  }];
  targetSettings.folio."folio-agents:agents".pi = {
    enabled = true;
    config-directory = "/home/folio/Workspace/folio-nixos-config/modules/agents/src/pi/config";
  };
  homeManagerModule = import ./src/user.nix { inherit pkgs lib codex pi; };
}
