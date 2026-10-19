# One driver closure for the Intel/RTX 4060 laptop and AMD/RTX 3090 desktop.
# Kernel PCI matching selects drivers; display/render selection stays with Niri.
{ ... }: {
  imports = [ ./nvidia.nix ];
  hardware.cpu.intel.updateMicrocode = true;
  hardware.cpu.amd.updateMicrocode = true;
  boot.initrd.kernelModules = [ "i915" "amdgpu" ];
  services.xserver.videoDrivers = [ "amdgpu" "modesetting" ];
  # No fixed PCI IDs, PRIME wiring, card numbering or global render overrides.
}
