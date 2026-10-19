import datetime
import json
import shlex


def user(command, account="folio", timeout=600):
    environment = f"HOME=/home/{account} USER={account} XDG_RUNTIME_DIR=/run/user/1000"
    return machine.succeed(
        "runuser -u " + account + " -- env " + environment + " bash -c "
        + shlex.quote("set -euo pipefail; " + command),
        timeout=datetime.timedelta(seconds=timeout),
    )


def folio(arguments):
    return json.loads(user("@cli@ --json --system " + arguments))


machine.start(allow_reboot=True)
machine.wait_for_unit("multi-user.target")
machine.wait_for_unit("folio-manager.service")
machine.succeed("test -d /sys/firmware/efi")

with subtest("real prior system model upgrades with its paired closure"):
    machine.succeed("@runtime@ system @oldBootstrap@ upgrade network-policy @upgraded@", timeout=datetime.timedelta(seconds=600))
    assert folio("status")["data"]["health"] == "healthy"
    model_list = machine.succeed("folio-repository system ctl --list")
    assert "folio-system" in model_list and "2026-10-19" in model_list

with subtest("authorized system build applies policy and publishes capabilities"):
    assert folio("config import @desired@ ")["status"] == "success"
    result = folio("plan --source @selected@")
    assert result["status"] == "success", result
    plan = result["data"]["planId"]
    assert folio("build " + plan)["status"] == "success"
    assert folio("apply " + plan)["status"] == "success"
    machine.wait_for_unit("folio-network.service")
    machine.wait_for_unit("NetworkManager.service")
    machine.wait_for_unit("folio-mihomo.service")
    machine.wait_for_unit("sshd.service")
    assert folio("status")["data"]["health"] == "healthy"
    assert machine.succeed("readlink -f /etc/localtime").strip().endswith("/zoneinfo/UTC")
    descriptor = json.loads(machine.succeed("cat /run/folio/public/system-descriptor.json"))
    assert descriptor["capabilities"]["network-provisioned"] is True
    machine.succeed("grep -q zram0 /proc/swaps; grep -q '\\[zstd\\]' /sys/block/zram0/comp_algorithm")
    machine.succeed("systemd-analyze cat-config systemd/journald.conf | grep 'SystemMaxUse=256M'")
    observed = folio("network status")
    assert observed["status"] == "success", observed
    assert observed["data"]["network"]["available"] is True
    assert observed["data"]["proxy"]["available"] is True
    assert observed["data"]["physicalAcceptance"] == "unverified"

with subtest("network-owned connection operations have real effects and bounded failures"):
    connection = "22222222-2222-4222-8222-222222222222"
    machine.succeed("nmcli connection add type ethernet ifname eth1 con-name folio-isolated connection.uuid " + connection
                    + " connection.autoconnect no ipv4.method manual ipv4.addresses 192.0.2.10/24 ipv4.never-default yes ipv6.method disabled")
    assert folio("network connect " + connection + " eth1")["status"] == "success"
    addresses = json.loads(machine.succeed("ip -j address show dev eth1"))
    assert any(entry.get("local") == "192.0.2.10" for entry in addresses[0]["addr_info"])
    missing = json.loads(user("code=0; @cli@ --json --system network connect 00000000-0000-4000-8000-000000000000 eth1 || code=$?; test $code = 3"))
    assert missing["status"] == "unavailable"
    assert "192.0.2.10" in machine.succeed("ip -4 address show dev eth1")
    denied = json.loads(user("code=0; @cli@ --json --system network disconnect eth1 || code=$?; test $code != 0", account="visitor"))
    assert denied["status"] != "success"
    invalid = json.loads(user("code=0; @cli@ --json --system network disconnect ../eth1 || code=$?; test $code = 2"))
    assert invalid["status"] == "invalid"
    unsupported = json.loads(user("code=0; @cli@ --json network disconnect eth1 || code=$?; test $code = 2"))
    assert unsupported["status"] == "invalid"
    assert "192.0.2.10" in machine.succeed("ip -4 address show dev eth1")
    assert folio("network disconnect eth1")["status"] == "success"
    assert "192.0.2.10" not in machine.succeed("ip -4 address show dev eth1")

