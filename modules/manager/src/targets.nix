# Explicit composition uses only public module exports. Shared software and user
# preferences remain in defaults.nix; each target supplies only its differences.
{ catalogue }: rec {
  portable = { settings = { }; modules = [ ]; };
  laptop = {
    settings.system = catalogue.system.targetSettings.laptop;
    modules = [ catalogue.system.targetModules.laptop catalogue.devices.targetModules.laptop ];
  };
  laptop-migration = {
    environment.system.users = [{
      name = "folio";
      uid = 1000;
      home = "/home/folio";
      groups = [ "folio-operators" "kvm" "video" "wheel" "networkmanager" ];
      login-shell = "zsh";
    }];
    settings = laptop.settings // {
      network."folio-network:network".proxy = {
        enabled = true;
        tun = true;
        provider-file = "/var/lib/sylphy-mihomo-private/provider.yaml";
      };
    };
    modules = laptop.modules ++ [ catalogue.system.migrationModule
      catalogue.desktop.migrationModule catalogue.network.migrationModule ];
  };
  # Register desktop after inspecting its CPU, GPU, firmware and chosen storage.
  # No guessed hardware or guest-label physical target is exposed.
}
