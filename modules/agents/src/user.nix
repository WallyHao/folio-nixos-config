{
  pkgs,
  lib,
  codex,
  pi,
}:
context:
let
  settings = context.settings;
in
{
  imports =
    lib.optional (settings.codex.enabled or true) (
      (import ./codex/user.nix {
        inherit pkgs lib;
        package = codex;
      })
        context
    )
    ++ lib.optional (settings.pi.enabled or false) (
      (import ./pi/user.nix {
        inherit pkgs lib;
        package = pi;
      })
        context
    );
}
