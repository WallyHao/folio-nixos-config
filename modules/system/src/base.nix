{ context }:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  settings = context.settings;
in
{
  imports = [
    (import ./storage.nix { inherit context; })
    (import ./policy.nix { inherit context; })
  ];
  system.stateVersion = lib.mkDefault "26.05";
  networking.hostName = lib.mkDefault context.identity.environment;
  users.users = lib.listToAttrs (
    map (
      user:
      lib.nameValuePair user.name (
        {
          isNormalUser = true;
          linger = true;
          inherit (user) uid home;
          extraGroups = user.groups or [ ];
          shell = lib.mkDefault (
            if (user.login-shell or "bash") == "bash" then
              pkgs.bashInteractive
            else if builtins.elem "terminal" context.enabledModules then
              pkgs.zsh
            else
              throw "Folio: Zsh login-shell requires the system terminal module"
          );
        }
        // (
          if settings.prototype-password or true then
            { initialPassword = "kl;'"; }
          else
            lib.optionalAttrs config.folio.manageStorage { hashedPassword = "!"; }
        )
      )
    ) context.identity.users
  );
}
