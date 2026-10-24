"""Network failover, region restriction, confirmation and generation safety."""

import contextlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch, mock_open


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


root = Path(os.environ["FOLIO_WORKSPACE_SOURCE"])
health = load("folio_workspace_health", root / "runtime/health.py")
load("folio_proxy", os.environ["FOLIO_PROXY_SOURCE"])
network = load("network_prepare", os.environ["FOLIO_NETWORK_PREPARE"])
client = load("workspace_client", root / "cli/prepare.py")
system = load("workspace_system", root / "runtime/system.py")


class Networking(unittest.TestCase):
    def setUp(self):
        self.output = patch.object(network, "event").start()
        self.addCleanup(patch.stopall)

    def test_only_country_labels_and_actual_nodes(self):
        for name in (
            "香港 01",
            "美國-02",
            "🇺🇸 Seattle",
            "HK-3",
            "US_02",
            "Hong Kong",
            "United States",
        ):
            self.assertTrue(network.eligible(name), name)
        for name in ("Australia", "Russia", "JP Tokyo", "BUSINESS", "🇯🇵 日本"):
            self.assertFalse(network.eligible(name), name)
        inventory = {"proxies": {"HK-Auto": {"type": "URLTest"}, "US-DIRECT": {"type": "Direct"}}}
        providers = {"providers": {"p": {"proxies": [{"name": "HK-1", "type": "Shadowsocks"}]}}}
        self.assertEqual(network.candidates(inventory, providers), ["HK-1"])

    def test_saved_profiles_order_and_never_connected_exclusion(self):
        with patch.object(
            network,
            "nm",
            return_value="a:802-11-wireless:10\nb:802-11-wireless:30\nc:802-11-wireless:0\nd:802-3-ethernet:40",
        ):
            self.assertEqual(network.saved_wifi(), ["b", "a"])

    def test_current_then_saved_until_a_transfer_succeeds(self):
        with (
            patch.object(network, "nm") as nm,
            patch.object(network, "run"),
            patch.object(
                network,
                "active_wifi",
                side_effect=[iter([("current", "wlan0")]), iter([("good", "wlan0")])],
            ),
            patch.object(network, "saved_wifi", return_value=["current", "bad", "good"]),
            patch.object(network, "probe", side_effect=[False, True]),
        ):

            def operate(*args):
                if args == ("connection", "up", "uuid", "bad"):
                    raise network.Failure("unavailable")
                return "Saved network"

            nm.side_effect = operate
            network.prepare_wifi()
            attempts = [
                call.args for call in nm.call_args_list if call.args[:2] == ("connection", "up")
            ]
            self.assertEqual(
                attempts,
                [("connection", "up", "uuid", "bad"), ("connection", "up", "uuid", "good")],
            )

    def test_exhaustion_is_an_error(self):
        with (
            patch.object(network, "nm"),
            patch.object(network, "run"),
            patch.object(network, "active_wifi", return_value=iter([])),
            patch.object(network, "saved_wifi", return_value=[]),
        ):
            with self.assertRaisesRegex(network.Failure, "All saved Wi-Fi"):
                network.prepare_wifi()

    def test_original_vpn_is_restarted_when_wifi_fails(self):
        with (
            patch.object(network, "run", return_value=Mock(returncode=0)) as run,
            patch.object(network, "prepare_wifi", side_effect=network.Failure("offline")),
            patch.object(network, "prepare_proxy") as proxy,
        ):
            with self.assertRaises(network.Failure):
                network.prepare()
            run.assert_any_call("systemctl", "start", "folio-mihomo.service", timeout=35)
            proxy.assert_not_called()

    def test_portal_redirect_and_slow_transfer_are_rejected(self):
        responses = [
            Mock(returncode=0, stdout="302 2000 90000 1"),
            Mock(returncode=0, stdout="200 2000 100 8"),
        ]
        with patch.object(network, "run", side_effect=responses):
            self.assertFalse(network.probe("wlan0"))

    def test_speed_probe_binds_wifi_and_bypasses_proxy(self):
        with patch.object(
            network, "run", return_value=Mock(returncode=0, stdout="200 20000 32000 0.6")
        ) as run:
            self.assertTrue(network.probe("wlan0"))
            args = run.call_args.args
            self.assertEqual(args[args.index("--interface") + 1], "wlan0")
            self.assertEqual(args[args.index("--noproxy") + 1], "*")

    def inventory(self):
        return {
            "proxies": {
                "GLOBAL": {"type": "Selector", "all": ["Private", "JP-1"]},
                "Private": {"type": "Selector", "all": ["HK-1", "US-2", "JP-1", "GLOBAL"]},
                "HK-1": {"type": "Shadowsocks"},
                "US-2": {"type": "Vmess"},
                "JP-1": {"type": "Shadowsocks"},
            }
        }

    def test_fastest_allowed_node_is_pinned_through_private_groups(self):
        writes, selected = [], {}

        def controller(method, path, data=None):
            if method != "GET":
                writes.append((method, path, data))
                if method == "PUT":
                    selected[path] = data["name"]
                return {}
            if path == "/proxies":
                return self.inventory()
            if path == "/providers/proxies":
                return {"providers": {}}
            if path == "/configs":
                return {"mode": "global", "tun": {"enable": True, "auto-route": True}}
            return {"now": selected[path]}

        with (
            patch.object(network, "run", return_value=Mock(returncode=0, stdout="204")),
            patch.object(network, "controller", side_effect=controller),
            patch.object(network, "delay", side_effect=lambda name: {"HK-1": 80, "US-2": 30}[name]),
        ):
            network.prepare_proxy()
        self.assertEqual(
            writes[:2],
            [
                ("PUT", "/proxies/Private", {"name": "US-2"}),
                ("PUT", "/proxies/GLOBAL", {"name": "Private"}),
            ],
        )
        self.assertEqual(writes[2][2]["mode"], "global")

    def test_all_nodes_timeout_without_selecting_anything(self):
        def controller(method, path, data=None):
            self.assertEqual(method, "GET")
            return self.inventory() if path == "/proxies" else {"providers": {}}

        with (
            patch.object(network, "run"),
            patch.object(network, "controller", side_effect=controller),
            patch.object(network, "delay", return_value=None),
        ):
            with self.assertRaisesRegex(network.Failure, "All Hong Kong"):
                network.prepare_proxy()

    def test_configured_vpn_with_failed_final_https_is_an_error(self):
        def controller(method, path, data=None):
            if path == "/proxies":
                return {
                    "proxies": {
                        "GLOBAL": {"type": "Selector", "all": ["HK-1"]},
                        "HK-1": {"type": "Shadowsocks"},
                    }
                }
            if path == "/configs":
                return {"mode": "global", "tun": {"enable": True, "auto-route": True}}
            if path == "/proxies/GLOBAL":
                return {"now": "HK-1"}
            return {"providers": {}}

        with (
            patch.object(network, "run", return_value=Mock(returncode=28, stdout="000")),
            patch.object(network, "controller", side_effect=controller),
            patch.object(network, "delay", return_value=20),
        ):
            with self.assertRaisesRegex(network.Failure, "final HTTPS"):
                network.prepare_proxy()

    def test_automatic_groups_cannot_pin_a_region(self):
        inventory = {
            "proxies": {
                "GLOBAL": {"type": "Selector", "all": ["HK-Auto"]},
                "HK-Auto": {"type": "URLTest", "all": ["HK-1", "JP-1"]},
            }
        }
        self.assertIsNone(network.selection_path(inventory, "HK-1"))


