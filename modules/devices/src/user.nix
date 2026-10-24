{ pkgs, packages }:
context: {
  assertions = [
    {
      assertion = context.capabilities.devices-provisioned or false;
      message = "Device controls require system-provisioned services and permissions";
    }
  ];
  home.packages = [ pkgs.blueman ];
  systemd.user.services.folio-devices = {
    Unit = {
      Description = "Folio actual device observations and session controls";
      Requires = [ "folio-manager.service" ];
      After = [ "folio-manager.service" ];
    };
    Service = {
      ExecStart = "${packages.subscriber}/bin/folio-devices-subscriber";
      Restart = "on-failure";
      UMask = "0077";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
