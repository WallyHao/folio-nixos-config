{ pkgs, lib }:
let
  power = import ./src/power.nix { inherit pkgs; };
in
{
  packages = {
    runtime = power.runtime;
  };
  commands.system = {
    path = "${power.client}/bin/folio-system";
    scopes = [ "system" ];
  };
  models.system = [ ./model/folio-system.yang ];
  nixosModule = context: { ... }: {
    imports = [ (import ./src/system.nix { inherit context; }) ];
    systemd.services.folio-system = {
      description = "Folio system-owned power subscriber";
      wantedBy = [ "multi-user.target" ];
      after = [ "folio-manager.service" ];
      requires = [ "folio-manager.service" ];
      serviceConfig = {
        User = "root";
        Group = "folio-operators";
        StateDirectory = "folio/system";
        StateDirectoryMode = "0700";
        ExecStart = "${power.runtime}/bin/folio-system-subscriber";
        Restart = "on-failure";
        UMask = "0077";
      };
    };
  };
}
