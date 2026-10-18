{ pkgs }:
let
  runtime = pkgs.stdenv.mkDerivation {
    pname = "folio-system-subscriber";
    version = "0.1.0";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [
      pkgs.folio.sysrepo
      pkgs.libyang
      pkgs.jansson
    ];
    buildPhase = ''
      $CC -std=c11 -Wall -Wextra -Werror -O2 \
        -DATOMIC_WRITE='"${pkgs.folio.atomicWrite}/bin/folio-atomic-write"' \
        -DTIMEOUT='"${pkgs.coreutils}/bin/timeout"' \
        -DSYSTEMD_RUN='"${pkgs.systemd}/bin/systemd-run"' \
        -DSYSTEMCTL='"${pkgs.systemd}/bin/systemctl"' \
        ${./power.c} $(pkg-config --cflags --libs sysrepo libyang jansson) -o folio-system-subscriber
    '';
    installPhase = "mkdir -p $out/bin; cp folio-system-subscriber $out/bin/";
  };
  client = pkgs.writeShellApplication {
    name = "folio-system";
    runtimeInputs = [
      pkgs.folio.repository
      pkgs.jq
      pkgs.coreutils
    ];
    extraShellCheckFlags = [ "-x" ];
    text = ''
      source ${pkgs.folio.cliSupport}/share/folio/client-common.sh
    ''
    + builtins.readFile ./power-client.sh;
  };
in
{
  inherit runtime client;
}
