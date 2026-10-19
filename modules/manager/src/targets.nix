# Explicit composition uses only public module exports. Shared software and user
# preferences remain in defaults.nix; each target supplies only its differences.
{ catalogue }: {
  portable = { settings = { }; modules = [ ]; };
  laptop = {
    settings.system = catalogue.system.targetSettings.laptop;
    modules = [ catalogue.system.targetModules.laptop catalogue.devices.targetModules.laptop ];
  };
  # Register desktop after inspecting its CPU, GPU, firmware and chosen storage.
  # No guessed hardware or guest-label physical target is exposed.
}
