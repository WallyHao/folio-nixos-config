# Lenovo Legion Y7000 IRX9: i7-13650HX, Intel 00:02.0 + NVIDIA 01:00.0.
# PRIME offload keeps the integrated GPU as the default Wayland renderer.
{ config, lib, ... }: {
  nixpkgs.config.allowUnfreePredicate = package:
    builtins.elem (lib.getName package) [ "nvidia-x11" "nvidia-settings" ];
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;
  boot.initrd.kernelModules = [ "i915" ];
  hardware.graphics = { enable = true; enable32Bit = true; };
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    open = true;
    modesetting.enable = true;
    powerManagement.enable = true;
    nvidiaSettings = true;
    prime = {
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
      offload = { enable = true; enableOffloadCmd = true; };
    };
  };
}
