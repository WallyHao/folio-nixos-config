# ruff: noqa: F821 -- machine/subtest are injected by the NixOS test driver.
import datetime
import json
import shlex


def user(command, timeout=90):
    return machine.succeed(
        "runuser -u folio -- env HOME=/home/folio XDG_RUNTIME_DIR=/run/user/1000 "
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus bash -c "
        + shlex.quote(command),
        timeout=datetime.timedelta(seconds=timeout),
    )


def native(program, request, code=0):
    # Disposable credentials are supplied to the program via a private file/stdin,
    # never as program arguments. No real host connection is used.
    machine.succeed("install -o folio -m 0600 /dev/null /run/user/1000/fixture-request")
    machine.succeed(
        "printf %s "
        + shlex.quote(json.dumps(request))
        + " >/run/user/1000/fixture-request"
    )
    output = user(
        "code=0; "
        + program
        + " </run/user/1000/fixture-request || code=$?; test $code = "
        + str(code)
    )
    machine.succeed("rm /run/user/1000/fixture-request")
    result = json.loads(output)
    if request.get("password"):
        assert request["password"] not in output, "Credential leaked in a backend reply"
    assert result["status"] == {0: "success", 2: "invalid", 3: "unavailable"}[code], (
        result
    )
    return result["data"]


def rpc(action, **fields):
    root = (
        "folio-network:execute"
        if action in ("status", "proxy-mode")
        else "folio-network-panel:control"
    )
    request = {root: {"action": action, **fields}}
    machine.succeed(
        "printf %s "
        + shlex.quote(json.dumps(request))
        + " >/tmp/panel-rpc.json; chmod 0644 /tmp/panel-rpc.json"
    )
    result = json.loads(
        user(
            "folio-repository system cfg --rpc=/tmp/panel-rpc.json --format json --timeout 30"
        )
    )
    record = next(iter(result.values()))
    assert "result-json" in record, record
    return json.loads(record["result-json"])


machine.start()
machine.wait_for_unit("multi-user.target")
machine.wait_for_unit("NetworkManager.service")
machine.succeed("systemctl start polkit.service wpa_supplicant.service")
machine.wait_until_succeeds(
    "nmcli -t -f DEVICE,STATE device status | grep '^wlan0:disconnected$'"
)
machine.wait_for_unit("folio-network.service")
machine.wait_for_unit("folio-mihomo.service")
machine.wait_until_succeeds(
    "test -d /sys/class/net/wlan0; test -d /sys/class/net/wlan1"
)
machine.succeed("ip link set wlan1 up")
machine.succeed("ip address add 192.168.70.1/24 dev wlan1")
machine.succeed(
    "systemd-run --unit=folio-test-dhcp dnsmasq --keep-in-foreground --interface=wlan1 --bind-interfaces --port=0 --dhcp-range=192.168.70.10,192.168.70.20,255.255.255.0,1h"
)
machine.succeed(
    "cat >/tmp/hostapd.conf <<'EOF'\ninterface=wlan1\ndriver=nl80211\nssid=FolioFixture\nhw_mode=g\nchannel=1\nwpa=2\nwpa_key_mgmt=WPA-PSK\nrsn_pairwise=CCMP\nwpa_passphrase=fixture-network-password\nEOF"
)
machine.succeed("systemd-run --unit=folio-test-ap hostapd /tmp/hostapd.conf")
machine.wait_until_succeeds("journalctl -u folio-test-ap --no-pager | grep AP-ENABLED")
machine.wait_until_succeeds(
    "nmcli -t -f SSID device wifi list ifname wlan0 --rescan yes | grep -Fx FolioFixture",
    timeout=datetime.timedelta(seconds=60),
)

