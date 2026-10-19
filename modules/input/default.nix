{ pkgs, lib }:
{
  models.user = [ ./model/folio-input.yang ];
  packages.seed = import ./src/package.nix { inherit pkgs; };
  packages.indicator = import ./src/indicator.nix { inherit pkgs; };
  homeManagerModule = import ./src/user.nix { inherit pkgs lib; };
}
