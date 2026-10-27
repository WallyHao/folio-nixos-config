{
  pkgs,
  inputs,
  source,
  bootstrap,
  modules,
}:
pkgs.testers.runNixOSTest {
  name = "folio-system-configuration";
  nodes.machine = { lib, ... }: {
    imports = modules;
    _module.args.folioBootstrap = bootstrap;
    # QEMU provides the test clock; this access-policy fixture does not test NTP.
    services.timesyncd.enable = lib.mkForce false;
    fileSystems."/".device = lib.mkForce "/dev/disk/by-label/nixos";
    users.users.visitor = {
      isNormalUser = true;
      uid = 1001;
    };
    virtualisation.memorySize = 1536;
    virtualisation.cores = 2;
    virtualisation.additionalPaths = [
      source
      inputs.nixpkgs
      inputs.home-manager
    ];
  };
  testScript = ''
    import datetime
    import json
    import shlex

    def user(command, account="folio"):
        prefix = "runuser -u " + account + " -- env HOME=/home/" + account + " USER=" + account
        if account == "folio":
            prefix += " XDG_STATE_HOME=/home/folio/.local/state XDG_RUNTIME_DIR=/run/user/1000"
        return machine.succeed(prefix + " bash -c " + shlex.quote(command))

    machine.start()
    machine.wait_for_unit("folio-manager.service")
    machine.wait_for_unit("user@1000.service")
    machine.wait_for_unit("folio-manager.service", user="folio")
    machine.wait_until_succeeds("runuser -u folio -- folio --json --system status >/dev/null", timeout=datetime.timedelta(seconds=30))
    boot = machine.succeed("cat /proc/sys/kernel/random/boot_id").strip()

    with subtest("provisioned operator access uses real kernel and library permissions"):
        system = json.loads(user("folio --json --system config show"))
        assert system["data"]["configuration"]["folio-environment:environment"]["scope"] == "system"
        assert user("stat -c '%U %G %a' /var/lib/folio/sysrepo").strip() == "root folio-operators 2770"
        user("test ! -w /var/lib/folio/deployments")
        denied = json.loads(user("folio --json --system config show; test $? -ne 0", "visitor"))
        assert denied["status"] != "success"
        user("if sudo -n true 2>/dev/null; then exit 1; fi")
        assert "folio" not in machine.succeed("nix config show trusted-users").split()

    with subtest("root desired data is durable and separate from compiled defaults and user data"):
        configuration = system["data"]["configuration"]
        configuration["folio-environment:environment"]["preferences"]["font-size"] = 20
        user("printf %s " + shlex.quote(json.dumps(configuration)) + " > /home/folio/system-draft.json")
        saved = json.loads(user("folio --json --system config import /home/folio/system-draft.json"))
        assert saved["status"] == "success", saved
        assert json.loads(user("folio --json config show"))["data"]["configuration"]["folio-environment:environment"]["preferences"]["font-size"] == 16
        descriptor = json.loads(user("cat /run/folio/public/system-descriptor.json", "visitor"))
        assert descriptor["origin"] == "system-generation"
        assert descriptor["preferences"]["font-size"] == 16
        compiled = json.loads(machine.succeed("cat ${bootstrap}/system-descriptor.json"))
        assert descriptor["users"] == compiled["users"]
        assert "folio-operators" in descriptor["users"][0]["groups"]
        user("test ! -w /run/folio/public/system-descriptor.json")
        user("mkdir -p /home/folio/source; cp -R ${source}/. /home/folio/source/; chmod -R u+w /home/folio/source")
        plan = json.loads(user("folio --json --user plan --source /home/folio/source"))
        snapshot = plan["data"]["plan"]["source"]
        frozen = json.loads(user("cat " + shlex.quote(snapshot + "/folio-input.json")))
        assert frozen["systemDescriptor"] == descriptor
        assert frozen["systemDescriptor"]["origin"] == "system-generation"
        machine.succeed("systemctl restart folio-manager.service")
        machine.wait_until_succeeds("runuser -u folio -- folio --json --system status >/dev/null", timeout=datetime.timedelta(seconds=30))
        assert json.loads(user("folio --json --system config show"))["data"]["configuration"]["folio-environment:environment"]["preferences"]["font-size"] == 20
        observed = json.loads(user("folio-repository system cfg --export --datastore operational --module folio-environment --format json"))
        assert observed["folio-environment:environment"]["configuration"]["saved"] is True
        result = json.loads(user("folio --json --system modules enable neovim; test $? -eq 2"))
        assert result["status"] == "invalid"
        assert machine.succeed("cat /proc/sys/kernel/random/boot_id").strip() == boot
  '';
}
