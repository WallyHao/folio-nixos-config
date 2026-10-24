{
  pkgs,
  lib,
  context,
  config,
}:
let
  settings = context.settings.native or { };
  zenEnabled = settings.zen or false;
  obsEnabled = settings.obs or false;
  imvEnabled = settings.imv or true;
  zathuraEnabled = settings.zathura or true;
  browser = import ./zen.nix { inherit pkgs; };
  profile = "${config.xdg.configHome}/zen/${settings.zen-profile or ""}";
  managedProfile = zenEnabled && settings ? zen-profile;
  browserFiles =
    (import ./apps/zen.nix {
      inherit pkgs lib context;
      app = {
        name = "zen";
        selected = true;
      };
    }).files;
  zen =
    if !(settings ? zen-profile) then
      browser
    else
      pkgs.symlinkJoin {
        name = "folio-zen-beta-${browser.version}";
        paths = [ browser ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          rm "$out/bin/zen-beta"
          makeWrapper ${browser}/bin/zen-beta "$out/bin/zen-beta" \
            --add-flags ${lib.escapeShellArg ("--profile " + lib.escapeShellArg profile)}
        '';
      };
in
{
  profileDirectory = if managedProfile then profile else null;
  profileFiles = lib.optionalAttrs managedProfile (
    lib.listToAttrs (
      map (file: {
        name = "zen/${settings.zen-profile}/${file.destination}";
        value.source = file.source;
      }) browserFiles
    )
  );
  packages = lib.optional zenEnabled zen ++ lib.optional obsEnabled pkgs.obs-studio;
  manifest =
    lib.optional zenEnabled {
      name = "zen";
      package = toString zen;
      executable = "${zen}/bin/zen-beta";
    }
    ++ lib.optional obsEnabled {
      name = "obs";
      package = toString pkgs.obs-studio;
      executable = "${pkgs.obs-studio}/bin/obs";
    }
    ++ lib.optional zathuraEnabled {
      name = "zathura";
      package = toString pkgs.zathura;
      executable = "${pkgs.zathura}/bin/zathura";
    }
    ++ lib.optional imvEnabled {
      name = "imv";
      package = toString pkgs.imv;
      executable = "${pkgs.imv}/bin/imv";
    };
  desktopEntries = lib.optionalAttrs zenEnabled {
    zen-beta = {
      name = "Zen Browser (Beta)";
      genericName = "Web Browser";
      exec = "${zen}/bin/zen-beta %U";
      icon = "zen-beta";
      terminal = false;
      categories = [
        "Network"
        "WebBrowser"
      ];
      mimeType = [
        "text/html"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
      ];
    };
  };
}
