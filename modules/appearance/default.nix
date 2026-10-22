{ pkgs, lib }:
{
  checks.contrast = import ./tests/contrast.nix { inherit pkgs; };
  checks.themes = import ./tests/themes.nix { inherit pkgs; };
  checks.gtk = import ./tests/gtk.nix { inherit pkgs; };
  migrations = import ./theme-migrations.nix { inherit pkgs; };
  models.system = [ ./model/folio-appearance.yang ];
  models.user = [ ./model/folio-appearance.yang ];
  impacts = [ "Restart open applications to reload fonts and GTK styles." ];
  nixosModule = import ./src/system.nix { inherit pkgs; };
  homeManagerModule = import ./src/user.nix { inherit pkgs lib; };
}
