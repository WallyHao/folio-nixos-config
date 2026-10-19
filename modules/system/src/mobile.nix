# The same existing USB installation boots on both supported UEFI machines.
{ ... }: {
  imports = [ ./usb-storage.nix ];
  boot.initrd.availableKernelModules = [ "ehci_pci" "uhci_hcd" ];
  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.timeout = 5;
  boot.loader.systemd-boot.configurationLimit = 10;
}
