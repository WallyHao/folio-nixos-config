{ context }:
{ config, lib, ... }:
let
  settings = context.settings;
  guest = (settings.storage-profile or "disposable-guest") == "disposable-guest";
in
{
  options.folio.manageStorage = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Let Folio configure storage and the boot loader. Disable when importing an existing installation.";
  };

  config = lib.mkIf config.folio.manageStorage {
    # Guest labels are a disposable image contract. Physical devices must be
    # explicitly inspected and supplied; this module never partitions disks.
    boot.loader.grub.enable = false;
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = false;
    boot.initrd.availableKernelModules = [
      "virtio_pci"
      "virtio_blk"
      "ahci"
      "nvme"
      "usb_storage"
      "xhci_pci"
    ];
    boot.kernelParams = lib.optionals guest [
      "console=ttyS0,115200n8"
      "console=tty0"
    ];
    fileSystems."/" = {
      device = if guest then "/dev/disk/by-label/nixos" else settings.root-device;
      fsType = if guest then "ext4" else settings.root-filesystem or "ext4";
    };
    fileSystems."/boot" = {
      device = if guest then "/dev/disk/by-label/ESP" else settings.boot-device;
      fsType = "vfat";
    };
    assertions = [
      {
        assertion = guest || !(settings.prototype-password or true);
        message = "Physical targets require explicit storage and must disable the public prototype password";
      }
    ];
  };
}
