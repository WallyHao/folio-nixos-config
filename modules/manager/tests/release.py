# One representative interrupted publication from recovery.py, using the actual
# completed deployment record and manager recovery; no alternate activator.
with subtest("interrupted publication recovers the recorded retained deployment"):
    state = "/home/folio/.local/state/folio/deployments"
    current = json.loads(user("cat " + state + "/current.json"))
    task_path = state + "/tasks/" + current["taskId"] + ".json"
    task = json.loads(user("cat " + task_path))
    user("systemctl --user stop folio-manager.service")
    task.update(phase="verifying", effectPhase="activation-returned", recoveryRequired=True)
    user("printf %s " + shlex.quote(json.dumps(task)) + " >" + task_path)
    user("rm " + state + "/current.json; systemctl --user start folio-manager.service")
    machine.wait_for_unit("folio-manager.service", user="folio")
    user("timeout 30 bash -c 'until folio --json status >/dev/null 2>&1; do sleep 0.2; done'")
    recovered = json.loads(user("cat " + task_path))
    assert recovered["recoveryAction"] == "completed-publication", recovered
    assert json.loads(user("cat " + state + "/current.json"))["artifact"] == user_profile
    assert folio("status")["data"]["health"] == "healthy"

with subtest("retained rollback restores desired data, files and the rooted closure"):
    changed = folio("config show")["data"]["configuration"]
    changed["folio-environment:environment"]["preferences"]["font-size"] = 24
    save(changed)
    assert folio("status")["data"]["health"] != "healthy"
    later = folio("--user plan --source /home/folio/source")["data"]["planId"]
    assert folio("build " + later)["status"] == "success"
    assert folio("apply " + later)["status"] == "success"
    assert (
        user("readlink -f /home/folio/.local/state/nix/profiles/home-manager").strip()
        != user_profile
    )
    assert "font=Maple Mono NF CN:size=24" in user("cat /home/folio/.config/foot/foot.ini")
    assert folio("rollback " + user_plan)["status"] == "success"
    assert folio("config show")["data"]["digest"] == user_digest
    assert (
        user("readlink -f /home/folio/.local/state/nix/profiles/home-manager").strip()
        == user_profile
    )
    assert "font=Maple Mono NF CN:size=18" in user("cat /home/folio/.config/foot/foot.ini")
    assert folio("status")["data"]["health"] == "healthy"
    user(
        "find "
        + state
        + "/roots -type l -exec readlink -f {} + | grep -Fx "
        + shlex.quote(user_profile)
    )

with subtest("current network and developer contributions coexist in the deployed system"):
    observed = folio("--system network status")
    assert observed["status"] == "success", observed
    user(
        "/home/folio/.nix-profile/bin/git --version; /home/folio/.nix-profile/bin/codex --version; /home/folio/.nix-profile/bin/nvim --version"
    )
    user(
        "setsid --wait /home/folio/.nix-profile/bin/zsh -ic 'print -r -- folio-release-shell' </dev/null"
    )
    # The shared default deliberately leaves SSH disabled. Stage 08 owns the
    # enabled/key-authentication/firewall gate; observe the deployed default here.
    machine.fail("systemctl is-active --quiet sshd.service")
    machine.succeed("systemctl show sshd.service -p LoadState -p ActiveState >/tmp/release-ssh.txt")
    machine.copy_from_machine("/tmp/release-ssh.txt")
