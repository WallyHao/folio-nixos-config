"""Health diagnostics, concurrency, and confirmation-gated repair boundaries."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


root = Path(os.environ["FOLIO_WORKSPACE_SOURCE"])
health = load("folio_workspace_health", root / "runtime/health.py")
client = load("health_client", root / "cli/prepare.py")


def good_reports():
    return [
        health.report("Storage and mounts", [], cleanup_safe=True),
        health.report("Service health", [], failed=[]),
        health.report("Time synchronization", [], synchronized=True, ntp_enabled=True),
        health.report("DNS and service connectivity", []),
    ]


class MountChecks(unittest.TestCase):
    def setUp(self):
        self.expected = [
            {"target": "/", "device": "/dev/root", "fsType": "btrfs", "options": ["subvol=root"]},
            {"target": "/boot", "device": "/dev/efi", "fsType": "vfat", "options": []},
        ]
        self.actual = [
            {
                "target": "/",
                "source": "/dev/root[/root]",
                "fstype": "btrfs",
                "fsroot": "/root",
                "options": "rw,relatime",
            },
            {
                "target": "/boot",
                "source": "/dev/efi",
                "fstype": "vfat",
                "fsroot": "/",
                "options": "rw",
            },
        ]
        self.usage = SimpleNamespace(
            f_bavail=20 * 1024**3,
            f_frsize=1,
            f_blocks=100 * 1024**3,
            f_flag=0,
            f_files=0,
            f_favail=0,
        )
        patch.object(
            health, "CONFIG", Mock(read_text=lambda: json.dumps({"mounts": self.expected}))
        ).start()
        patch.object(
            health,
            "command",
            side_effect=lambda *a, **k: Mock(stdout=json.dumps({"filesystems": self.actual})),
        ).start()
        patch.object(health.os, "statvfs", side_effect=lambda path: self.usage).start()
        self.addCleanup(patch.stopall)

    def test_shared_root_filesystems_and_btrfs_without_inodes_are_valid(self):
        result = health.disk_check()
        self.assertTrue(result["data"]["cleanup_safe"])
        self.assertEqual([item["tone"] for item in result["findings"]], ["success"] * 4)

    def test_missing_boot_mount_is_not_hidden_by_an_existing_boot_directory(self):
        self.actual.pop()
        result = health.disk_check()
        self.assertFalse(result["data"]["cleanup_safe"])
        self.assertIn("expected mount /boot", result["findings"][-1]["message"])

    def test_wrong_device_subvolume_and_readonly_mount_block_cleanup(self):
        self.actual[0].update(source="/dev/wrong[/other]", fsroot="/other", options="ro")
        result = health.disk_check()
        self.assertFalse(result["data"]["cleanup_safe"])
        messages = " ".join(item["message"] for item in result["findings"])
        self.assertIn("mounted device differs", messages)
        self.assertIn("subvolume differs", messages)
        self.assertIn("read-only", messages)

    def test_low_space_reports_error_but_allows_confirmed_cleanup(self):
        self.usage.f_bavail = 512 * 1024**2
        result = health.disk_check()
        self.assertTrue(result["data"]["cleanup_safe"])
        self.assertEqual(result["findings"][0]["tone"], "error")

    def test_boot_has_a_smaller_absolute_space_threshold(self):
        self.usage.f_bavail, self.usage.f_blocks = 200 * 1024**2, 1024**3
        result = health.disk_check()
        self.assertEqual(result["findings"][-1]["tone"], "success")

    def test_inode_exhaustion_and_permission_errors_are_reported(self):
        self.usage.f_files, self.usage.f_favail = 1000, 1
        self.assertTrue(
            any(
                "inodes" in item["message"] and item["tone"] == "error"
                for item in health.disk_check()["findings"]
            )
        )
        with patch.object(health.os, "statvfs", side_effect=PermissionError("denied")):
            result = health.disk_check()
            self.assertFalse(result["data"]["cleanup_safe"])


class ServicesAndTime(unittest.TestCase):
    def test_failed_services_include_exit_reason_and_log_command(self):
        def command(args, **kwargs):
            if "list-units" in args:
                return Mock(
                    stdout=json.dumps([{"unit": "demo.service"}]) if "--system" in args else "[]"
                )
            return Mock(
                stdout="Id=demo.service\nResult=exit-code\nExecMainStatus=1\nSubState=failed\n"
            )

        with patch.object(health, "command", side_effect=command):
            result = health.service_check()
        self.assertEqual(result["data"]["failed"], [{"scope": "system", "unit": "demo.service"}])
        self.assertTrue(any("exit=1" in item["message"] for item in result["findings"]))
        self.assertTrue(any("sudo journalctl" in item["message"] for item in result["findings"]))

    def test_user_bus_failure_does_not_hide_system_results(self):
        with patch.object(health, "failed_services", side_effect=[[], RuntimeError("no user bus")]):
            result = health.service_check()
        self.assertEqual([item["tone"] for item in result["findings"]], ["success", "warning"])

    def test_repair_rechecks_failed_state_and_never_restarts_healthy_units(self):
        with (
            patch.object(health, "failed_services", return_value=["bad.service"]),
            patch.object(
                health, "command", return_value=Mock(stdout="ActiveState=active\nResult=success\n")
            ) as command,
        ):
            result = health.restart_failed("system", ["healthy.service", "bad.service"])
        restarts = [call.args[0] for call in command.call_args_list if "restart" in call.args[0]]
        self.assertEqual(restarts, [["systemctl", "--system", "restart", "--", "bad.service"]])
        self.assertIn("restart skipped", result["findings"][0]["message"])

    def test_repair_rejects_arbitrary_unit_types_options_and_paths(self):
        with patch.object(health, "command") as command:
            for unit in (
                "x.target",
                "--all.service",
                "../bad.service",
                "bad\n.service",
                "x.service; reboot",
                "*.service",
            ):
                with self.assertRaises(ValueError):
                    health.restart_failed("system", [unit])
            command.assert_not_called()

    def test_restart_errors_are_reported_and_other_requested_units_continue(self):
        with (
            patch.object(health, "failed_services", return_value=["a.service", "b.service"]),
            patch.object(
                health,
                "command",
                side_effect=[
                    RuntimeError("failed"),
                    Mock(stdout=""),
                    Mock(stdout="ActiveState=inactive\nResult=success\n"),
                ],
            ),
        ):
            result = health.restart_failed("user", ["a.service", "b.service"])
        self.assertEqual([item["tone"] for item in result["findings"]], ["error", "success"])

    def test_clock_gets_a_bounded_readonly_grace_period(self):
        with (
            patch.object(
                health,
                "command",
                side_effect=[
                    Mock(stdout="NTPSynchronized=no\nNTP=yes\nTimezone=Asia/Shanghai\n"),
                    Mock(stdout="NTPSynchronized=yes\nNTP=yes\nTimezone=Asia/Shanghai\n"),
                ],
            ) as command,
            patch.object(health.time, "sleep"),
        ):
            result = health.time_check(wait=8)
        self.assertTrue(result["data"]["synchronized"])
        self.assertTrue(all(call.args[0][0] == "timedatectl" for call in command.call_args_list))
        self.assertTrue(
            all(
                "--property=NTP" in call.args[0] and "--property=NTPSynchronized" in call.args[0]
                for call in command.call_args_list
            )
        )

    def test_missing_clock_properties_are_unavailable_not_reported_as_disabled(self):
        with patch.object(health, "command", return_value=Mock(stdout="")):
            result = health.safe_check("Time synchronization", health.time_check)
        self.assertEqual(result["data"], {})
        self.assertIn("incomplete", result["findings"][0]["message"])

    def test_disabled_ntp_is_not_automatically_enabled_by_retry(self):
        with (
            patch.object(
                health, "time_check", return_value=health.report("Time", [], ntp_enabled=False)
            ),
            patch.object(health, "command") as command,
        ):
            with self.assertRaisesRegex(RuntimeError, "NTP is disabled"):
                health.retry_time_sync()
            command.assert_not_called()

    def test_retry_restarts_only_timesyncd_then_rechecks(self):
        before = health.report("Time", [], ntp_enabled=True, synchronized=False)
        after = health.report("Time", [], ntp_enabled=True, synchronized=True)
        with (
            patch.object(health, "time_check", side_effect=[before, after]),
            patch.object(health, "command") as command,
        ):
            self.assertEqual(health.retry_time_sync(), after)
        command.assert_called_once_with(
            ["systemctl", "--system", "restart", "systemd-timesyncd.service"], timeout=20
        )


class ConnectivityAndScheduling(unittest.TestCase):
    def test_dns_timeout_and_http_error_are_separate_findings(self):
        with patch.object(health, "command", side_effect=subprocess.TimeoutExpired("getent", 5)):
            self.assertEqual(health.dns_check("github.com")["tone"], "warning")
        with patch.object(health, "command", return_value=Mock(returncode=0, stdout="503 0.5")):
            self.assertIn(
                "HTTP 503", health.https_check("GitHub", "https://github.com/", 200)["message"]
            )

    def test_https_verifies_tls_and_bypasses_environment_proxy(self):
        with patch.object(
            health, "command", return_value=Mock(returncode=0, stdout="200 0.2")
        ) as command:
            self.assertEqual(
                health.https_check("Nix cache", "https://cache.nixos.org/nix-cache-info", 200)[
                    "tone"
                ],
                "success",
            )
        args = command.call_args.args[0]
        self.assertEqual(args[args.index("--noproxy") + 1], "*")
        self.assertNotIn("--insecure", args)

    def test_all_six_network_probes_run_concurrently(self):
        barrier = threading.Barrier(6, timeout=3)

        def probe(*args):
            barrier.wait()
            return health.finding(str(args[0]), "success")

        with (
            patch.object(health, "dns_check", side_effect=probe),
            patch.object(health, "https_check", side_effect=probe),
        ):
            result = health.connectivity_check()
        self.assertEqual(len(result["findings"]), 7)

    def test_three_local_checks_overlap_network_initialization(self):
        barrier = threading.Barrier(4, timeout=3)

        def local(index):
            barrier.wait()
            return good_reports()[index]

        def network(*args):
            barrier.wait()
            return 1

        with (
            patch.object(client, "privileged_disk_check", side_effect=lambda: local(0)),
            patch.object(client, "service_check", side_effect=lambda: local(1)),
            patch.object(client, "time_check", side_effect=lambda: local(2)),
            patch.object(client, "backend", side_effect=network),
            patch.object(client, "connectivity_check") as connectivity,
        ):
            ready, reports = client.automatic_checks(Mock())
        self.assertFalse(ready)
        self.assertEqual(len(reports), 4)
        connectivity.assert_not_called()

    def test_one_unavailable_check_does_not_abort_the_other_reports(self):
        with (
            patch.object(client, "privileged_disk_check", side_effect=OSError("missing helper")),
            patch.object(client, "service_check", return_value=good_reports()[1]),
            patch.object(client, "time_check", return_value=good_reports()[2]),
            patch.object(client, "connectivity_check", return_value=good_reports()[3]),
            patch.object(client, "backend", return_value=0),
        ):
            ready, reports = client.automatic_checks(Mock())
        self.assertTrue(ready)
        self.assertEqual(client.status(reports[0]), "WARN")
        self.assertEqual(client.status(reports[1]), "PASS")


class RepairConsent(unittest.TestCase):
    def setUp(self):
        self.reports = good_reports()
        self.reports[1]["data"]["failed"] = [
            {"scope": "system", "unit": "bad.service"},
            {"scope": "user", "unit": "user.service"},
        ]
        self.reports[2]["data"].update(synchronized=False)

    def test_declining_all_repairs_never_mutates_services_or_clock(self):
        with (
            patch.object(client, "approved", return_value=False),
            patch.object(client, "privileged_repair") as system,
            patch.object(client, "restart_failed") as user,
        ):
            client.optional_repairs(Mock(), self.reports)
        system.assert_not_called()
        user.assert_not_called()

    def test_noninteractive_input_cannot_approve_repairs(self):
        with (
            patch.object(client.sys, "stdin", Mock(isatty=lambda: False)),
            patch("builtins.input") as prompt,
        ):
            self.assertFalse(client.approved(Mock(), "Restart?"))
        prompt.assert_not_called()

    def test_confirmed_repairs_keep_system_and_user_scopes_separate(self):
        with (
            patch.object(client, "approved", return_value=True),
            patch.object(
                client, "privileged_repair", return_value=health.report("Repair", [])
            ) as system,
            patch.object(
                client, "restart_failed", return_value=health.report("Repair", [])
            ) as user,
            patch.object(client, "service_check", return_value=good_reports()[1]),
            patch.object(client, "time_check", return_value=good_reports()[2]),
            patch.object(client, "connectivity_check", return_value=good_reports()[3]),
        ):
            client.optional_repairs(Mock(), self.reports)
        system.assert_called_once_with("repair-services", ["bad.service"])
        user.assert_called_once_with("user", ["user.service"])

    def test_failed_repair_is_an_error_even_if_later_checks_are_unavailable(self):
        with (
            patch.object(client, "approved", return_value=True),
            patch.object(client, "privileged_repair", side_effect=RuntimeError("denied")),
            patch.object(client, "restart_failed", return_value=health.report("Repair", [])),
            patch.object(client, "service_check", side_effect=RuntimeError("unavailable")),
            patch.object(client, "time_check", return_value=good_reports()[2]),
            patch.object(client, "connectivity_check", return_value=good_reports()[3]),
        ):
            repairs = client.optional_repairs(Mock(), self.reports)
        self.assertEqual(client.status(repairs[0]), "FAIL")


if __name__ == "__main__":
    unittest.main()
