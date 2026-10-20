{ pkgs, lib, context, config }:
let
  settings = context.settings."folio-applications:applications".native or { };
  zenEnabled = settings.zen or false;
  obsEnabled = settings.obs or false;
  # Keep the reviewed Sylphy Beta revision and application identity. Import its
  # package with this repository's Nixpkgs, without another Flake or user data.
  upstream = builtins.fetchTree {
    type = "github";
    owner = "0xc000022070";
    repo = "zen-browser-flake";
    rev = "a12d482485d877cc066516ea256b435b209a1a8c";
    narHash = "sha256-C9BpLH4dNggam12nz/Fx/M0Vlbw8WcT/cpOc37DPQAA=";
  };
  browser = (import (upstream.outPath + "/default.nix") { inherit pkgs; }).beta;
  profile = "${config.xdg.configHome}/zen/${settings.zen-profile or ""}";
  zen = if !(settings ? zen-profile) then browser else pkgs.symlinkJoin {
    name = "folio-zen-beta-${browser.version}";
    paths = [ browser ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm "$out/bin/zen-beta"
      makeWrapper ${browser}/bin/zen-beta "$out/bin/zen-beta" \
        --add-flags ${lib.escapeShellArg ("--profile " + lib.escapeShellArg profile)}
    '';
  };
in {
  packages = lib.optional zenEnabled zen ++ lib.optional obsEnabled pkgs.obs-studio;
  manifest = lib.optional zenEnabled {
    name = "zen"; package = toString zen; executable = "${zen}/bin/zen-beta";
  } ++ lib.optional obsEnabled {
    name = "obs"; package = toString pkgs.obs-studio; executable = "${pkgs.obs-studio}/bin/obs";
  };
  desktopEntries = lib.optionalAttrs zenEnabled {
    zen-beta = {
      name = "Zen Browser (Beta)";
      genericName = "Web Browser";
      exec = "${zen}/bin/zen-beta %U";
      icon = "zen-beta";
      terminal = false;
      categories = [ "Network" "WebBrowser" ];
      mimeType = [ "text/html" "x-scheme-handler/http" "x-scheme-handler/https" ];
    };
  };
}
