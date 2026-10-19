{ pkgs, lib }:
{
  models.system = [ ./model/folio-appearance.yang ];
  models.user = [ ./model/folio-appearance.yang ];
  nixosModule = import ./src/system.nix { inherit pkgs; };
  homeManagerModule = import ./src/user.nix { inherit pkgs lib; };
}