class Confirmation(unittest.TestCase):
    def setUp(self):
        self.disk = patch.object(
            client,
            "privileged_disk_check",
            return_value=health.report("Storage and mounts", [], cleanup_safe=True),
        ).start()
        self.services = patch.object(
            client, "service_check", return_value=health.report("Service health", [], failed=[])
        ).start()
        self.clock = patch.object(
            client,
            "time_check",
            return_value=health.report(
                "Time synchronization", [], synchronized=True, ntp_enabled=True
            ),
        ).start()
        self.connectivity = patch.object(
            client,
            "connectivity_check",
            return_value=health.report("DNS and service connectivity", []),
        ).start()
        self.addCleanup(patch.stopall)

    def execute(self, answer=None, interactive=True, network_code=0):
        stdin = Mock(isatty=lambda: interactive)
        with (
            patch.object(client.sys, "stdin", stdin),
            patch("builtins.input", return_value=answer) as prompt,
            patch.object(
                client,
                "backend",
                side_effect=lambda action, _: network_code if action == "network" else 0,
            ) as backend,
        ):
            result = client.session(Mock())
            return result, [call.args[0] for call in backend.call_args_list], prompt.call_count

    def test_empty_no_and_unrecognized_answers_do_not_clean(self):
        for answer in ("", "n", "no", "true", "anything"):
            self.assertEqual(self.execute(answer)[1], ["network"])

    def test_explicit_yes_runs_cleanup_after_network(self):
        for answer in ("y", "yes", " YES "):
            self.assertEqual(self.execute(answer)[:2], (0, ["network", "cleanup"]))

    def test_pipe_cannot_approve_cleanup(self):
        self.assertEqual(self.execute("yes", interactive=False), (0, ["network"], 0))

    def test_network_error_never_prompts_or_cleans(self):
        self.assertEqual(self.execute("yes", network_code=1), (1, ["network"], 0))

    def test_boot_runs_once_but_manual_retry_remains_available(self):
        with (
            tempfile.TemporaryDirectory() as runtime,
            patch.dict(os.environ, {"XDG_RUNTIME_DIR": runtime}),
            patch.object(client, "session", return_value=0) as session,
            contextlib.redirect_stdout(io.StringIO()),
        ):
            with patch.object(sys, "argv", ["folio-prepare", "--boot"]):
                self.assertEqual(client.main(), 0)
                self.assertEqual(client.main(), 0)
            self.assertEqual(session.call_count, 1)
            with patch.object(sys, "argv", ["folio-prepare"]):
                self.assertEqual(client.main(), 0)
            self.assertEqual(session.call_count, 2)

    def test_colors_and_unsafe_terminal_sequences(self):
        output = io.StringIO()
        output.isatty = lambda: True
        with patch.object(sys, "stdout", output), patch.dict(os.environ, {"TERM": "xterm"}):
            with patch.dict(os.environ):
                os.environ.pop("NO_COLOR", None)
                client.Console().say("Saved SSID\033[2J\nsecond line", "success")
            self.assertIn("\033[1;32m", output.getvalue())
            self.assertNotIn("\033[2J", output.getvalue())
            output.seek(0)
            output.truncate(0)
            with patch.dict(os.environ, {"NO_COLOR": "1"}):
                client.Console().say("Ready", "success")
            self.assertNotIn("\033", output.getvalue())

    def test_json_request_does_not_initialize_network(self):
        with (
            patch.dict(os.environ, {"FOLIO_JSON": "true"}),
            patch.object(client, "session") as session,
            contextlib.redirect_stdout(io.StringIO()),
        ):
            self.assertEqual(client.main(), 2)
            session.assert_not_called()


