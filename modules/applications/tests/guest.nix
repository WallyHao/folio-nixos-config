{
  pkgs,
  inputs,
  source,
  bootstrap,
  prepareInput,
  modules,
  cache ? null,
  plans ? null,
}:
let
  descriptor =
    pkgs.runCommand "folio-applications-test-descriptor" { nativeBuildInputs = [ pkgs.jq ]; }
      ''
        jq '.origin="system-generation" | .capabilities += {"system-repository":true}' ${bootstrap}/system-descriptor.json >$out
      '';
  seed =
    pkgs.runCommand "folio-applications-test-source"
      {
        nativeBuildInputs = [
          prepareInput
          pkgs.jq
        ];
      }
      ''
        mkdir $out
        cp -R ${source}/. $out/
        chmod -R u+w $out
        jq '."folio-environment:environment".modules |= map(if .name=="applications" then
          ."folio-applications:applications".app |= map(if .name=="zen" then ."zen-profile"="test.default" else . end)
          else . end)' ${bootstrap}/user.json >configuration.json
        folio-prepare-input configuration.json ${bootstrap} ${descriptor} >$out/folio-input.json
      '';
  generation =
    (import (seed + "/modules/manager/src/outputs.nix") {
      inputs = inputs // {
        self.outPath = seed;
      };
    }).homeConfigurations.folio.activationPackage;
