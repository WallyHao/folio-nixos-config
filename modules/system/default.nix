{ pkgs, lib }:
{
  nixosModule = context: import ./src/system.nix { inherit context; };
}
