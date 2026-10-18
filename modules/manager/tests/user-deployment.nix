{
  pkgs,
  inputs,
  source,
  bootstrap,
  runtime,
  cli,
  repository,
  prepareInput,
}:
let
  # Seed the exact immutable generations for offline guest builds. This uses the
  # same public frozen-input interface as the CLI, not a substitute activation.
  generation =
    disabled:
    let
      frozen =
        pkgs.runCommand "folio-user-acceptance-source"
          {
            nativeBuildInputs = [
              pkgs.jq
              prepareInput
            ];
          }
          ''
            mkdir -p $out
            cp -R ${source}/. $out/
            chmod -R u+w $out
            jq '."folio-environment:environment".preferences."font-size"=18 |
              ."folio-environment:environment".modules |= map(
                if .name=="terminal" then .enabled=${if disabled then "false" else "true"} else . end)' \
              ${bootstrap}/user.json > configuration.json
            folio-prepare-input configuration.json ${bootstrap} > $out/folio-input.json
          '';
      evaluated = import ../src/outputs.nix {
        inputs = inputs // {
          self = {
            outPath = frozen;
          };
        };
      };
    in
    evaluated.homeConfigurations.folio.activationPackage;
  enabled = generation false;
  disabled = generation true;
in
pkgs.testers.runNixOSTest {
  name = "folio-user-deployment";
  nodes.machine = { ... }: {
    users.users.folio = {
      isNormalUser = true;
      uid = 1000;
      home = "/home/folio";
      linger = true;
    };
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    nix.settings.substituters = pkgs.lib.mkForce [ ];
    environment.systemPackages = [
      cli
      runtime
      repository
      pkgs.jq
      pkgs.nix
    ];
    systemd.user.services.folio-manager = {
      description = "Folio user configuration subscriber";
      unitConfig.ConditionUser = "folio";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        ExecStartPre = "${repository}/bin/folio-repository user init ${bootstrap}/models/user ${bootstrap}/user.json";
        ExecStart = "${runtime}/bin/folio-manager-subscriber user ${bootstrap}";
        Restart = "on-failure";
        RestartSec = 2;
        UMask = "0077";
      };
    };
    virtualisation = {
      memorySize = 3072;
      cores = 2;
      diskSize = 4096;
      writableStoreUseTmpfs = false;
      additionalPaths = [
        source
        inputs.nixpkgs
        inputs.home-manager
        enabled
        disabled
      ];
    };
    system.stateVersion = "26.05";
  };
  testScript = ''
    import datetime
    import json
    import shlex

    def user(command, timeout=180):
        prefix = "runuser -u folio -- env HOME=/home/folio USER=folio XDG_STATE_HOME=/home/folio/.local/state XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus bash -c "
        return machine.succeed(prefix + shlex.quote(command), timeout=datetime.timedelta(seconds=timeout))

    def folio(arguments, timeout=180):
        return json.loads(user("folio --json " + arguments, timeout))

    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("user@1000.service")
    machine.wait_for_unit("folio-manager.service", user="folio")
    user("mkdir -p /home/folio/source /home/folio/.config/foot /home/folio/.local/share/foot")
    user("cp -R ${source}/. /home/folio/source/ && chmod -R u+w /home/folio/source")
    user("printf first-adoption > /home/folio/.config/foot/foot.ini; printf preserve > /home/folio/.local/share/foot/keep")
    configuration = folio("config show")["data"]["configuration"]
    configuration["folio-environment:environment"]["preferences"]["font-size"] = 18
    user("printf %s " + shlex.quote(json.dumps(configuration)) + " > /home/folio/draft.json")
    assert folio("config import /home/folio/draft.json")["status"] == "success"

    with subtest("real CLI, subscriber, plan, build and standalone activation"):
        plan = folio("plan --source /home/folio/source")["data"]["planId"]
        assert folio("build " + plan)["status"] == "success"
        assert folio("status")["data"].get("applied") is None
        applied = folio("apply " + plan)
        assert applied["status"] == "success", applied
        state = folio("status")["data"]
        assert state["health"] == "healthy", state
        assert user("readlink -f /home/folio/.local/state/nix/profiles/home-manager").strip() == state["applied"]["artifact"]
        assert "font=Maple Mono NF CN:size=18" in user("cat /home/folio/.config/foot/foot.ini")
        observed = json.loads(user("folio-repository user cfg --export --datastore operational --module folio-environment --format json"))
        assert observed["folio-environment:environment"]["state"]["applied-digest"] == state["applied"]["configurationDigest"]
        tasks = json.loads(user("folio-repository user cfg --export --datastore operational --module folio-deployment --format json"))
        assert any(task["id"] == applied["taskId"] and task["phase"] == "succeeded" for task in tasks["folio-deployment:deployment"]["tasks"])
        assert user("cat /home/folio/.config/foot/foot.ini.folio-backup-*").strip() == "first-adoption"
        assert user("test -L /home/folio/.local/state/folio/deployments/roots/build-" + plan) == ""

    with subtest("later unmanaged changes conflict without replacing user data"):
        plan = folio("plan --source /home/folio/source")["data"]["planId"]
        assert folio("build " + plan)["status"] == "success"
        user("mv /home/folio/.config/foot/foot.ini /home/folio/managed-foot; printf user-edit > /home/folio/.config/foot/foot.ini")
        result = json.loads(user("folio --json apply " + plan + "; test $? -eq 4"))
        assert result["status"] == "conflict", result
        assert user("cat /home/folio/.config/foot/foot.ini").strip() == "user-edit"
        assert folio("status")["data"]["health"] == "degraded"
        user("rm /home/folio/.config/foot/foot.ini; mv /home/folio/managed-foot /home/folio/.config/foot/foot.ini")

    with subtest("disabling removes contribution and preserves application data"):
        assert folio("modules disable terminal")["status"] == "success"
        plan = folio("plan --source /home/folio/source")["data"]["planId"]
        assert folio("build " + plan)["status"] == "success"
        assert folio("apply " + plan)["status"] == "success"
        user("test ! -e /home/folio/.config/foot/foot.ini")
        assert user("cat /home/folio/.local/share/foot/keep").strip() == "preserve"
        assert folio("status")["data"]["health"] == "healthy"
        user("systemctl --user restart folio-manager.service")
        machine.wait_for_unit("folio-manager.service", user="folio")
        modules = folio("config show")["data"]["configuration"]["folio-environment:environment"]["modules"]
        assert next(item for item in modules if item["name"] == "terminal")["enabled"] is False
  '';
}
