{
  pkgs,
  inputs,
  source,
  bootstrap,
  prepareInput,
  modules,
}:
let
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
              ./modules/manager/tests/system-guest.nix
            ];
          };
        };
    }
  '';
  fixtureSource = pkgs.runCommand "folio-system-test-source" { } ''
    mkdir $out
    cp -R ${source}/. $out/
    chmod -R u+w $out
    cp ${fixtureFlake} $out/flake.nix
    ln -s ../src/common.sh $out/modules/manager/tests/frozen-link
  '';
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
          ${bootstrap}/${scope}.json > configuration.json
        folio-prepare-input configuration.json ${bootstrap} ${descriptor} >$out/folio-input.json
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
      ./system-guest.nix
    ];
  };
in
pkgs.testers.runNixOSTest {
  name = "folio-system-deployment";
  nodes.machine = { ... }: {
    imports = modules ++ [ ./system-guest.nix ];
    _module.args.folioBootstrap = bootstrap;
    virtualisation.additionalPaths = [
      fixtureSource
      inputs.nixpkgs
      inputs.home-manager
      userSeed.homeConfigurations.folio.activationPackage
      systemSeed.config.system.build.toplevel
    ];
  };
  testScript = ''
    import datetime
    import json
    import shlex

    def user(command, timeout=240):
        return machine.succeed("runuser -u folio -- env HOME=/home/folio USER=folio XDG_STATE_HOME=/home/folio/.local/state XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus bash -c " + shlex.quote(command), timeout=datetime.timedelta(seconds=timeout))

    def folio(arguments):
        return json.loads(user("folio --json " + arguments))

    def save(configuration, system=False):
        user("printf %s " + shlex.quote(json.dumps(configuration)) + " >/home/folio/draft.json")
        assert folio(("--system " if system else "") + "config import /home/folio/draft.json")["status"] == "success"

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
        accepted = folio("--system system poweroff --request-id observed-poweroff")
        assert accepted["data"]["phase"] == "accepted"
        machine.wait_for_qmp_event(lambda event: event["event"]=="SHUTDOWN", timeout=datetime.timedelta(seconds=60))
        machine.wait_for_shutdown(timeout=datetime.timedelta(seconds=60))
        assert machine.process is not None and machine.process.returncode == 0
  '';
}
