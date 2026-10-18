{
  pkgs,
  sysrepo,
  repository,
  normalizer,
}:
let
  atomic = pkgs.stdenv.mkDerivation {
    pname = "folio-atomic-write";
    version = "0.1.0";
    dontUnpack = true;
    buildPhase = ''
      $CC -std=c11 -Wall -Wextra -Werror -O2 ${./atomic.c} -o folio-atomic-write
    '';
    installPhase = ''
      mkdir -p $out/bin
      cp folio-atomic-write $out/bin/
    '';
  };
  operation =
    name: source:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        atomic
        repository
        normalizer
        pkgs.coreutils
        pkgs.jq
        pkgs.util-linux
      ];
      text = builtins.readFile ./common.sh + "\n" + builtins.readFile source;
    };
  configuration = operation "folio-manager-configuration" ./configuration.sh;
  recovery = operation "folio-manager-recover" ./recover.sh;
in
pkgs.stdenv.mkDerivation {
  pname = "folio-manager-subscriber";
  version = "0.1.0";
  dontUnpack = true;
  nativeBuildInputs = [ pkgs.pkg-config ];
  buildInputs = [
    sysrepo
    pkgs.libyang
    pkgs.jansson
  ];
  buildPhase = ''
    $CC -std=c11 -Wall -Wextra -Werror -O2 \
      -DCONFIGURATION_OPERATION='"${configuration}/bin/folio-manager-configuration"' \
      -DRECOVERY_OPERATION='"${recovery}/bin/folio-manager-recover"' \
      -DTIMEOUT_PROGRAM='"${pkgs.coreutils}/bin/timeout"' \
      ${./subscriber.c} $(pkg-config --cflags --libs sysrepo libyang jansson) -o folio-manager-subscriber
  '';
  installPhase = ''
    mkdir -p $out/bin
    cp folio-manager-subscriber $out/bin/
  '';
}
