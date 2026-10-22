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
      $CC -std=c11 -Wall -Wextra -Werror -O2 ${../runtime/journal/atomic.c} -o folio-atomic-write
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
        pkgs.bash
        pkgs.jq
        pkgs.util-linux
        pkgs.nix
        pkgs.systemd
        pkgs.gnutar
        pkgs.findutils
        pkgs.diffutils
        pkgs.python3
        prepareInput
      ];
      text =
        "export FOLIO_CATALOGUE=${pkgs.folio.catalogue}\n"
        + builtins.readFile ../runtime/lib/common.sh
        + "\n"
        + builtins.readFile ../runtime/journal/common.sh
        + "\n"
        + builtins.readFile ../runtime/lib/effects.sh
        + "\n"
        + text;
    };
  configuration = operation "folio-manager-configuration" (
    builtins.replaceStrings [ "@requirements@" ] [ "${../runtime/snapshot/requirements.py}" ]
      (builtins.readFile ../runtime/operations/configuration.sh));
  maintenance = pkgs.writeShellApplication {
    name = "folio-manager-maintain";
    runtimeInputs = [
      atomic repository normalizer prepareInput pkgs.folio.repositoryMaintenance
      pkgs.coreutils pkgs.bash pkgs.jq pkgs.util-linux pkgs.nix pkgs.systemd
      pkgs.findutils pkgs.diffutils pkgs.ripgrep
    ];
    text = builtins.replaceStrings [ "@compatibilitySource@" ] [ (toString pkgs.folio.source) ] (builtins.readFile ../runtime/operations/rollback.sh);
  };
  cleanup = pkgs.writeShellApplication {
    name = "folio-manager-cleanup";
    runtimeInputs = [ atomic pkgs.coreutils pkgs.jq pkgs.util-linux ];
    text = builtins.readFile ../runtime/operations/cleanup.sh;
  };
  recovery = operation "folio-manager-recover" (builtins.readFile ../runtime/journal/recover.sh);
  plan = operation "folio-manager-plan" (
    builtins.replaceStrings [ "@review@" ] [ "${../runtime/snapshot/review.py}" ]
      (builtins.readFile ../runtime/operations/plan.sh)
  );
  worker = operation "folio-manager-worker" (builtins.readFile ../runtime/operations/deploy.sh);
  status = operation "folio-manager-status" (builtins.readFile ../runtime/operations/status.sh);
  observed = operation "folio-manager-observed" (builtins.readFile ../runtime/callbacks/operational-data.sh);
  submission =
    kind:
    operation "folio-manager-${kind}" (
      "operation_kind=${kind}\n"
      + builtins.replaceStrings [ "@worker@" ] [ "${worker}" ] (builtins.readFile ../runtime/operations/submit.sh)
    );
in
pkgs.symlinkJoin {
  name = "folio-manager-runtime";
  passthru.atomic = atomic;
  paths = [
    maintenance
    cleanup
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
          ${../runtime/main.c} $(pkg-config --cflags --libs sysrepo libyang jansson) -o folio-manager-subscriber
      '';
      installPhase = ''
        mkdir -p $out/bin
        cp folio-manager-subscriber $out/bin/
      '';
    })
  ];
}
