{
  pkgs,
  sysrepo,
  repository,
  normalizer,
  prepareInput,
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
    name: text:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        atomic
        repository
        normalizer
        pkgs.coreutils
        pkgs.jq
        pkgs.util-linux
        pkgs.nix
        pkgs.systemd
        pkgs.gnutar
        pkgs.findutils
        pkgs.diffutils
        prepareInput
      ];
      text = builtins.readFile ./common.sh + "\n" + builtins.readFile ./task-common.sh + "\n" + text;
    };
  configuration = operation "folio-manager-configuration" (builtins.readFile ./configuration.sh);
  recovery = operation "folio-manager-recover" (builtins.readFile ./recover.sh);
  plan = operation "folio-manager-plan" (builtins.readFile ./plan.sh);
  worker = operation "folio-manager-worker" (builtins.readFile ./worker.sh);
  status = operation "folio-manager-status" (builtins.readFile ./status.sh);
  observed = operation "folio-manager-observed" (builtins.readFile ./observed.sh);
  submission =
    kind:
    operation "folio-manager-${kind}" (
      "operation_kind=${kind}\n"
      + builtins.replaceStrings [ "@worker@" ] [ "${worker}" ] (builtins.readFile ./submit.sh)
    );
in
pkgs.symlinkJoin {
  name = "folio-manager-runtime";
  paths = [
    worker
    (pkgs.stdenv.mkDerivation {
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
          -DPLAN_OPERATION='"${plan}/bin/folio-manager-plan"' \
          -DBUILD_OPERATION='"${submission "build"}/bin/folio-manager-build"' \
          -DAPPLY_OPERATION='"${submission "apply"}/bin/folio-manager-apply"' \
          -DSTATUS_OPERATION='"${status}/bin/folio-manager-status"' \
          -DOBSERVED_OPERATION='"${observed}/bin/folio-manager-observed"' \
          -DTIMEOUT_PROGRAM='"${pkgs.coreutils}/bin/timeout"' \
          ${./subscriber.c} $(pkg-config --cflags --libs sysrepo libyang jansson) -o folio-manager-subscriber
      '';
      installPhase = ''
        mkdir -p $out/bin
        cp folio-manager-subscriber $out/bin/
      '';
    })
  ];
}