with subtest("native Wi-Fi scan, new credential connection, saved profile and forget"):
    observed = native("@wifi@", {"action": "scan", "interface": "wlan0"})
    adapter = next(a for a in observed["adapters"] if a["interface"] == "wlan0")
    assert any(a["ssid"] == "FolioFixture" for a in adapter["networks"]), observed
    ap = next(a for a in adapter["networks"] if a["ssid"] == "FolioFixture")
    observed = native(
        "@wifi@",
        {
            "action": "connect",
            "interface": "wlan0",
            "ap": ap["path"],
            "password": "fixture-network-password",
        },
    )
    adapter = next(a for a in observed["adapters"] if a["interface"] == "wlan0")
    assert any(a["active"] for a in adapter["networks"]), observed
    profile = next(
        p["uuid"] for p in adapter["profiles"] if p["ssid"] == "FolioFixture"
    )
    assert "folio" in user(
        "nmcli -g connection.permissions connection show " + shlex.quote(profile)
    )
    machine.succeed(
        "find /etc/NetworkManager/system-connections -type f -exec stat -c '%U:%G:%a' {} + | grep -q '^root:root:600$'"
    )
    machine.succeed(
        "test -z \"$(find /var/lib/folio/sysrepo /run/folio/network -type f -exec grep -l -- 'fixture-network-password' {} +)\""
    )
    native("@wifi@", {"action": "disconnect", "interface": "wlan0"})
    native("@wifi@", {"action": "connect", "interface": "wlan0", "uuid": profile})
    native("@wifi@", {"action": "disconnect", "interface": "wlan0"})
    observed = native(
        "@wifi@", {"action": "forget", "interface": "wlan0", "uuid": profile}
    )
    assert all(
        p["uuid"] != profile for a in observed["adapters"] for p in a["profiles"]
    )
    assert native("@wifi@", {"action": "radio", "enabled": False})["enabled"] is False
    assert native("@wifi@", {"action": "radio", "enabled": True})["enabled"] is True

with subtest("wrong password fails, then hidden personal network connects"):
    machine.wait_until_succeeds(
        "nmcli -t -f SSID device wifi list ifname wlan0 --rescan yes | grep -Fx FolioFixture",
        timeout=datetime.timedelta(seconds=60),
    )
    observed = native("@wifi@", {"action": "status"})
    adapter = next(a for a in observed["adapters"] if a["interface"] == "wlan0")
    ap = next(a for a in adapter["networks"] if a["ssid"] == "FolioFixture")
    native(
        "@wifi@",
        {
            "action": "connect",
            "interface": "wlan0",
            "ap": ap["path"],
            "password": "incorrect-fixture-password",
        },
        code=3,
    )
    observed = native("@wifi@", {"action": "status"})
    adapter = next(a for a in observed["adapters"] if a["interface"] == "wlan0")
    for profile in adapter["profiles"]:
        native(
            "@wifi@",
            {"action": "forget", "interface": "wlan0", "uuid": profile["uuid"]},
        )
    machine.succeed("systemctl stop folio-test-ap")
    machine.succeed(
        "sed -i 's/ssid=FolioFixture/ssid=FolioHidden/; $a ignore_broadcast_ssid=1' /tmp/hostapd.conf"
    )
    machine.succeed("systemd-run --unit=folio-test-ap hostapd /tmp/hostapd.conf")
    observed = native(
        "@wifi@",
        {
            "action": "connect",
            "interface": "wlan0",
            "hidden": True,
            "ssid": "FolioHidden",
            "security": "WPA Personal",
            "password": "fixture-network-password",
        },
    )
    adapter = next(a for a in observed["adapters"] if a["interface"] == "wlan0")
    assert adapter["addresses"], observed
    profile = next(p["uuid"] for p in adapter["profiles"] if p["ssid"] == "FolioHidden")
    native("@wifi@", {"action": "disconnect", "interface": "wlan0"})
    native("@wifi@", {"action": "forget", "interface": "wlan0", "uuid": profile})

