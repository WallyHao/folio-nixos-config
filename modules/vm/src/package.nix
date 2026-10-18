{ pkgs, tools }:
{
  subscriber = pkgs.stdenv.mkDerivation {
    pname = "folio-vm-subscriber";
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
        -DTOOL='"${tools}/bin/folio-vm-tool"' \
        -DTIMEOUT='"${pkgs.coreutils}/bin/timeout"' \
        ${../runtime/main.c} $(pkg-config --cflags --libs sysrepo libyang jansson) -o folio-vm-subscriber
    '';
    installPhase = "mkdir -p $out/bin; cp folio-vm-subscriber $out/bin/";
  };
  client = pkgs.writeShellApplication {
    name = "folio-vm";
    runtimeInputs = [
      pkgs.folio.repository
      pkgs.jq
      pkgs.coreutils
    ];
    extraShellCheckFlags = [ "-x" ];
    text = ''
      source ${pkgs.folio.cliSupport}/share/folio/client-common.sh
    ''
    + builtins.replaceStrings [ "@requestFilter@" ] [ "${../cli/commands/vm/request.jq}" ] (builtins.readFile ../cli/commands/vm/command.sh);
  };
}
