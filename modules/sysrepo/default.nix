{ pkgs, lib }:
let
  implementation = import ./src/package.nix { inherit pkgs lib; };
in
{
  inherit (implementation) packages;
  nixosModule = context: { environment.systemPackages = [ implementation.packages.tools ]; };
  homeManagerModule = context: { home.packages = [ implementation.packages.tools ]; };
}
