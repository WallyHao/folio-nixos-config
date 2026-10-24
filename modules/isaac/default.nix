{ pkgs, lib }:
let
  packages = import ./src/package.nix { inherit pkgs lib; };
in
{
  checks.runtime = import ./tests/runtime.nix { inherit pkgs; };
  inherit packages;
  homeManagerModule = import ./src/user.nix { inherit packages; };
}
