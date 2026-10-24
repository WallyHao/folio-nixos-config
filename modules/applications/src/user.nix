{
  pkgs,
  lib,
  runtime,
}:
context:
{
  folioBootstrap,
  config,
  lib,
  ...
}:
let
  native = import ./native.nix {
    inherit
      pkgs
      lib
      context
      config
      ;
  };
in
{
  imports = [
    ((import ./zathura.nix { inherit pkgs lib; }) context)
    ((import ./imv.nix { inherit pkgs lib; }) context)
  ];
  assertions = [
    {
      assertion = context.capabilities.flatpak-provisioned or false;
      message = "Applications require system-provisioned Flatpak support";
    }
  ];
  home.packages = [ pkgs.flatpak ] ++ native.packages;
  xdg.desktopEntries = native.desktopEntries;
  # Home Manager refuses to replace unmanaged files. Existing personal CSS or
  # user.js must be explicitly adopted; browser databases and prefs.js stay owned
  # by the browser. Select an existing profile instead of creating one silently.
  xdg.configFile = native.profileFiles;
  home.activation.folioNativeZenProfile = lib.mkIf (native.profileDirectory != null) (
    lib.hm.dag.entryBefore [ "writeBoundary" ] ''
      if [ ! -d ${lib.escapeShellArg native.profileDirectory} ] || [ -L ${lib.escapeShellArg native.profileDirectory} ]; then
        echo 'Folio: the selected native Zen profile must be an existing regular directory' >&2
        exit 1
      fi
    ''
  );
  systemd.user.services.folio-applications = {
    Unit = {
      Description = "Folio owned applications subscriber";
      Requires = [ "folio-manager.service" ];
      After = [ "folio-manager.service" ];
    };
    Service = {
      Environment = "FOLIO_BOOTSTRAP=${folioBootstrap}";
      # Home Manager can start us while its worker holds the configuration
      # lock and the manager is still recovering. Do not wait for manager RPC
      # readiness here: that would make activation wait on its own lock.
      ExecStartPre = "${runtime.tools}/bin/folio-applications-tool recover";
      ExecStart = "${runtime.subscriber}/bin/folio-applications-subscriber";
      Restart = "on-failure";
      UMask = "0077";
    };
    Install.WantedBy = [ "default.target" ];
  };
  home.extraBuilderCommands = ''
    cp ${
      pkgs.writeText "folio-applications.json" (
        builtins.toJSON (
          (import ./flatpak.nix {
            inherit pkgs lib context;
            configurationDigest = context.configurationDigest or null;
          })
          // {
            nativeApplications = native.manifest;
          }
        )
      )
    } $out/folio-applications.json
  '';
}
