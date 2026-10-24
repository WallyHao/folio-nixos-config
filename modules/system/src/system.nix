{ power }:
context: { ... }: {
  imports = [ (import ./base.nix { inherit context; }) ];
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
}
