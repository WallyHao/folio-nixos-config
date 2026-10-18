{
  pkgs,
  lib,
  cliCommands ? { },
}:
let
  normalizer = pkgs.callPackage ./src/normalizer.nix { };
in
{
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
  packages = {
    inherit normalizer;
    input = pkgs.writeShellApplication {
      name = "folio-prepare-input";
      runtimeInputs = [
        normalizer
        pkgs.jq
        pkgs.coreutils
      ];
      text = builtins.readFile ./src/prepare-input.sh;
    };
  };
  nixosModule = context: { };
  homeManagerModule = context: { };
}
