# Lenovo Legion Y7000 IRX9: i7-13650HX, Intel 00:02.0 + NVIDIA 01:00.0.
# PRIME offload keeps the integrated GPU as the default Wayland renderer.
{ ... }: {
  imports = [ ./nvidia.nix ];
  hardware.cpu.intel.updateMicrocode = true;
  boot.initrd.kernelModules = [ "i915" ];
  hardware.nvidia = {
    prime = {
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
      offload = { enable = true; enableOffloadCmd = true; };
    };
  };
}
