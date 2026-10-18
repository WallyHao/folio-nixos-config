{ tools, runtime }:
context: { ... }: {
    assertions = [
      {
        assertion = context.capabilities.kvm-access-configured or false;
        message = "Folio VM requires system-provisioned KVM access; actual device access is checked on start";
      }
    ];
    home.packages = [ tools ];
    systemd.user.services.folio-vm = {
      Unit = {
        Description = "Folio VM lifecycle subscriber";
        Requires = [ "folio-manager.service" ];
        After = [ "folio-manager.service" ];
      };
      Service = {
        ExecStart = "${runtime.subscriber}/bin/folio-vm-subscriber";
        Restart = "on-failure";
        UMask = "0077";
      };
      Install.WantedBy = [ "default.target" ];
    };
  }