with subtest("actual DNS and HTTP traffic use the local proxy and its live mode"):
    machine.succeed("mkdir -p /tmp/folio-http; printf folio-isolated-origin >/tmp/folio-http/index.html")
    machine.succeed("systemd-run --collect --unit=folio-test-origin python3 -m http.server 18080 --bind 0.0.0.0 --directory /tmp/folio-http")
    machine.succeed("systemd-run --collect --unit=folio-test-dns dnsmasq --keep-in-foreground --port=53 --listen-address=127.0.0.1 --bind-interfaces --no-resolv --no-hosts --address=/folio.test/127.0.0.1")
    machine.wait_for_open_port(53)
    machine.wait_for_open_port(18080)
    machine.wait_until_succeeds("grep 'nameserver 127.0.0.1' /etc/resolv.conf; getent ahostsv4 folio.test | grep 127.0.0.1")
    selected = folio("network proxy-select DIRECT")
    assert selected["status"] == "success" and selected["data"]["proxy"]["selectedNode"] == "DIRECT", selected
    assert folio("network proxy-mode direct")["data"]["proxy"]["mode"] == "direct"
    desired = folio("config show")["data"]["configuration"]["folio-environment:environment"]
    assert next(module for module in desired["modules"] if module["name"] == "network")["folio-network:network"]["proxy"]["mode"] == "rule"
    output = machine.succeed("curl --fail --silent --show-error --max-time 5 --noproxy '' --proxy socks5h://127.0.0.1:7890 http://folio.test:18080/")
    assert output == "folio-isolated-origin", output
    missing = json.loads(user("code=0; @cli@ --json --system network proxy-select missing-fixture-node || code=$?; test $code = 3"))
    assert missing["status"] == "unavailable"
    assert folio("network status")["data"]["proxy"]["selectedNode"] == "DIRECT"
    machine.succeed("systemctl stop folio-mihomo")
    unavailable = json.loads(user("code=0; @cli@ --json --system network proxy-mode rule || code=$?; test $code = 3"))
    assert unavailable["status"] == "unavailable"
    assert folio("network status")["data"]["proxy"]["available"] is False
    machine.succeed("systemctl start folio-mihomo")
    machine.wait_for_unit("folio-mihomo.service")

with subtest("isolated inbound endpoint proves SSH policy and firewall behavior"):
    # Ephemeral keys are generated only inside this disposable guest at runtime.
    machine.succeed("ssh-keygen -q -t ed25519 -N '' -f /tmp/folio-fixture-key; install -d -o folio -g users -m 0700 /home/folio/.ssh; cat /tmp/folio-fixture-key.pub >/home/folio/.ssh/authorized_keys; chown folio:users /home/folio/.ssh/authorized_keys; chmod 0600 /home/folio/.ssh/authorized_keys")
    machine.succeed("ip netns add folio-peer; ip link add folio-test0 type veth peer name folio-peer0; ip link set folio-peer0 netns folio-peer; ip address add 198.51.100.1/24 dev folio-test0; ip link set folio-test0 up; ip -n folio-peer address add 198.51.100.2/24 dev folio-peer0; ip -n folio-peer link set folio-peer0 up; ip -n folio-peer link set lo up")
    output = machine.succeed("ip netns exec folio-peer ssh -i /tmp/folio-fixture-key -p 2222 -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/folio-fixture-known-hosts folio@198.51.100.1 printf ssh-fixture-ok")
    assert "ssh-fixture-ok" in output, output
    machine.fail("ip netns exec folio-peer curl --noproxy '*' --connect-timeout 2 --max-time 3 --silent http://198.51.100.1:18080/")
    policy = machine.succeed("sshd -T -f /etc/ssh/sshd_config | tee /tmp/folio-ssh-policy.txt")
    for setting in ["passwordauthentication no", "kbdinteractiveauthentication no", "permitrootlogin no"]:
        assert setting in policy.lower().splitlines(), policy
    machine.copy_from_machine("/tmp/folio-ssh-policy.txt")
    assert folio("status")["data"]["health"] == "healthy"
    user("@cli@ --json --system network status >/home/folio/network-status.json")
    machine.copy_from_machine("/home/folio/network-status.json")
    machine.succeed("ip netns delete folio-peer")
