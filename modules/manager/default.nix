{ pkgs, lib, cliCommands ? { } }:
let implementation = import ./src/package.nix { inherit pkgs lib cliCommands; };
in
{
  subscribers = {
    user = [ "folio-manager.service" ];
    system = [ "folio-manager.service" ];
  };
  models = {
    system = [
      ./model/folio-environment.yang
      ./model/folio-deployment.yang
    ];
    user = [
      ./model/folio-environment.yang
      ./model/folio-deployment.yang
    ];
  };
  inherit (implementation) packages commands;
  nixosModule = import ./src/system.nix {
    inherit pkgs lib;
    inherit (implementation) client runtime normalizer;
  };
  homeManagerModule = import ./src/user.nix {
    inherit pkgs;
    inherit (implementation) client runtime;
  };
}
