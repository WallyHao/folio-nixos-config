{ pkgs, lib }:
let packages = import ./src/package.nix { inherit pkgs; };
in {
  inherit packages;
  migrationModule = { ... }: {
    services.gnome.gnome-keyring.enable = true;
    security.pam.services.greetd.enableGnomeKeyring = true;
    security.pam.services.login.enableGnomeKeyring = true;
    security.pam.services.passwd.enableGnomeKeyring = true;
  };
  models.system = [ ./model/folio-desktop.yang ];
  models.user = [ ./model/folio-desktop.yang ];
  nixosModule = import ./src/system.nix { inherit pkgs lib; };
  homeManagerModule = import ./src/user.nix { inherit pkgs lib packages; };
}
