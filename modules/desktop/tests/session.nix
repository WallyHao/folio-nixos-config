{
  pkgs,
  inputs,
  source,
  bootstrap,
  prepareInput,
  modules,
  runtime,
  cli,
  legacySource ? null,
  cache ? null,
  plans ? null,
  drm ? true,
}:
let
  legacy =
    if legacySource == null then
      null
    else
      import (legacySource + "/modules/manager/src/outputs.nix") {
        inputs = inputs // {
          self.outPath = legacySource;
        };
      };
  oldBootstrap = if legacy == null then bootstrap else legacy.packages.x86_64-linux.manager-bootstrap;
  descriptor = pkgs.runCommand "folio-desktop-test-descriptor" { nativeBuildInputs = [ pkgs.jq ]; } ''
    jq '.origin="system-generation" | .capabilities += {"system-repository":true}' ${bootstrap}/system-descriptor.json >$out
  '';
  prepared =
    name: base: configuration: modelBootstrap:
    pkgs.runCommand name
      {
        nativeBuildInputs = [ prepareInput ];
      }
      ''
        mkdir $out
        cp -R ${base}/. $out/
        chmod -R u+w $out
        folio-prepare-input ${configuration} ${modelBootstrap} ${descriptor} >$out/folio-input.json
      '';
  oldSeed = prepared "folio-desktop-old-user" (
    if legacy == null then source else legacySource
  ) "${oldBootstrap}/user.json" oldBootstrap;
  schemaSeed = prepared "folio-desktop-schema-upgrade" source "${oldBootstrap}/user.json" bootstrap;
  userSeed = prepared "folio-desktop-user" source "${bootstrap}/user.json" bootstrap;
  generation =
    seed:
    (import (seed + "/modules/manager/src/outputs.nix") {
      inputs = inputs // {
        self.outPath = seed;
      };
    }).homeConfigurations.folio.activationPackage;
  oldGeneration = generation oldSeed;
  schemaGeneration = generation schemaSeed;
  userGeneration = generation userSeed;
  testPython = pkgs.python3.withPackages (p: [
    p.websocket-client
    p.pillow
  ]);
in
pkgs.testers.runNixOSTest {
  name = "folio-desktop-session";
  nodes.machine = { lib, ... }: {
    imports = modules ++ [ (import ./guest.nix { inherit pkgs drm; }) ];
    _module.args.folioBootstrap = bootstrap;
    systemd.user.services.folio-manager.serviceConfig = {
      ExecStartPre = lib.mkForce "${pkgs.folio.repository}/bin/folio-repository user init ${oldBootstrap}/models/user ${oldBootstrap}/user.json";
      # Manager's unchanged global protocol can serve the old installed model
      # set before the explicit upgrade; no new module RPC is used at this point.
      ExecStart = lib.mkForce "${runtime}/bin/folio-manager-subscriber user ${oldBootstrap}";
    };
    virtualisation.additionalPaths = [
      oldSeed
      schemaSeed
      userSeed
      oldGeneration
      schemaGeneration
      userGeneration
      inputs.nixpkgs
      inputs.home-manager
      pkgs.stdenvNoCC
      pkgs.shellcheck-minimal
      pkgs.lndir
      pkgs.perl
    ]
    ++ pkgs.lib.optional (cache != null) cache
    ++ pkgs.lib.optional (plans != null) plans;
    nix.settings.substituters = lib.mkForce [ ];
  };
  testScript = ''
    import datetime
    import json
    import shlex
    import time
    from typing import Any, cast

    cli = "${cli}/bin/folio"
    session_env = {}

    def user(command, timeout=240):
        environment = {"HOME":"/home/folio", "USER":"folio", "XDG_STATE_HOME":"/home/folio/.local/state",
            "XDG_RUNTIME_DIR":"/run/user/1000", "DBUS_SESSION_BUS_ADDRESS":"unix:path=/run/user/1000/bus"}
        environment.update(session_env)
        prefix = "runuser -u folio -- env " + " ".join(shlex.quote(key+"="+value) for key,value in environment.items())
        return machine.succeed(prefix + " bash -c " + shlex.quote("set -euo pipefail; " + command), timeout=datetime.timedelta(seconds=timeout))

    def folio(arguments):
        return json.loads(user(cli + " --json " + arguments, 600))

    def save(configuration):
        user("printf %s " + shlex.quote(json.dumps(configuration)) + " >/home/folio/desired.json")
        result = folio("config import /home/folio/desired.json")
        assert result["status"]=="success", result

    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("folio-manager.service", user="folio")
    ${pkgs.lib.optionalString (!drm) ''machine.wait_for_file("/tmp/.X11-unix/X1")''}
    plan = folio("--user plan --source ${oldSeed}")["data"]["planId"]
    assert folio("build " + plan)["status"]=="success"
    assert folio("apply " + plan)["status"]=="success"

    ${pkgs.lib.optionalString (legacy != null) ''
      with subtest("new user models use the explicit paired schema upgrade path"):
          before = user("readlink -f /home/folio/.local/state/nix/profiles/home-manager").strip()
          user("${runtime}/bin/folio-manager-maintain user ${oldBootstrap} upgrade desktop-models ${schemaSeed}", 600)
          after = user("readlink -f /home/folio/.local/state/nix/profiles/home-manager").strip()
          assert after != before
          user("folio-repository user ctl --list | grep folio-desktop")
    ''}

    save(json.loads(user("jq .configuration ${userSeed}/folio-input.json")))
    plan = folio("--user plan --source ${userSeed}")["data"]["planId"]
    assert folio("build " + plan)["status"]=="success"
    assert folio("apply " + plan)["status"]=="success"
    machine.wait_for_unit("folio-devices.service", user="folio")

    with subtest("actual device observations and unavailable hardware"):
        observed = folio("devices status")
        assert observed["status"]=="success", observed
        assert observed["data"]["hardware"]["logicalCpus"]==4
        assert observed["data"]["physicalAcceptance"]=="unverified"
        assert not observed["data"]["brightness"]["available"]
        result = json.loads(user("code=0; " + cli + " --json devices brightness 50 || code=$?; test $code = 3"))
        assert result["status"]=="unavailable", result

    ${pkgs.lib.optionalString (cache != null && plans != null) ''
      with subtest("cached applications use the actual desktop prerequisites"):
          user("mkdir -p /home/folio/.local/share/flatpak /home/folio/.local/state/folio/applications/prepared; cp -R ${cache}/. /home/folio/.local/share/flatpak/; chmod -R u+w /home/folio/.local/share/flatpak; cp ${plans}/*.json /home/folio/.local/state/folio/applications/prepared/")
          assert folio("apps install all --offline")["status"]=="success"
    ''}

    ${import ./session-script.nix {
      inherit
        pkgs
        drm
        cache
        plans
        testPython
        ;
    }}
  '';
}
