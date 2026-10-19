{ pkgs }:
let
  keyringHelper = pkgs.stdenv.mkDerivation {
    pname = "folio-keyring-password";
    version = "0.1.0";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.glib ];
    buildPhase = ''
      $CC -std=c11 -Wall -Wextra -Werror -O2 \
        ${../runtime/keyring-password.c} $(pkg-config --cflags --libs gio-2.0) -o folio-keyring-password
    '';
    installPhase = "mkdir -p $out/bin; cp folio-keyring-password $out/bin/";
  };
  keyring = pkgs.writeShellApplication {
    name = "folio-migrate-keyring";
    runtimeInputs = [ pkgs.coreutils pkgs.getent keyringHelper ];
    text = builtins.readFile ../runtime/migrate-keyring.sh;
  };
  migration = pkgs.writeShellApplication {
    name = "folio-migrate-account";
    runtimeInputs = with pkgs; [ coreutils findutils gnugrep gnused gawk diffutils
      jq util-linux shadow btrfs-progs nix systemd gnutar procps getent glibc.bin ];
    text = builtins.readFile ../runtime/migrate-account.sh;
  };
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
        ${../runtime/main.c} $(pkg-config --cflags --libs sysrepo libyang jansson) -o folio-system-subscriber
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
    + builtins.replaceStrings [ "@requestFilter@" ] [ "${../cli/commands/system/request.jq}" ] (builtins.readFile ../cli/commands/system/command.sh);
  };
in
{
  inherit runtime client migration keyring;
}
