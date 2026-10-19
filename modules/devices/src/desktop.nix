# MSI MAG B650M MORTAR WIFI: Ryzen 7 9700X, RTX 3090 and AMD integrated graphics.
# Both display adapters remain usable; no laptop PRIME topology is imposed.
{ config, lib, ... }: {
  nixpkgs.config.allowUnfreePredicate = package:
    builtins.elem (lib.getName package) [ "nvidia-x11" "nvidia-settings" ];
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.amd.updateMicrocode = true;
  boot.initrd.kernelModules = [ "amdgpu" ];
  hardware.graphics = { enable = true; enable32Bit = true; };
  services.xserver.videoDrivers = [ "nvidia" "amdgpu" ];
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    open = true;
    modesetting.enable = true;
    powerManagement.enable = true;
    nvidiaSettings = true;
  };
}
