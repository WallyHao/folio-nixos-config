# Explicit composition uses only public module exports. Shared software and user
# preferences remain in defaults.nix; each target supplies only its differences.
{ catalogue }:
{
  portable = { settings = { }; modules = [ ]; };
  folio = {
    environment.system.users = [{
      name = "folio"; uid = 1000; home = "/home/folio";
      groups = [ "folio-operators" "kvm" "video" "wheel" "networkmanager" ];
      login-shell = "zsh";
    }];
    settings = {
      system = catalogue.system.targetSettings.folio;
      network."folio-network:network".proxy = {
        enabled = true; tun = true;
        provider-file = "/var/lib/sylphy-mihomo-private/provider.yaml";
      };
    };
    modules = [ catalogue.system.targetModules.folio catalogue.devices.targetModules.folio
      catalogue.system.migrationModule
      catalogue.desktop.migrationModule catalogue.network.migrationModule ];
  };
}
