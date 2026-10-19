# Explicit composition uses only public module exports. Shared software and user
# preferences remain in defaults.nix; each target supplies only its differences.
{ catalogue }:
let
  migrated = base: {
    environment.system.users = [{
      name = "folio"; uid = 1000; home = "/home/folio";
      groups = [ "folio-operators" "kvm" "video" "wheel" "networkmanager" ];
      login-shell = "zsh";
    }];
    settings = base.settings // {
      network."folio-network:network".proxy = {
        enabled = true; tun = true;
        provider-file = "/var/lib/sylphy-mihomo-private/provider.yaml";
      };
    };
    modules = base.modules ++ [ catalogue.system.migrationModule
      catalogue.desktop.migrationModule catalogue.network.migrationModule ];
  };
in rec {
  portable = { settings = { }; modules = [ ]; };
  laptop = {
    settings.system = catalogue.system.targetSettings.laptop;
    modules = [ catalogue.system.targetModules.laptop catalogue.devices.targetModules.laptop ];
  };
  desktop = {
    settings.system = catalogue.system.targetSettings.desktop;
    modules = [ catalogue.system.targetModules.desktop catalogue.devices.targetModules.desktop ];
  };
  laptop-migration = migrated laptop;
  desktop-migration = migrated desktop;
  folio = migrated {
    settings.system = catalogue.system.targetSettings.folio;
    modules = [ catalogue.system.targetModules.folio catalogue.devices.targetModules.folio ];
  };
}
