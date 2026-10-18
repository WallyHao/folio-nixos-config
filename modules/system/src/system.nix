{ context }:
{ pkgs, ... }:
{
  # Disposable bootstrap fixture, never a physical installation description.
  system.stateVersion = "26.05";
  networking.hostName = context.identity.environment;
  boot.loader.grub.enable = false;
  fileSystems."/" = {
    device = "/dev/disk/by-label/folio-vm";
    fsType = "ext4";
  };
  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "en_US.UTF-8";
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  users.users.folio = {
    isNormalUser = true;
    uid = 1000;
    home = "/home/folio";
  };
}
