{ pkgs, lib, runtime }:
context: { folioBootstrap, config, ... }:
let native = import ./native.nix { inherit pkgs lib context config; };
in {
    assertions = [{ assertion = context.capabilities.flatpak-provisioned or false; message = "Applications require system-provisioned Flatpak support"; }];
    home.packages = [ pkgs.flatpak ] ++ native.packages;
    xdg.desktopEntries = native.desktopEntries;
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
      cp ${pkgs.writeText "folio-applications.json" (builtins.toJSON ((import ./flatpak.nix {
        inherit pkgs lib context;
        configurationDigest = context.configurationDigest or null;
      }) // { nativeApplications = native.manifest; }))} $out/folio-applications.json
    '';
  }
