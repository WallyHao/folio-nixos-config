{ context }:
{ pkgs, lib, ... }:
let
  settings = context.settings;
in
{
  imports = [
    (import ./storage.nix { inherit context; })
    (import ./policy.nix { inherit context; })
  ];
  system.stateVersion = "26.05";
  networking.hostName = context.identity.environment;
  users.users = lib.listToAttrs (
    map (
      user:
      lib.nameValuePair user.name (
        {
          isNormalUser = true;
          linger = true;
          inherit (user) uid home;
          extraGroups = user.groups or [ ];
          shell =
            if (user.login-shell or "bash") == "bash" then
              pkgs.bashInteractive
            else if builtins.elem "terminal" context.enabledModules then
              pkgs.zsh
            else
              throw "Folio: Zsh login-shell requires the system terminal module";
        }
        // (
          if settings.prototype-password or true then
            { initialPassword = "kl;'"; }
          else
            { hashedPassword = "!"; }
        )
      )
    ) context.identity.users
  );
}
