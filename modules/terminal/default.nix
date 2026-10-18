{ pkgs, lib }:
let
  renderer = import ./src/foot.nix { };
  initial = ./model/revisions/2026-10-18/folio-terminal.yang;
  additive = ./model/revisions/2026-10-19/folio-terminal.yang;
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
      toSha256 = builtins.hashFile "sha256" current;
      transform = "${fractionOpacity}/bin/folio-terminal-opacity-fraction";
    }
  ];
  packages.schema-history = pkgs.linkFarm "folio-terminal-schema-history" [
    { name = "2026-10-18/folio-terminal.yang"; path = initial; }
    { name = "2026-10-19/folio-terminal.yang"; path = additive; }
    { name = "2026-10-20/folio-terminal.yang"; path = current; }
  ];
  homeManagerModule =
    context:
    let
      foot = (context.settings."folio-terminal:terminal" or { }).foot or { };
      preferences = context.globals;
      theme = renderer.defaultTheme // {
        colors = renderer.defaultTheme.colors // {
          appearance = preferences.appearance;
        };
      };
    in
    lib.mkIf (foot.enabled or true) {
      home.packages = [
        pkgs.foot
        pkgs.maple-mono.NF-CN
      ];
      xdg.configFile."foot/foot.ini".text = renderer.renderConfig {
        inherit lib theme;
        font = foot.font or "${preferences.font-family}:size=${toString preferences.font-size}";
        padding = foot.padding or "15x15";
        opacity = foot.opacity or "1";
      };
    };
}
