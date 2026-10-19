# MSI MAG B650M MORTAR WIFI: Ryzen 7 9700X, RTX 3090 and AMD integrated graphics.
# Both display adapters remain usable; no laptop PRIME topology is imposed.
{ ... }: {
  imports = [ ./nvidia.nix ];
  hardware.cpu.amd.updateMicrocode = true;
  boot.initrd.kernelModules = [ "amdgpu" ];
  services.xserver.videoDrivers = [ "amdgpu" ];
}
