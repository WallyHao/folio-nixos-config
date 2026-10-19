{ pkgs, lib }:
let package = import ./src/package.nix { inherit pkgs; };
in {
  models.user = [ ./model/folio-codex.yang ];
  packages.application = package;
  homeManagerModule = import ./src/user.nix { inherit pkgs lib package; };
}
