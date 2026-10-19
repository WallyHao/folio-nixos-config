{
  pkgs,
  inputs,
  source,
  bootstrap,
  prepareInput,
  modules,
  recovery ? false,
  integrated ? false,
  cache ? null,
  plans ? null,
}:
let
  guest = if integrated then import ./release-guest.nix { inherit pkgs; } else ./system-guest.nix;
  guestImport = if integrated then ''(import ./modules/manager/tests/release-guest.nix {
    pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
  })'' else "./modules/manager/tests/system-guest.nix";
  testPython = pkgs.python3.withPackages (p: [ p.websocket-client p.pillow ]);
  fixtureFlake = pkgs.writeText "folio-system-test-flake.nix" ''
    {
      inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
        home-manager = { url = "github:nix-community/home-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
      };
      outputs = inputs:
        let base = import ./modules/manager/src/outputs.nix { inherit inputs; };
        in base // {
          nixosConfigurations.portable = base.nixosConfigurations.portable.extendModules {
            modules = [
              (inputs.nixpkgs + "/nixos/modules/virtualisation/qemu-vm.nix")
              (inputs.nixpkgs + "/nixos/lib/testing/nixos-test-base.nix")
              ${guestImport}
            ];
          };
        };
    }
  '';
  currentFixtureSource = pkgs.runCommand "folio-system-test-source" { } ''
    mkdir $out
    cp -R ${source}/. $out/
    chmod -R u+w $out
    cp ${fixtureFlake} $out/flake.nix
    ln -s ../runtime/lib/common.sh $out/modules/manager/tests/frozen-link
  '';
  fixtureSource = if recovery then pkgs.runCommand "folio-legacy-schema-test-source" { } ''
    mkdir $out
    cp -R ${currentFixtureSource}/. $out/
    chmod -R u+w $out
    cp $out/modules/terminal/model/revisions/2026-10-18/folio-terminal.yang $out/modules/terminal/model/folio-terminal.yang
  '' else currentFixtureSource;
  fixtureBootstrap = if recovery then
    (import (fixtureSource + "/modules/manager/src/outputs.nix") {
      inputs = inputs // { self.outPath = fixtureSource; };
    }).packages.${pkgs.stdenv.hostPlatform.system}.manager-bootstrap
  else bootstrap;
  descriptor = pkgs.runCommand "folio-system-test-descriptor" { nativeBuildInputs = [ pkgs.jq ]; } ''
    jq '.origin="system-generation" | .capabilities += {"system-repository":true}' ${bootstrap}/system-descriptor.json >$out
  '';
  preparedSource =
    scope:
    pkgs.runCommand "folio-${scope}-deployment-seed"
      {
        nativeBuildInputs = [
          prepareInput
          pkgs.jq
        ];
      }
      ''
        mkdir $out
        cp -R ${fixtureSource}/. $out/
        chmod -R u+w $out
        jq ${
          pkgs.lib.escapeShellArg (
            if scope == "user" then
              ''."folio-environment:environment".preferences."font-size"=18''
            else
              ''
                ."folio-environment:environment".preferences."font-size"=20 |
                        ."folio-environment:environment".modules |= map(if .name=="system"
                          then ."folio-system:system"."time-zone"="UTC" else . end)''
          )
        } \
          ${fixtureBootstrap}/${scope}.json > configuration.json
        folio-prepare-input configuration.json ${fixtureBootstrap} ${descriptor} >$out/folio-input.json
      '';
  userSeed = import (preparedSource "user" + "/modules/manager/src/outputs.nix") {
    inputs = inputs // {
      self.outPath = preparedSource "user";
    };
  };
  systemSeedBase = import (preparedSource "system" + "/modules/manager/src/outputs.nix") {
    inputs = inputs // {
      self.outPath = preparedSource "system";
    };
  };
  systemSeed = systemSeedBase.nixosConfigurations.portable.extendModules {
    modules = [
      (inputs.nixpkgs + "/nixos/modules/virtualisation/qemu-vm.nix")
      (inputs.nixpkgs + "/nixos/lib/testing/nixos-test-base.nix")
      guest
    ];
  };
  laterSource = pkgs.runCommand "folio-release-later-user" { nativeBuildInputs = [ prepareInput pkgs.jq ]; } ''
    mkdir $out
    cp -R ${fixtureSource}/. $out/
    chmod -R u+w $out
    jq '.preferences."font-size"=20' ${descriptor} > descriptor.json
    jq '."folio-environment:environment".preferences."font-size"=24' ${bootstrap}/user.json > configuration.json
    folio-prepare-input configuration.json ${bootstrap} descriptor.json >$out/folio-input.json
  '';
  laterUser = (import (laterSource + "/modules/manager/src/outputs.nix") {
    inputs = inputs // { self.outPath = laterSource; };
  }).homeConfigurations.folio.activationPackage;
  defaultUser =
    (import (fixtureSource + "/modules/manager/src/outputs.nix") {
      inputs = inputs // {
        self.outPath = fixtureSource;
      };
    }).homeConfigurations.folio.activationPackage;
  migrationSource = pkgs.runCommand "folio-schema-upgrade-source" {
    nativeBuildInputs = [ prepareInput pkgs.jq ];
  } ''
    mkdir $out
    cp -R ${currentFixtureSource}/. $out/
    chmod -R u+w $out
    jq '.preferences."font-size"=20' ${descriptor} > descriptor.json
    jq '."folio-environment:environment".preferences."font-size"=18' ${bootstrap}/user.json > configuration.json
    folio-prepare-input configuration.json ${bootstrap} descriptor.json >$out/folio-input.json
  '';
  migrationSeed = import (migrationSource + "/modules/manager/src/outputs.nix") {
    inputs = inputs // { self.outPath = migrationSource; };
  };
