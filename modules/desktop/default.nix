{ pkgs, lib }:
let packages = import ./src/package.nix { inherit pkgs; };
in {
  checks.focus-fade = import ./tests/focus-fade.nix { inherit pkgs; niri = packages.niri; };
  requirements.user.capabilities = [ "desktop-provisioned" ];
  impacts = [ "Compositor binary changes require logging out and back in; the current session stays running." ];
  inherit packages;
  models.system = [ ./model/folio-desktop.yang ];
  models.user = [ ./model/folio-desktop.yang ];
  nixosModule = import ./src/system.nix { inherit pkgs lib packages; };
  homeManagerModule = import ./src/user.nix { inherit pkgs lib packages; };
}
