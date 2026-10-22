def user_record(path):
    return json.loads(user("cat " + shlex.quote(path)))


def write_fault(path, record, system=False):
    command = "printf %s " + shlex.quote(json.dumps(record)) + " >" + shlex.quote(path)
    (machine.succeed if system else user)(command)


def restart_user_manager():
    user("systemctl --user restart folio-manager.service")
    machine.wait_for_unit("folio-manager.service", user="folio")
    user("timeout 30 bash -c 'until folio --json status >/dev/null 2>&1; do sleep 0.2; done'")


user_state = "/home/folio/.local/state/folio/deployments"
with subtest("completed activation publication is recovered without activation"):
    current = user_record(user_state + "/current.json")
    task_path = user_state + "/tasks/" + current["taskId"] + ".json"
    task = user_record(task_path)
    user("systemctl --user stop folio-manager.service")
    task.update(phase="verifying", effectPhase="activation-returned", recoveryRequired=True)
    write_fault(task_path, task)
    user("rm " + user_state + "/current.json")
    restart_user_manager()
    assert user_record(task_path)["recoveryAction"] == "completed-publication"
    assert user_record(user_state + "/current.json")["artifact"] == user_profile
    revision = user_record(user_state + "/revisions/" + current["planId"] + ".json")
    assert revision["configurationDigest"] == user_digest and revision["workerProtocol"] == 1
    assert folio("status")["data"]["health"] == "healthy"

with subtest("failed profile restoration stays visible and blocks apply"):
    task_id = "t-22222222222222222222222222222222"
    fault_path = user_state + "/tasks/" + task_id + ".json"
    task = user_record(task_path)
    task.update(id=task_id, phase="activating", effectPhase="profile-selected",
                beforeProfile=user_profile, afterProfile="@defaultGeneration@", recoveryRequired=True)
    user("systemctl --user stop folio-manager.service")
    write_fault(fault_path, task)
    user("nix-env --profile /home/folio/.local/state/nix/profiles/home-manager --set @defaultGeneration@")
    user("chmod 0500 /home/folio/.local/state/nix/profiles")
    restart_user_manager()
    assert user_record(fault_path)["recoveryRequired"] is True
    pending = folio("status")["data"]
    assert pending["health"] == "degraded" and task_id in pending["recovery"]
    denied = json.loads(user("if folio --json apply " + user_plan + "; then exit 1; fi"))
    assert denied["status"] == "conflict"
    assert "font=Maple Mono NF CN:size=18" in user("cat /home/folio/.config/foot/foot.ini")
    user("chmod 0700 /home/folio/.local/state/nix/profiles")
    restart_user_manager()
    task = user_record(fault_path)
    assert task["recoveryRequired"] is False and task["recoveryAction"] == "restored-profile"
    assert folio("status")["data"]["health"] == "healthy"
    assert user("readlink -f /home/folio/.local/state/nix/profiles/home-manager").strip() == user_profile