in
pkgs.testers.runNixOSTest {
  name = if integrated then "folio-integrated-release" else if recovery then "folio-deployment-recovery" else "folio-system-deployment";
  nodes.machine = { ... }: {
    imports = modules ++ [ guest ];
    _module.args.folioBootstrap = fixtureBootstrap;
    virtualisation.additionalPaths = [
      fixtureSource
      inputs.nixpkgs
      inputs.home-manager
      userSeed.homeConfigurations.folio.activationPackage
      systemSeed.config.system.build.toplevel
    ]
    ++ pkgs.lib.optionals integrated [ laterUser testPython pkgs.stdenvNoCC pkgs.shellcheck-minimal pkgs.lndir pkgs.perl ]
    ++ pkgs.lib.optional (cache != null) cache
    ++ pkgs.lib.optional (plans != null) plans
    ++ pkgs.lib.optionals recovery [
      defaultUser migrationSource migrationSeed.homeConfigurations.folio.activationPackage
      # Rebuilding retained source may produce a new wrapper derivation even
      # when its runtime dependencies are unchanged. Keep the offline guest's
      # native build tools available rather than bootstrapping a compiler there.
      pkgs.stdenv pkgs.stdenvNoCC pkgs.stdenv.cc pkgs.pkg-config
      pkgs.shellcheck-minimal pkgs.makeWrapper pkgs.makeBinaryWrapper pkgs.curl
      pkgs.lndir pkgs.perl pkgs.jansson.dev pkgs.libyang.dev
    ];
  };
  testScript = ''
    import datetime
    import json
    import shlex
    import time
    from typing import Any, cast

    session_env = {}

    def user(command, timeout=240):
        environment = {"HOME":"/home/folio", "USER":"folio", "XDG_STATE_HOME":"/home/folio/.local/state",
            "XDG_RUNTIME_DIR":"/run/user/1000", "DBUS_SESSION_BUS_ADDRESS":"unix:path=/run/user/1000/bus"}
        environment.update(session_env)
        prefix = "runuser -u folio -- env " + " ".join(shlex.quote(key+"="+value) for key,value in environment.items())
        return machine.succeed(prefix + " bash -c " + shlex.quote("set -euo pipefail; " + command), timeout=datetime.timedelta(seconds=timeout))

    def folio(arguments):
        return json.loads(user("folio --json " + arguments))

    def save(configuration, system=False):
        user("printf %s " + shlex.quote(json.dumps(configuration)) + " >/home/folio/draft.json")
        assert folio(("--system " if system else "") + "config import /home/folio/draft.json")["status"] == "success"

    assert ${if integrated && (cache == null || plans == null) then "False" else "True"}, "Integrated acceptance requires isolated Flatpak cache/plans overrides; see README"
    machine.start(allow_reboot=True)
    machine.wait_for_unit("multi-user.target")
    machine.succeed("test -d /sys/firmware/efi")
    machine.wait_for_unit("folio-manager.service")
    machine.wait_for_unit("folio-system.service")
    machine.wait_for_unit("folio-manager.service", user="folio")
    user("mkdir -p /home/folio/source; cp -R ${fixtureSource}/. /home/folio/source/; chmod -R u+w /home/folio/source")
    configuration = folio("config show")["data"]["configuration"]
    configuration["folio-environment:environment"]["preferences"]["font-size"] = 18
    save(configuration)
    plan = folio("plan --source /home/folio/source")["data"]["planId"]
    assert folio("build " + plan)["status"] == "success"
    assert folio("apply " + plan)["status"] == "success"
    user_plan = plan
    user_profile = user("readlink -f /home/folio/.local/state/nix/profiles/home-manager").strip()
    user_digest = folio("config show")["data"]["digest"]

    with subtest("authorized unprivileged system build and recorded root activation"):
        configuration = folio("--system config show")["data"]["configuration"]
        environment = configuration["folio-environment:environment"]
        environment["preferences"]["font-size"] = 20
        next(item for item in environment["modules"] if item["name"]=="system")["folio-system:system"]["time-zone"] = "UTC"
        save(configuration, True)
        plan = folio("--system plan --source /home/folio/source")["data"]["planId"]
        build = folio("--system build " + plan)
        assert build["status"] == "success", build
        assert machine.succeed("stat -c %U /var/lib/folio-builder/.cache/nix").strip() == "folio-builder"
        assert machine.succeed("id -u folio-builder").strip() != "0"
        assert folio("--system apply " + plan)["status"] == "success"
        machine.wait_until_succeeds("runuser -u folio -- folio --json --system status >/dev/null", timeout=datetime.timedelta(seconds=30))
        status = folio("--system status")["data"]
        assert status["health"] == "healthy", status
        assert machine.succeed("readlink -f /run/current-system").strip() == status["applied"]["artifact"]
        assert machine.succeed("readlink -f /etc/localtime").strip().endswith("/zoneinfo/UTC")
        assert user("readlink -f /home/folio/.local/state/nix/profiles/home-manager").strip() == user_profile
        assert folio("config show")["data"]["digest"] == user_digest
        assert "font=Maple Mono NF CN:size=18" in user("cat /home/folio/.config/foot/foot.ini")
        descriptor = json.loads(user("cat /run/folio/public/system-descriptor.json"))
        assert descriptor["preferences"]["font-size"] == 20

    ${pkgs.lib.optionalString recovery (
      builtins.replaceStrings [ "@defaultGeneration@" "@migrationSource@" ] [ (toString defaultUser) (toString migrationSource) ] (
        builtins.readFile ./recovery.py
      )
    )}

    ${pkgs.lib.optionalString (integrated && cache != null && plans != null) ''
    with subtest("module-owned cached Zen and OBS reconciliation"):
        user("mkdir -p /home/folio/.local/share/flatpak /home/folio/.local/state/folio/applications/prepared; cp -R ${cache}/. /home/folio/.local/share/flatpak/; chmod -R u+w /home/folio/.local/share/flatpak; cp ${plans}/*.json /home/folio/.local/state/folio/applications/prepared/")
        assert folio("apps install all --offline")["status"]=="success"
    ''}

    ${pkgs.lib.optionalString integrated (builtins.readFile ./release.py)}

    ${pkgs.lib.optionalString integrated (import ../../desktop/tests/session-script.nix {
      inherit pkgs cache plans testPython;
    })}

    with subtest("unauthorized and arbitrary activation requests have no effects"):
        profile = machine.succeed("readlink -f /run/current-system").strip()
        denied = json.loads(machine.succeed("if runuser -u visitor -- folio --json --system system reboot --request-id denied; then exit 1; fi"))
        assert denied["status"] != "success"
        payload = {"folio-deployment:apply":{"plan-id":plan,"request-id":"bad-payload","executable":"/bin/sh","arguments":"touch /root/folio-payload"}}
        user("printf %s " + shlex.quote(json.dumps(payload)) + " >/home/folio/payload.json")
        user("if folio-repository system cfg --rpc=/home/folio/payload.json --format json; then exit 1; fi")
        machine.succeed("test ! -e /root/folio-payload")
        assert machine.succeed("readlink -f /run/current-system").strip() == profile

    with subtest("owned power actions report acceptance and are observed externally"):
        before_boot = machine.succeed("cat /proc/sys/kernel/random/boot_id").strip()
        accepted = folio("--system system reboot --request-id observed-reboot")
        assert accepted["status"] == "success" and accepted["data"]["phase"] == "accepted", accepted
        assert folio("--system system reboot --request-id observed-reboot")["data"] == accepted["data"]
        machine.wait_for_qmp_event(lambda event: event["event"]=="RESET", timeout=datetime.timedelta(seconds=60))
        machine.connected = False
        session_env.clear()
        machine.wait_for_unit("multi-user.target", timeout=datetime.timedelta(seconds=90))
        after_boot = machine.succeed("cat /proc/sys/kernel/random/boot_id").strip()
        assert before_boot != after_boot
        print(json.dumps({"beforeBootId":before_boot,"afterBootId":after_boot,"userProfile":user_profile,"systemProfile":status["applied"]["artifact"]}))
        machine.wait_for_unit("folio-manager.service")
        machine.wait_for_unit("folio-system.service")
        machine.wait_for_unit("folio-manager.service", user="folio")
        assert user("readlink -f /home/folio/.local/state/nix/profiles/home-manager").strip() == user_profile
        assert folio("config show")["data"]["digest"] == user_digest
        machine.succeed("test -d /sys/firmware/efi")
        if ${if integrated then "True" else "False"}:
            assert folio("status")["data"]["health"] == "healthy"
            assert folio("--system status")["data"]["health"] == "healthy"
            user("folio --json status >/home/folio/release-status.json")
            machine.copy_from_machine("/home/folio/release-status.json")
            user("printf %s " + shlex.quote(json.dumps({"beforeBootId":before_boot,"afterBootId":after_boot,"userProfile":user_profile,"systemProfile":status["applied"]["artifact"]})) + " >/home/folio/release-boot.json")
            machine.copy_from_machine("/home/folio/release-boot.json")
        accepted = folio("--system system poweroff --request-id observed-poweroff")
        assert accepted["data"]["phase"] == "accepted"
        machine.wait_for_qmp_event(lambda event: event["event"]=="SHUTDOWN", timeout=datetime.timedelta(seconds=60))
        machine.wait_for_shutdown(timeout=datetime.timedelta(seconds=60))
        assert machine.process is not None and machine.process.returncode == 0
  '';
}
