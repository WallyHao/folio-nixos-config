{
  pkgs,
  files,
  transaction,
}:
let
  dependencies = [
    pkgs.folio.repository
    pkgs.folio.normalizer
    pkgs.folio.atomicWrite
    pkgs.flatpak
    pkgs.ostree
    pkgs.jq
    pkgs.coreutils
    pkgs.util-linux
    pkgs.systemd
    pkgs.gawk
    pkgs.nix
    files
    transaction
  ];
  common = builtins.readFile ../runtime/lib/common.sh;
  worker = pkgs.writeShellApplication {
    name = "folio-applications-worker";
    runtimeInputs = dependencies;
    text =
      common
      + "\n"
      + builtins.readFile ../runtime/operations/files.sh
      + "\n"
      + builtins.readFile ../runtime/operations/reconcile.sh;
  };
  tools = pkgs.writeShellApplication {
    name = "folio-applications-tool";
    runtimeInputs = dependencies;
    text =
      common
      + "\n"
      + builtins.replaceStrings [ "@worker@" ] [ "${worker}" ] (
        builtins.readFile ../runtime/operations/dispatch.sh
      );
  };
  subscriber = pkgs.stdenv.mkDerivation {
    pname = "folio-applications-subscriber";
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
        -DTOOL='"${tools}/bin/folio-applications-tool"' \
        -DTIMEOUT='"${pkgs.coreutils}/bin/timeout"' \
        ${../runtime/main.c} $(pkg-config --cflags --libs sysrepo libyang jansson) -o folio-applications-subscriber
    '';
    installPhase = "mkdir -p $out/bin; cp folio-applications-subscriber $out/bin/";
  };
  client = pkgs.writeShellApplication {
    name = "folio-apps";
    extraShellCheckFlags = [ "-x" ];
    runtimeInputs = [
      pkgs.folio.repository
      pkgs.folio.configClient
      pkgs.jq
      pkgs.coreutils
    ];
    text =
      "source ${pkgs.folio.cliSupport}/share/folio/client-common.sh\n"
      + builtins.replaceStrings [ "@requestFilter@" ] [ "${../cli/commands/applications/request.jq}" ] (
        builtins.readFile ../cli/commands/applications/command.sh
      );
  };
in
{
  inherit
    worker
    tools
    subscriber
    client
    ;
}