with subtest("offline root restore pairs desired data and closure and retains a failed restore barrier"):
    system_state = "/var/lib/folio/deployments"
    current = json.loads(machine.succeed("cat " + system_state + "/current.json"))
    metadata = json.loads(machine.succeed("cat " + current["artifact"] + "/folio-system.json"))
    bootstrap = metadata["bootstrap"]
    command = "folio-manager-maintain system " + bootstrap
    boot_id = machine.succeed("cat /proc/sys/kernel/random/boot_id").strip()
    machine.succeed(command + " snapshot paired-root > /tmp/paired-snapshot.json")
    user("timeout 30 bash -c 'until folio --json --system status >/dev/null 2>&1; do sleep 0.2; done'")
    desired = folio("--system config show")["data"]["configuration"]
    changed = json.loads(json.dumps(desired))
    changed["folio-environment:environment"]["preferences"]["font-size"] = 24
    write_fault("/tmp/changed-system.json", changed, True)
    folio("--system config import /tmp/changed-system.json")
    transaction = "/var/lib/folio/backups/repositories/paired-root/transaction.json"
    record = json.loads(machine.succeed("cat " + transaction))
    broken = dict(record)
    broken["oldArtifact"] = "/nix/store/00000000000000000000000000000000-folio-missing-closure"
    write_fault(transaction, broken, True)
    machine.fail(command + " restore paired-root")
    machine.succeed("test -f /var/lib/folio/schema-transaction.json")
    machine.fail("systemctl is-active --quiet folio-manager.service")
    offline = json.loads(machine.succeed("folio --json --system status"))
    assert offline["data"]["offline"] is True and offline["data"]["maintenance"]["paired-root"]["phase"] == "restoring"
    write_fault(transaction, record, True)
    machine.succeed(command + " restore paired-root > /tmp/paired-restore.json")
    user("timeout 30 bash -c 'until folio --json --system status >/dev/null 2>&1; do sleep 0.2; done'")
    restored = folio("--system config show")["data"]["configuration"]
    assert restored == desired
    assert machine.succeed("readlink -f /nix/var/nix/profiles/system").strip() == current["artifact"]
    assert machine.succeed("readlink -f /run/current-system").strip() == current["artifact"]
    assert machine.succeed("cat /proc/sys/kernel/random/boot_id").strip() == boot_id
    machine.succeed("test ! -e /var/lib/folio/schema-transaction.json")
    machine.succeed("test -L /var/lib/folio/backups/repositories/paired-root/artifact-root")
    revision = json.loads(machine.succeed("cat " + system_state + "/revisions/" + current["planId"] + ".json"))
    machine.succeed(command + " upgrade paired-upgrade " + revision["source"] + " > /tmp/paired-upgrade.json")
    user("timeout 30 bash -c 'until folio --json --system status >/dev/null 2>&1; do sleep 0.2; done'")
    assert folio("--system status")["data"]["health"] == "healthy"
    machine.succeed(command + " restore paired-upgrade > /tmp/paired-upgrade-restored.json")
    user("timeout 30 bash -c 'until folio --json --system status >/dev/null 2>&1; do sleep 0.2; done'")

with subtest("offline user restore retains the matching managed files and desired configuration"):
    current = user_record(user_state + "/current.json")
    metadata = user_record(current["artifact"] + "/folio-home.json")
    command = "folio-manager-maintain user " + metadata["bootstrap"]
    user(command + " snapshot paired-user > /tmp/paired-user-snapshot.json")
    user("timeout 30 bash -c 'until folio --json status >/dev/null 2>&1; do sleep 0.2; done'")
    desired = folio("config show")["data"]["configuration"]
    changed = json.loads(json.dumps(desired))
    changed["folio-environment:environment"]["preferences"]["font-size"] = 24
    save(changed)
    user(command + " restore paired-user > /tmp/paired-user-restore.json")
    user("timeout 30 bash -c 'until folio --json status >/dev/null 2>&1; do sleep 0.2; done'")
    assert folio("config show")["data"]["configuration"] == desired
    assert folio("status")["data"]["health"] == "healthy"
    assert "font=Maple Mono NF CN:size=18" in user("cat /home/folio/.config/foot/foot.ini")

