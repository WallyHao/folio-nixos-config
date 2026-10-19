{ pkgs, lib }:
let
  codex = import ./src/codex/package.nix { inherit pkgs; };
  dsh = import ./src/dsh/default.nix { inherit pkgs; };
  legacy = ./model/revisions/2026-10-19/folio-codex.yang;
  current = ./model/folio-agents.yang;
  migrate = pkgs.writeShellApplication {
    name = "folio-agents-migrate-codex";
    runtimeInputs = [ pkgs.jq ];
    text = "jq -ceS -f ${./src/migrate.jq}";
  };
in {
  models.user = [ current ];
  packages = {
    inherit codex dsh;
    migration = migrate;
    schema-history = pkgs.linkFarm "folio-agents-schema-history" [
      { name = "2026-10-19/folio-codex.yang"; path = legacy; }
    ];
  };
  migrations = [{
    module = "folio-codex"; toModule = "folio-agents";
    from = "2026-10-19"; to = "2026-10-22";
    fromSha256 = builtins.hashFile "sha256" legacy;
    toSha256 = builtins.hashFile "sha256" current;
    transform = "${migrate}/bin/folio-agents-migrate-codex";
  }];
  homeManagerModule = import ./src/user.nix { inherit pkgs lib codex dsh; };
}
