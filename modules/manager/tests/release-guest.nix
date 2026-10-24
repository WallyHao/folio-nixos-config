# Explicit integration of the existing manager and desktop disposable fixtures.
# The frozen source imports exactly the same instrumentation as the booted guest.
{ pkgs }:
{ lib, ... }: {
  imports = [
    ./system-guest.nix
    (import ../../desktop/tests/guest.nix { inherit pkgs; })
  ];
  # UEFI's auto-sized base image needs its partition and filesystem grown to
  # the disposable overlay capacity before copying the offline Flatpak cache.
  boot.growPartition = true;
  fileSystems."/".autoResize = true;
  # The legacy initrd has already mounted /; explicitly schedule the stock
  # growfs unit after the partition expansion instead of relying on fstab.
  systemd.services.systemd-growfs-root = {
    wantedBy = [ "multi-user.target" ];
    after = [ "growpart.service" ];
    requires = [ "growpart.service" ];
    before = [ "folio-manager.service" ];
  };
  virtualisation.memorySize = lib.mkForce 6144;
  virtualisation.cores = lib.mkForce 4;
}