with subtest("root recovery restores only a recorded profile while the guest stays running"):
    system_state = "/var/lib/folio/deployments"
    current = json.loads(machine.succeed("cat " + system_state + "/current.json"))
    original = json.loads(machine.succeed("cat " + system_state + "/tasks/" + current["taskId"] + ".json"))
    task_id = "t-33333333333333333333333333333333"
    fault_path = system_state + "/tasks/" + task_id + ".json"
    task = dict(original)
    task.update(id=task_id, phase="activating", effectPhase="profile-selected",
                beforeProfile=current["artifact"], afterProfile=original["beforeProfile"], recoveryRequired=True)
    boot_id = machine.succeed("cat /proc/sys/kernel/random/boot_id").strip()
    machine.succeed("systemctl stop folio-manager.service")
    write_fault(fault_path, task, True)
    machine.succeed("nix-env --profile /nix/var/nix/profiles/system --set " + task["afterProfile"])
    machine.succeed("systemctl start folio-manager.service folio-system.service")
    machine.wait_for_unit("folio-manager.service")
    user("timeout 30 bash -c 'until folio --json --system status >/dev/null 2>&1; do sleep 0.2; done'")
    observed = json.loads(machine.succeed("cat " + fault_path))
    assert observed["recoveryRequired"] is False and observed["recoveryAction"] == "restored-profile"
    assert machine.succeed("readlink -f /nix/var/nix/profiles/system").strip() == current["artifact"]
    assert machine.succeed("readlink -f /run/current-system").strip() == current["artifact"]
    assert machine.succeed("cat /proc/sys/kernel/random/boot_id").strip() == boot_id
    assert machine.succeed("readlink -f /etc/localtime").strip().endswith("/zoneinfo/UTC")
    assert user("readlink -f /home/folio/.local/state/nix/profiles/home-manager").strip() == user_profile

with subtest("module-owned schema migration activates a matching closure and rollback discards failed later desired data"):
    current = user_record(user_state + "/current.json")
    retained_id = current["planId"]
    retained_path = user_state + "/revisions/" + retained_id + ".json"
    retained = user_record(retained_path)
    metadata = user_record(current["artifact"] + "/folio-home.json")
    command = "folio-manager-maintain user " + metadata["bootstrap"]
    user(command + " upgrade opacity-units @migrationSource@ > /tmp/schema-upgrade.json")
    assert folio("status")["data"]["health"] == "healthy"
    upgraded = folio("config show")["data"]["configuration"]
    terminal = next(item for item in upgraded["folio-environment:environment"]["modules"] if item["name"] == "terminal")
    foot = terminal["folio-terminal:terminal"]["foot"]
    assert float(foot["opacity"]) == 1 and "opacity-percent" not in foot
    assert "alpha=1" in user("cat /home/folio/.config/foot/foot.ini")
    assert folio("status")["data"]["applied"]["revisionId"] == "maintenance-opacity-units"
    failed_desired = json.loads(json.dumps(upgraded))
    failed_desired["folio-environment:environment"]["preferences"]["font-size"] = 24
    save(failed_desired)
    unsupported = dict(retained)
    unsupported["workerProtocol"] = 0
    write_fault(retained_path, unsupported)
    rejected = json.loads(user("set +e; folio --json rollback " + retained_id + " >/tmp/unsupported.json; code=$?; test $code = 3 || exit 1; cat /tmp/unsupported.json"))
    assert rejected["status"] == "unavailable"
    assert folio("config show")["data"]["configuration"] == failed_desired
    assert folio("rollback " + retained_id + " --rebuild")["status"] == "success"
    write_fault(retained_path, retained)
    restored = folio("config show")["data"]["configuration"]
    assert restored == retained["configuration"]
    assert folio("status")["data"]["health"] == "healthy"
    assert "font=Maple Mono NF CN:size=18" in user("cat /home/folio/.config/foot/foot.ini")
    user_digest = folio("config show")["data"]["digest"]
    user_profile = user("readlink -f /home/folio/.local/state/nix/profiles/home-manager").strip()
    published = user_record(user_state + "/current.json")
    revision = user_record(user_state + "/revisions/" + published["revisionId"] + ".json")
    assert revision["workerProtocol"] == 1 and revision["models"] == retained["models"]
    orphan = folio("--user plan --source /home/folio/source")["data"]["planId"]
    preview = folio("cleanup")["data"]
    assert orphan in preview["plans"] and retained_id not in preview["plans"]
    assert folio("cleanup --apply")["status"] == "success"
    user("test ! -e " + user_state + "/plans/" + orphan + ".json")
    assert folio("status")["data"]["health"] == "healthy"
