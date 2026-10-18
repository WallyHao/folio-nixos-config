{ pkgs, lib }:
let
  quiescent = pkgs.stdenv.mkDerivation {
    pname = "folio-repository-quiescent";
    version = "0.1.0";
    dontUnpack = true;
    buildPhase = "$CC -std=c11 -Wall -Wextra -Werror -O2 ${../runtime/lib/quiescent.c} -o folio-repository-quiescent";
    installPhase = "mkdir -p $out/bin; cp folio-repository-quiescent $out/bin/";
  };
  library = import ./library.nix { inherit pkgs lib; };
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
    text = builtins.readFile ../runtime/operations/repository.sh;
  };
in
{
  packages = {
    inherit library tools;
    maintenance = pkgs.writeShellApplication {
      name = "folio-repository-maintain";
      runtimeInputs = [
        library
        quiescent
        pkgs.folio.atomicWrite
        pkgs.folio.normalizer
        pkgs.coreutils
        pkgs.jq
        pkgs.util-linux
        pkgs.gawk
        pkgs.gnused
        pkgs.diffutils
        pkgs.nix
      ];
      text = builtins.readFile ../runtime/operations/maintenance.sh;
    };
    libyang = pkgs.libyang;
  };
}
