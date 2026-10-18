{
  stdenv,
  libyang,
  pkg-config,
  writeShellApplication,
  jq,
}:
let
  binary = stdenv.mkDerivation {
    pname = "folio-normalize-data";
    version = "0.1.0";
    dontUnpack = true;
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ libyang ];
    buildPhase = ''
      $CC -D_GNU_SOURCE -std=c11 -Wall -Wextra -Werror -O2 \
        ${./normalize.c} $(pkg-config --cflags --libs libyang) -o folio-normalize-data
    '';
    installPhase = ''
      mkdir -p $out/bin
      cp folio-normalize-data $out/bin/
    '';
  };
in
writeShellApplication {
  name = "folio-normalize";
  runtimeInputs = [
    binary
    jq
  ];
  text = ''
    folio-normalize-data "$@" | jq -cS -f ${./normalize.jq}
  '';
}
