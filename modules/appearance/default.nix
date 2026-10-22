{ pkgs, lib }:
{
  checks.gtk = import ./tests/gtk.nix { inherit pkgs; };
  models.system = [ ./model/folio-appearance.yang ];
  models.user = [ ./model/folio-appearance.yang ];
  impacts = [ "Restart open applications to reload fonts and GTK styles." ];
  nixosModule = import ./src/system.nix { inherit pkgs; };
  homeManagerModule = import ./src/user.nix { inherit pkgs lib; };
}
