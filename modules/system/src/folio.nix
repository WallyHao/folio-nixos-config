# The Folio USB installation boots on both supported UEFI machines.
{ config, ... }: {
  fileSystems."/".options = [ "subvol=root" "compress=zstd" "noatime" ];
  fileSystems."/home" = {
    device = config.fileSystems."/".device;
    fsType = "btrfs";
    options = [ "subvol=home" "compress=zstd" "noatime" ];
  };
  fileSystems."/nix" = {
    device = config.fileSystems."/".device;
    fsType = "btrfs";
    options = [ "subvol=nix" "compress=zstd" "noatime" ];
  };
  fileSystems."/boot".options = [ "fmask=0077" "dmask=0077" ];
  boot.initrd.availableKernelModules = [ "uas" "sd_mod" "usbhid" "ehci_pci" "uhci_hcd" ];
  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.timeout = 5;
  boot.loader.systemd-boot.configurationLimit = 10;
  assertions = [{
    assertion = config.fileSystems."/".fsType == "btrfs";
    message = "The Folio USB profile requires Btrfs; configure storage before using a different disk";
  }];
}
