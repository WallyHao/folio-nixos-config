{ pkgs, lib }:
let
  initial = ./model/revisions/2026-10-18/folio-terminal.yang;
  additive = ./model/revisions/2026-10-19/folio-terminal.yang;
  fraction = ./model/revisions/2026-10-20/folio-terminal.yang;
  tools = ./model/revisions/2026-10-21/folio-terminal.yang;
  legacyGit = ./model/revisions/2026-10-19/folio-git.yang;
  gitModel = ./model/revisions/2026-10-22/folio-terminal.yang;
  current = ./model/folio-terminal.yang;
  migration = name: filter: pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = [ pkgs.jq ];
    text = "jq -ceS " + lib.escapeShellArg filter;
  };
  addOpacity = migration "folio-terminal-add-opacity" ''
    ."folio-environment:environment".modules |= map(
      if .name=="terminal" and has("folio-terminal:terminal") then
        ."folio-terminal:terminal".foot."opacity-percent" //= 100
      else . end)
  '';
  fractionOpacity = migration "folio-terminal-opacity-fraction" ''
    ."folio-environment:environment".modules |= map(
      if .name=="terminal" and has("folio-terminal:terminal") then
        ."folio-terminal:terminal".foot |= (
          .opacity=(((."opacity-percent" // 100) / 100) | tostring) | del(."opacity-percent"))
      else . end)
  '';
in
{
  models.user = [ current ];
  impacts = [ "Open a new terminal or shell to load changed terminal and shell settings." ];
  migrations = [
    {
      module = "folio-terminal";
      from = "2026-10-18"; to = "2026-10-19";
      fromSha256 = builtins.hashFile "sha256" initial;
      toSha256 = builtins.hashFile "sha256" additive;
      transform = "${addOpacity}/bin/folio-terminal-add-opacity";
    }
    {
      module = "folio-terminal";
      from = "2026-10-19"; to = "2026-10-20";
      fromSha256 = builtins.hashFile "sha256" additive;
      toSha256 = builtins.hashFile "sha256" fraction;
      transform = "${fractionOpacity}/bin/folio-terminal-opacity-fraction";
    }
    {
      module = "folio-terminal";
      from = "2026-10-20"; to = "2026-10-21";
      fromSha256 = builtins.hashFile "sha256" fraction;
      toSha256 = builtins.hashFile "sha256" tools;
      transform = "${migration "folio-terminal-add-tools" "."}/bin/folio-terminal-add-tools";
    }
    {
      module = "folio-terminal";
      from = "2026-10-21"; to = "2026-10-22";
      fromSha256 = builtins.hashFile "sha256" tools;
      toSha256 = builtins.hashFile "sha256" gitModel;
      transform = "${migration "folio-terminal-add-git" ''
        ."folio-environment:environment".modules |= map(
          if .name=="terminal" then ."folio-terminal:terminal".git //= {enabled:false}
          else . end)
      ''}/bin/folio-terminal-add-git";
    }
    {
      module = "folio-terminal";
      from = "2026-10-22"; to = "2026-10-24";
      fromSha256 = builtins.hashFile "sha256" gitModel;
      toSha256 = builtins.hashFile "sha256" current;
      transform = "${migration "folio-terminal-add-yazi" "."}/bin/folio-terminal-add-yazi";
    }
    {
      module = "folio-git"; toModule = "folio-terminal";
      from = "2026-10-19"; to = "2026-10-22";
      fromSha256 = builtins.hashFile "sha256" legacyGit;
      toSha256 = builtins.hashFile "sha256" gitModel;
      transform = "${pkgs.writeShellApplication {
        name = "folio-terminal-migrate-git";
        runtimeInputs = [ pkgs.jq ];
        text = "jq -ceS -f ${./src/migrate-git.jq}";
      }}/bin/folio-terminal-migrate-git";
    }
  ];
  packages.schema-history = pkgs.linkFarm "folio-terminal-schema-history" [
    { name = "2026-10-18/folio-terminal.yang"; path = initial; }
    { name = "2026-10-19/folio-terminal.yang"; path = additive; }
    { name = "2026-10-20/folio-terminal.yang"; path = fraction; }
    { name = "2026-10-21/folio-terminal.yang"; path = tools; }
    { name = "2026-10-22/folio-terminal.yang"; path = gitModel; }
    { name = "2026-10-24/folio-terminal.yang"; path = current; }
    { name = "2026-10-19/folio-git.yang"; path = legacyGit; }
  ];
  homeManagerModule = import ./src/user.nix { inherit pkgs lib; };
  nixosModule = context: { programs.zsh.enable = true; };
}
