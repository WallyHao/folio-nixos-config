{ pkgs }:
let
  launcher = pkgs.writeShellApplication {
    name = "pi";
    runtimeInputs = [ pkgs.coreutils pkgs.util-linux pkgs.nodejs pkgs.gitMinimal ];
    runtimeEnv = {
      FOLIO_PI_PACKAGE = "${pkgs.pi-coding-agent}";
      FOLIO_PI_BUNDLED_CONFIG = "${./config}";
    };
    text = builtins.readFile ./launch.sh;
  };
in launcher.overrideAttrs (old: {
  version = pkgs.pi-coding-agent.version;
  meta = pkgs.pi-coding-agent.meta // {
    description = "Pi with Folio native configuration and private runtime state";
  };
})
