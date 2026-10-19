{ pkgs }:
let
  tools = pkgs.writeShellApplication {
    name = "folio-network-control";
    runtimeInputs = [ pkgs.jq pkgs.coreutils pkgs.util-linux pkgs.networkmanager pkgs.curl ];
    text = builtins.readFile ../runtime/operations/control.sh;
  };
  subscriber = pkgs.stdenv.mkDerivation {
    pname = "folio-network-subscriber";
    version = "0.1.0";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.folio.sysrepo pkgs.libyang pkgs.jansson ];
    buildPhase = ''
      $CC -std=c11 -Wall -Wextra -Werror -O2 \
        -DTOOL='"${tools}/bin/folio-network-control"' \
        -DTIMEOUT='"${pkgs.coreutils}/bin/timeout"' \
        ${../runtime/main.c} $(pkg-config --cflags --libs sysrepo libyang jansson) -o folio-network-subscriber
    '';
    installPhase = "mkdir -p $out/bin; cp folio-network-subscriber $out/bin/";
  };
  client = pkgs.writeShellApplication {
    name = "folio-network";
    runtimeInputs = [ pkgs.folio.repository pkgs.coreutils pkgs.jq ];
    extraShellCheckFlags = [ "-x" ];
    text = "source ${pkgs.folio.cliSupport}/share/folio/client-common.sh\n" +
      builtins.replaceStrings [ "@requestFilter@" ] [ "${../cli/commands/network/request.jq}" ]
        (builtins.readFile ../cli/commands/network/command.sh);
  };
in { inherit tools subscriber client; }
