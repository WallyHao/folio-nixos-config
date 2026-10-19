# Shared NVIDIA userspace and kernel driver policy for the supported RTX GPUs.
{ config, lib, ... }: {
  nixpkgs.config.allowUnfreePredicate = package:
    builtins.elem (lib.getName package) [ "nvidia-x11" "nvidia-settings" ];
  hardware.enableRedistributableFirmware = true;
  hardware.graphics = { enable = true; enable32Bit = true; };
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    open = true;
    modesetting.enable = true;
    powerManagement.enable = true;
    nvidiaSettings = true;
  };
}
