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
