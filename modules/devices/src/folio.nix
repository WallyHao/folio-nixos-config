# Folio driver closure for the Intel/RTX 4060 laptop and AMD/RTX 3090 desktop.
# Kernel PCI matching selects drivers; display/render selection stays with Niri.
{ config, lib, ... }: {
  nixpkgs.config.allowUnfreePredicate = package:
    builtins.elem (lib.getName package) [ "nvidia-x11" "nvidia-settings" ];
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;
  hardware.cpu.amd.updateMicrocode = true;
  boot.initrd.kernelModules = [ "i915" "amdgpu" ];
  hardware.graphics = { enable = true; enable32Bit = true; };
  services.xserver.videoDrivers = [ "nvidia" "amdgpu" "modesetting" ];
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    open = true;
    modesetting.enable = true;
    powerManagement.enable = true;
    nvidiaSettings = true;
  };
  # No fixed PCI IDs, PRIME wiring, card numbering or global render overrides.
}
