{ pkgs, lib }:
{ nixosModule = import ./src/system.nix { inherit pkgs lib; }; }
