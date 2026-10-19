{ context }:
{ pkgs, lib, ... }:
let
  settings = context.settings."folio-system:system" or { };
in
{
  # Disposable bootstrap fixture, never a physical installation description.
  system.stateVersion = "26.05";
  networking.hostName = context.identity.environment;
  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "ahci"
  ];
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty0"
  ];
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };
  time.timeZone = settings.time-zone or "Asia/Shanghai";
  i18n.defaultLocale = "en_US.UTF-8";
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  users.users = lib.listToAttrs (
    map (
      user:
      lib.nameValuePair user.name {
        isNormalUser = true;
        linger = true;
        inherit (user) uid home;
        extraGroups = user.groups or [ ];
        shell =
          if (user.login-shell or "bash") == "bash" then
            pkgs.bashInteractive
          else
            if builtins.elem "terminal" context.enabledModules then pkgs.zsh
            else throw "Folio: Zsh login-shell requires the system terminal module";
        initialPassword = "kl;'";
      }
    ) context.identity.users
  );
}
