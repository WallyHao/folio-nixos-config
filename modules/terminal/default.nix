{ pkgs, lib }:
let
  renderer = import ./src/foot.nix { };
in
{
  models.user = [ ./model/folio-terminal.yang ];
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
      };
    };
}
