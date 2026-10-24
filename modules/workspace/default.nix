{
  pkgs,
  lib,
  networkPrepare,
}:
let
  packages = import ./src/package.nix { inherit pkgs networkPrepare; };
in
{
  provides.system = [ "workspace-provisioned" ];
  inherit packages;
  checks.preparation = import ./tests/preparation.nix { inherit pkgs; };
  commands.prepare = {
    path = "${packages.client}/bin/folio-prepare";
    help = "${./cli/help.txt}";
    scopes = [ "user" ];
  };
  requirements = {
    system.modules = [ "network" ];
    user = {
      capabilities = [
        "workspace-provisioned"
        "desktop-provisioned"
      ];
      modules = [ "desktop" ];
    };
  };
  nixosModule = context: { config, ... }: {
    assertions = [
      {
        assertion = context.capabilities.network-provisioned or false;
        message = "Workspace preparation requires the system network module";
      }
    ];
    environment.systemPackages = [ packages.system ];
    environment.etc."folio/workspace-checks.json".text = builtins.toJSON {
      mounts =
        lib.mapAttrsToList
          (target: fs: {
            inherit target;
            inherit (fs) device fsType options;
          })
          (
            lib.filterAttrs (
              target: _:
              builtins.elem target [
                "/"
                "/home"
                "/nix"
                "/boot"
              ]
            ) config.fileSystems
          );
    };
    security.sudo.extraRules = [
      {
        groups = [ "folio-operators" ];
        runAs = "root";
        commands =
          map
            (action: {
              command = "/run/current-system/sw/bin/folio-workspace-system ${action}";
              options = [ "NOPASSWD" ];
            })
            [
              "network"
              "disk-check"
              "repair-services --apply"
              "sync-time --apply"
              "cleanup --apply"
            ];
      }
    ];
  };
  homeManagerModule = context: {
    assertions = [
      {
        assertion =
          (context.capabilities.workspace-provisioned or false)
          && builtins.elem "desktop" context.enabledModules;
        message = "Workspace preparation requires system provisioning and the user desktop module";
      }
    ];
    home.packages = [ packages.client ];
    systemd.user.services.folio-workspace = {
      Unit = {
        Description = "Folio interactive workspace preparation";
        After = [ "graphical-session-pre.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.foot}/bin/foot --app-id=org.folio.Workspace --title=Workspace\\x20Preparation ${packages.client}/bin/folio-prepare --boot --pause";
        RemainAfterExit = true;
        TimeoutStartSec = "infinity";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