with subtest("credentials remain outside Folio exports, service logs and frontend"):
    user(
        "folio-repository system cfg --export --format json >/run/user/1000/fixture-export.json"
    )
    machine.succeed(
        "journalctl -u NetworkManager -u wpa_supplicant -u folio-network --no-pager -o cat >/tmp/panel-service-journal"
    )
    machine.succeed(
        'test -z "$(find /var/lib/folio/sysrepo /run/folio/network @panel@/lib '
        "/run/user/1000/fixture-export.json /tmp/panel-service-journal -type f "
        "-exec grep -l -e 'fixture-network-password' -e 'incorrect-fixture-password' {} +)\""
    )

with subtest("real proxy inventory and authorized selection, bounded delay failure"):
    # Exercise the installed async transport too, not only fixture RPC helpers.
    script = "import asyncio,json; from folio_panel.client import Client; print(json.dumps(asyncio.run(Client().proxy('proxy-groups'))))"
    assert json.loads(
        user("PYTHONPATH=@panel@/lib @python@ -c " + shlex.quote(script))
    )["groups"]
    for mode in ("direct", "global", "rule"):
        assert rpc("proxy-mode", mode=mode)["status"] == "success"
        assert rpc("status")["data"]["proxy"]["mode"] == mode
    groups = rpc("proxy-groups")
    assert groups["status"] == "success", groups
    group = next(g for g in groups["data"]["groups"] if g["name"] == "PROXY")
    assert "DIRECT" in group["nodes"] and "REJECT" in group["nodes"]
    assert (
        rpc("proxy-group-select", group="PROXY", node="REJECT")["status"] == "success"
    )
    assert (
        next(g for g in rpc("proxy-groups")["data"]["groups"] if g["name"] == "PROXY")[
            "selected"
        ]
        == "REJECT"
    )
    assert (
        rpc("proxy-group-select", group="PROXY", node="missing")["status"]
        == "unavailable"
    )
    machine.succeed("iptables -A OUTPUT -p tcp --dport 443 -j REJECT")
    assert rpc("proxy-delay", node="DIRECT")["status"] == "unavailable"
    denied = machine.execute(
        "runuser -u nobody -- folio-repository system cfg --rpc=/tmp/panel-rpc.json --format json"
    )[0]
    assert denied != 0
    machine.succeed("systemctl stop folio-mihomo")
    assert rpc("proxy-groups")["status"] == "unavailable"

with subtest("real audio output, volume, mute and unavailable backlight"):
    user("systemctl --user start pipewire pipewire-pulse wireplumber")
    machine.wait_until_succeeds(
        "runuser -u folio -- env XDG_RUNTIME_DIR=/run/user/1000 pactl info"
    )
    user("pactl load-module module-null-sink sink_name=folio_fixture")
    user("pactl load-module module-null-sink sink_name=folio_second")
    native("@devices@", {"action": "output", "name": "folio_fixture"})
    observed = native("@devices@", {"action": "volume", "level": 47})
    assert observed["audio"]["default"] == "folio_fixture"
    assert (
        next(s for s in observed["audio"]["sinks"] if s["name"] == "folio_fixture")[
            "volume"
        ]
        == 47
    )
    observed = native("@devices@", {"action": "mute"})
    assert next(s for s in observed["audio"]["sinks"] if s["name"] == "folio_fixture")[
        "mute"
    ]
    assert observed["backlights"] == []
    native("@devices@", {"action": "output", "name": "folio_second"})
    user("pactl unload-module module-null-sink")
    remaining = native("@devices@", {"action": "status"})["audio"]["sinks"]
    assert all(s["name"] not in ("folio_fixture", "folio_second") for s in remaining)
    native("@devices@", {"action": "output", "name": "folio_second"}, code=2)
    information = native("@devices@", {"action": "information"})
    assert information["memoryKiB"] > 0 and information["cpu"] != "Unavailable"
    assert "without sudo" in machine.fail("@panel@/bin/folio panel 2>&1")
    user("@panel@/bin/folio --version >/home/folio/panel-version.txt")
    machine.copy_from_machine("/home/folio/panel-version.txt")
