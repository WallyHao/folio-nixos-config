{ pkgs }:
let
  tools = pkgs.writeShellApplication {
    name = "folio-devices-control";
    runtimeInputs = [ pkgs.jq pkgs.coreutils pkgs.util-linux pkgs.systemd pkgs.pulseaudio
      pkgs.wireplumber pkgs.brightnessctl pkgs.power-profiles-daemon pkgs.gawk ];
    text = builtins.readFile ../runtime/operations/control.sh;
  };
  subscriber = pkgs.stdenv.mkDerivation {
    pname = "folio-devices-subscriber";
    version = "0.1.0";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.folio.sysrepo pkgs.libyang pkgs.jansson ];
    buildPhase = ''
      $CC -std=c11 -Wall -Wextra -Werror -O2 \
        -DTOOL='"${tools}/bin/folio-devices-control"' \
        -DTIMEOUT='"${pkgs.coreutils}/bin/timeout"' \
        ${../runtime/main.c} $(pkg-config --cflags --libs sysrepo libyang jansson) -o folio-devices-subscriber
    '';
    installPhase = "mkdir -p $out/bin; cp folio-devices-subscriber $out/bin/";
  };
  client = pkgs.writeShellApplication {
    name = "folio-devices";
    runtimeInputs = [ pkgs.folio.repository pkgs.coreutils pkgs.jq ];
    extraShellCheckFlags = [ "-x" ];
    text = "source ${pkgs.folio.cliSupport}/share/folio/client-common.sh\n" +
      builtins.replaceStrings [ "@requestFilter@" ] [ "${../cli/commands/devices/request.jq}" ]
        (builtins.readFile ../cli/commands/devices/command.sh);
  };
in { inherit tools subscriber client; }
