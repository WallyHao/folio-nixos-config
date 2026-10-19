{ pkgs, lib }:
let packages = import ./src/package.nix { inherit pkgs; };
in {
  inherit packages;
  models.system = [ ./model/folio-desktop.yang ];
  models.user = [ ./model/folio-desktop.yang ];
  nixosModule = import ./src/system.nix { inherit pkgs lib; };
  homeManagerModule = import ./src/user.nix { inherit pkgs lib packages; };
}
