{ pkgs, lib }:
let
  library = import ./src/package.nix { inherit pkgs lib; };
  tools = pkgs.writeShellApplication {
    name = "folio-repository";
    runtimeInputs = [
      library
      pkgs.coreutils
      pkgs.util-linux
      pkgs.jq
      pkgs.diffutils
      pkgs.gawk
    ];
    text = builtins.readFile ./src/repository.sh;
  };
in
{
  packages = {
    inherit library tools;
    libyang = pkgs.libyang;
  };
  nixosModule = context: { environment.systemPackages = [ tools ]; };
  homeManagerModule = context: { home.packages = [ tools ]; };
}