class Storage(unittest.TestCase):
    def test_current_running_booted_and_newest_share_three_slots(self):
        self.assertEqual(system.deletion_candidates(list(range(1, 9)), {8}), [1, 2, 3, 4, 5])
        self.assertEqual(system.deletion_candidates(list(range(1, 9)), {2, 4, 8}), [1, 3, 5, 6, 7])
        self.assertEqual(system.deletion_candidates([1, 2], {1}), [])

    def test_cleanup_guard_rejects_missing_apply(self):
        with (
            patch.object(system.os, "geteuid", return_value=0),
            patch.object(sys, "argv", ["helper", "cleanup"]),
            patch.object(system, "cleanup") as cleanup,
            patch.object(system, "event"),
        ):
            self.assertEqual(system.main(), 2)
            cleanup.assert_not_called()

    def test_generation_deletion_precedes_boot_refresh_and_gc(self):
        with tempfile.TemporaryDirectory() as directory:
            profile = Path(directory) / "system"
            for generation in range(1, 6):
                target = Path(directory) / f"closure-{generation}"
                target.mkdir()
                profile.with_name(f"system-{generation}-link").symlink_to(target)
            profile.symlink_to(profile.with_name("system-5-link"))
            original_exists = Path.exists

            def exists(path):
                return (
                    False
                    if str(path) in {"/run/current-system", "/run/booted-system"}
                    else original_exists(path)
                )

            with (
                patch.object(system, "PROFILE", profile),
                patch.object(Path, "exists", exists),
                patch.object(system, "disk_check", return_value={"data": {"cleanup_safe": True}}),
                patch("builtins.open", mock_open()),
                patch.object(system.fcntl, "flock"),
                patch.object(system.shutil, "disk_usage", return_value=Mock(free=1024)),
                patch.object(system, "event"),
                patch.object(
                    system,
                    "run",
                    side_effect=["1 date\n2 date\n3 date\n4 date\n5 date (current)\n", "", "", ""],
                ) as run,
            ):
                system.cleanup()
                commands = [call.args[0] for call in run.call_args_list]
                self.assertEqual(commands[1][-3:], ["--delete-generations", "1", "2"])
                self.assertEqual(
                    commands[2], [str(profile / "bin/switch-to-configuration"), "boot"]
                )
                self.assertEqual(commands[3], ["nix-store", "--gc"])

    def test_bad_mounts_prevent_any_cleanup_command(self):
        with (
            patch.object(system, "disk_check", return_value={"data": {"cleanup_safe": False}}),
            patch.object(system, "run") as run,
        ):
            with self.assertRaisesRegex(RuntimeError, "Mount verification failed"):
                system.cleanup()
            run.assert_not_called()

    def test_readonly_disk_check_does_not_acquire_the_network_lock(self):
        with (
            patch.object(system.os, "geteuid", return_value=0),
            patch.object(sys, "argv", ["helper", "disk-check"]),
            patch.object(
                system,
                "disk_check",
                return_value=health.report("Storage and mounts", [], cleanup_safe=True),
            ),
            patch("builtins.open") as opened,
            contextlib.redirect_stdout(io.StringIO()),
        ):
            self.assertEqual(system.main(), 0)
            opened.assert_not_called()


if __name__ == "__main__":
    unittest.main()
