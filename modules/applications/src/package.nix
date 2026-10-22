{ pkgs, lib }:
let
  files = pkgs.stdenv.mkDerivation {
    pname = "folio-applications-files";
    version = "0.1.0";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.jansson pkgs.openssl ];
    buildPhase = ''
      $CC -std=c11 -Wall -Wextra -Werror -O2 ${../runtime/lib/files.c} $(pkg-config --cflags --libs jansson openssl) -o folio-applications-files
    '';
    installPhase = "mkdir -p $out/bin; cp folio-applications-files $out/bin/";
  };
  transaction = pkgs.stdenv.mkDerivation {
    pname = "folio-applications-transaction";
    version = "0.1.0";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.flatpak pkgs.jansson ];
    buildPhase = ''
      $CC -std=gnu11 -Wall -Wextra -Werror -O2 ${../runtime/lib/flatpak.c} $(pkg-config --cflags --libs flatpak jansson) -o folio-applications-transaction
    '';
    installPhase = "mkdir -p $out/bin; cp folio-applications-transaction $out/bin/";
  };
  store = pkgs.runCommand "folio-applications-store" { } ''
    mkdir -p $out/lib
    cp ${../runtime/store.py} $out/lib/folio_store.py
  '';
  runtime = import ./runtime.nix { inherit pkgs files transaction; };
in { inherit files transaction store; inherit (runtime) worker tools subscriber client; }
