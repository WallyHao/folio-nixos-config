{ pkgs, lib }:
let package = import ./src/package.nix { inherit pkgs; };
in {
  models.user = [ ./model/folio-emacs.yang ];
  packages.editor = package;
  homeManagerModule = import ./src/user.nix { inherit pkgs lib package; };
}
