{ pkgs }:
pkgs.stdenv.mkDerivation {
  pname = "folio-input-language";
  version = "0.1.0";
  dontUnpack = true;
  nativeBuildInputs = [ pkgs.pkg-config ];
  buildInputs = [ pkgs.glib pkgs.jansson ];
  buildPhase = ''
    $CC -std=c11 -Wall -Wextra -Werror -O2 ${../runtime/observers/language.c} \
      $(pkg-config --cflags --libs gio-2.0 gio-unix-2.0 jansson) -o folio-input-language
  '';
  installPhase = "mkdir -p $out/bin; cp folio-input-language $out/bin/";
}
