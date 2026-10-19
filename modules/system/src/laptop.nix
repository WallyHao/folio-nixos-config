# Observed current USB installation on the Legion, not its internal NVMe.
# Hardware and disk policy are separate: replace this binding for a new disk.
{ config, lib, ... }:
let root = config.fileSystems."/".device;
in {
  fileSystems."/".options = [ "subvol=root" "compress=zstd" "noatime" ];
  fileSystems."/home" = { device = root; fsType = "btrfs"; options = [ "subvol=home" "compress=zstd" "noatime" ]; };
  fileSystems."/nix" = { device = root; fsType = "btrfs"; options = [ "subvol=nix" "compress=zstd" "noatime" ]; };
  fileSystems."/boot".options = [ "fmask=0077" "dmask=0077" ];
  boot.initrd.availableKernelModules = [ "uas" "sd_mod" "usbhid" ];
  assertions = [{
    assertion = config.fileSystems."/".fsType == "btrfs";
    message = "The laptop current-storage profile requires Btrfs; select a different storage profile for a new disk";
  }];
}
