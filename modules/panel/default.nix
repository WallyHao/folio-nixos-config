{ pkgs, legacyCli, wifi, devices, repository }:
{
  packages.cli = import ./src/package.nix { inherit pkgs legacyCli wifi devices repository; };
}
