{ context }:
{ pkgs, lib, ... }:
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
            throw "Folio: Zsh login-shell capability is not implemented yet";
        initialPassword = "kl;'";
      }
    ) context.identity.users
  );
}