in
pkgs.testers.runNixOSTest {
  name = "folio-owned-applications";
  nodes.machine = { ... }: {
    imports = modules;
    _module.args.folioBootstrap = bootstrap;
    virtualisation = {
      memorySize = 4096;
      cores = 2;
      diskSize = 16384;
      writableStoreUseTmpfs = false;
    };
    environment.systemPackages = [
      pkgs.jq
      pkgs.flatpak
      pkgs.ostree
    ];
    virtualisation.additionalPaths = [
      seed
      generation
    ]
    ++ pkgs.lib.optional (cache != null) cache
    ++ pkgs.lib.optional (plans != null) plans;
  };
  testScript = ''
    import datetime
    import json
    import shlex

    def user(command, timeout=120):
        return machine.succeed("runuser -u folio -- env HOME=/home/folio USER=folio XDG_STATE_HOME=/home/folio/.local/state XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus FLATPAK_GL_DRIVERS=default bash -c " + shlex.quote(command), timeout=datetime.timedelta(seconds=timeout))

    def apps(arguments):
        return json.loads(user("folio --json apps " + arguments, 600))

    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("folio-manager.service", user="folio")
    user("jq .configuration ${seed}/folio-input.json >/home/folio/desired.json; folio --json config import /home/folio/desired.json")
    user("${generation}/activate", 180)
    machine.wait_for_unit("folio-applications.service", user="folio")
    result = apps("list")
    assert result["status"] == "success", result
    assert {app["name"] for app in result["data"]["applications"]} == {"zen", "obs"}
    assert all(not app["installed"] for app in result["data"]["applications"])
    assert all(app["configurationState"] == "configuration-pending" for app in result["data"]["applications"])

    ${pkgs.lib.optionalString (cache != null && plans != null) ''
      with subtest("real isolated cached Flatpak deployment and repeat reconciliation"):
          user("mkdir -p /home/folio/.local/share/flatpak /home/folio/.local/state/folio/applications/prepared; cp -R ${cache}/. /home/folio/.local/share/flatpak/; chmod -R u+w /home/folio/.local/share/flatpak; cp ${plans}/*.json /home/folio/.local/state/folio/applications/prepared/")
          result = apps("install all --offline")
          assert result["status"] == "success", result
          revision = result["taskId"]
          listing = apps("list")["data"]["applications"]
          assert all(app["installed"] and app["owned"] for app in listing), listing
          assert next(app for app in listing if app["name"]=="zen")["configurationState"] == "configuration-pending"
          commits = {app["name"]: app["actual"]["commit"] for app in listing}
          assert commits == {"zen":"7ce097e9b6c826656be4872830a3126e5eebf88a46b0401e87b65dea1403c022", "obs":"21b35765922fb5c8b92ccdccedc0d8ca709b12f86a961780350199082da822ef"}, commits
          assert apps("reconcile all --offline")["status"] == "success"
          operational = json.loads(user("folio-repository user cfg --export --datastore operational --module folio-environment --format json"))
          modeled = next(entry for entry in operational["folio-environment:environment"]["modules"] if entry["name"]=="applications")["folio-applications:applications"]["app"]
          assert all(app["state"]["installed"] and len(app["state"]["actual-commit"])==64 for app in modeled), modeled

      with subtest("explicit adoption and preservation of an independent Flatpak"):
          user("mv /home/folio/.local/state/folio/applications/owned/obs.json /home/folio/old-obs-ownership.json")
          result = json.loads(user("folio --json apps reconcile obs --offline; test $? = 4"))
          assert result["status"] == "conflict", result
          assert apps("adopt obs --offline")["status"] == "success"
          user("mkdir -p /home/folio/independent/files/bin; printf '[Application]\\nname=org.folio.Independent\\nruntime=org.freedesktop.Platform/x86_64/25.08\\ncommand=independent\\n' >/home/folio/independent/metadata; printf '#!/bin/sh\\nexit 0\\n' >/home/folio/independent/files/bin/independent; chmod +x /home/folio/independent/files/bin/independent; flatpak build-finish /home/folio/independent; flatpak build-export --disable-sandbox /home/folio/independent-repo /home/folio/independent stable; flatpak remote-add --user --no-gpg-verify independent /home/folio/independent-repo; flatpak install --user --noninteractive --assumeyes --no-deps independent org.folio.Independent")
          independent = user("flatpak info --user --show-commit org.folio.Independent")
          user("mkdir -p /home/folio/.var/app/org.folio.Independent; printf 'personal sentinel' >/home/folio/.var/app/org.folio.Independent/sentinel")
          assert apps("reconcile all --offline")["status"] == "success"
          assert user("flatpak info --user --show-commit org.folio.Independent") == independent
          assert user("cat /home/folio/.var/app/org.folio.Independent/sentinel") == "personal sentinel"

      with subtest("explicit existing browser profile and regular managed resources"):
          user("mkdir -p /home/folio/.var/app/app.zen_browser.zen/.zen/test.default; printf '[Profile0]\\nName=Test\\nIsRelative=1\\nPath=test.default\\n' >/home/folio/.var/app/app.zen_browser.zen/.zen/profiles.ini; printf 'untouched application data\\n' >/home/folio/.var/app/app.zen_browser.zen/.zen/test.default/prefs.js")
          assert apps("reconcile zen --offline")["status"] == "success"
          user("test -f /home/folio/.var/app/app.zen_browser.zen/.zen/test.default/user.js; test ! -L /home/folio/.var/app/app.zen_browser.zen/.zen/test.default/user.js; grep -q 'untouched application data' /home/folio/.var/app/app.zen_browser.zen/.zen/test.default/prefs.js")
          assert apps("reconcile zen --offline")["status"] == "success"
          assert apps("rollback " + revision + " all --offline")["status"] == "success"

      with subtest("stale manifest leaves regular files pending and untouched"):
          before = user("sha256sum /home/folio/.var/app/app.zen_browser.zen/.zen/test.default/user.js")
          changed = json.loads(user("cat /home/folio/desired.json"))
          changed["folio-environment:environment"]["preferences"]["font-size"] = 17
          user("printf %s " + shlex.quote(json.dumps(changed)) + " >/home/folio/new-desired.json; folio --json config import /home/folio/new-desired.json")
          assert apps("reconcile zen --offline")["status"] == "success"
          assert next(app for app in apps("list")["data"]["applications"] if app["name"]=="zen")["configurationState"] == "configuration-pending"
          assert user("sha256sum /home/folio/.var/app/app.zen_browser.zen/.zen/test.default/user.js") == before
          user("folio --json config import /home/folio/desired.json")

      with subtest("unavailable rollback preflight changes nothing"):
          before = user("flatpak list --user --columns=ref:full,active:full")
          result = json.loads(user("folio --json apps rollback a-00000000000000000000000000000000 all --offline; test $? = 3"))
          assert result["status"] == "unavailable", result
          assert user("flatpak list --user --columns=ref:full,active:full") == before

      with subtest("unexpected browser edits require explicit resolution"):
          user("printf 'unmanaged change\\n' >/home/folio/.var/app/app.zen_browser.zen/.zen/test.default/user.js")
          result = json.loads(user("folio --json apps reconcile zen --offline; test $? = 4"))
          assert result["status"] == "conflict", result
          assert "unmanaged change" in user("cat /home/folio/.var/app/app.zen_browser.zen/.zen/test.default/user.js")
          # A previously owned file cannot silently be adopted over an unknown edit.
          assert result["data"]["recoveryRequired"]
          task = result["taskId"]
          user("source_path=$(jq -r '.source' /home/folio/.local/state/folio/applications/files/*.json | grep 'folio-browser-user.js$'); cp \"$source_path\" /home/folio/.var/app/app.zen_browser.zen/.zen/test.default/user.js")
          assert apps("resume " + task)["status"] == "success"
    ''}
  '';
}
