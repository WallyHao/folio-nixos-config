"""Global theme selection uses one system choice and the combined deployment workflow."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class ThemeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.catalogue = self.root / "catalogue.json"
        self.catalogue.write_text(
            json.dumps({"everforest": ["dark", "light"], "graphite": ["dark", "light"]})
        )
        (self.root / "flake.nix").write_text("{}")
        self.state = self.root / "state.json"
        self.state.write_text(
            json.dumps(
                {
                    "calls": [],
                    "system": {
                        "preferences": {
                            "scheme": "everforest",
                            "appearance": "dark",
                            "font-size": 16,
                        }
                    },
                    "user": {
                        "preferences": {"font-size": 19},
                        "modules": [{"name": "desktop", "enabled": True}],
                    },
                }
            )
        )
        adapter = self.root / "adapter"
        adapter.write_text(
            f"#!{sys.executable}\n"
            + """import json, os, sys
from pathlib import Path
p = Path(os.environ['THEME_STATE'])
s = json.loads(p.read_text())
a = sys.argv[1:]
operation = a[0]
scope = os.environ['FOLIO_SCOPE'] if operation in ('show', 'import') else 'combined'
key = scope + ':' + operation
s['calls'].append(key)
status = s.get('fail', {}).get(key, 'success')
data = None
if operation == 'show':
    data = {'digest': 'a'*64, 'configuration': {'folio-environment:environment': s[scope]}}
elif operation == 'import' and status == 'success':
    assert a[2:] == ['--expected-digest', 'a'*64]
    s[scope] = json.loads(Path(a[1]).read_text())['folio-environment:environment']
    data = {'digest': 'b'*64}
elif operation == 'plan':
    assert a[1:4] == ['--source', os.environ['FOLIO_THEME_SOURCE'], '--yes']
    assert a[4] == '--comment' and 'theme' in a[5]
    data = {'planId': None if s.get('unchanged') else 'c'*64}
elif operation in ('build', 'apply'):
    assert a == [operation, 'c'*64]
p.write_text(json.dumps(s))
print(json.dumps({'status': status, 'data': data, 'error': None if status == 'success' else 'fixture failure', 'taskId': None}))
sys.exit(0 if status == 'success' else 1)
"""
        )
        adapter.chmod(0o700)
        # Exercise the privilege boundary without invoking the real sudo binary.
        sudo = self.root / "sudo"
        sudo.write_text(
            f"#!{sys.executable}\n"
            + """import os, sys
args = sys.argv[1:]
assert args.pop(0) == 'env'
env = os.environ.copy()
while '=' in args[0]:
    key, value = args.pop(0).split('=', 1)
    env[key] = value
assert env['FOLIO_SCOPE'] == 'system'
os.execvpe(args[0], args, env)
"""
        )
        sudo.chmod(0o700)
        self.env = os.environ | {
            "FOLIO_SCOPE": "system",
            "FOLIO_JSON": "true",
            "FOLIO_CONFIG_ADAPTER": str(adapter),
            "FOLIO_WORKFLOW_ADAPTER": str(adapter),
            "FOLIO_THEME_CATALOGUE": str(self.catalogue),
            "THEME_STATE": str(self.state),
            "FOLIO_THEME_SOURCE": str(self.root),
            "PATH": str(self.root) + ":" + os.environ["PATH"],
        }

    def run_theme(self, *args, code=0):
        result = subprocess.run(
            [sys.executable, os.environ["THEME_COMMAND"], *args],
            env=self.env,
            capture_output=True,
            text=True,
            cwd=self.root.parent,
        )
        self.assertEqual(result.returncode, code, result.stderr + result.stdout)
        return json.loads(result.stdout)

    def read(self):
        return json.loads(self.state.read_text())

    def update(self, **kwargs):
        self.state.write_text(json.dumps(self.read() | kwargs))

    def test_list_requires_no_configuration_services(self):
        self.assertEqual(
            self.run_theme("list")["data"]["themes"],
            ["everforest-dark", "everforest-light", "graphite-dark", "graphite-light"],
        )
        self.assertEqual(self.read()["calls"], [])

    def test_set_always_deploys_both_environments(self):
        reply = self.run_theme("set", "graphite-light")
        self.assertTrue(reply["data"]["applied"])
        self.assertEqual(
            self.read()["system"]["preferences"],
            {"scheme": "graphite", "appearance": "light", "font-size": 16},
        )
        self.assertEqual(self.read()["user"]["preferences"], {"font-size": 19})
        self.assertEqual(
            self.read()["calls"],
            [
                "system:show",
                "user:show",
                "system:import",
                "combined:plan",
                "combined:build",
                "combined:apply",
            ],
        )

    def test_legacy_overrides_cannot_keep_a_different_theme(self):
        user = self.read()["user"]
        user["preferences"].update(scheme="everforest", appearance="light")
        user["modules"].append(
            {
                "name": "appearance",
                "folio-appearance:appearance": {"appearance": "light", "cursor-size": 32},
            }
        )
        self.update(user=user)
        self.run_theme("set", "graphite-dark")
        self.assertEqual(self.read()["user"]["preferences"], {"font-size": 19})
        self.assertEqual(
            self.read()["user"]["modules"][1]["folio-appearance:appearance"], {"cursor-size": 32}
        )
        self.assertIn("user:import", self.read()["calls"])

    def test_failed_build_keeps_recovery_plan_and_stops_apply(self):
        self.update(fail={"combined:build": "failure"})
        reply = self.run_theme("set", "graphite-dark", code=1)
        self.assertIn("saved but not fully applied", reply["error"])
        self.assertEqual(reply["data"]["planId"], "c" * 64)
        self.assertFalse(reply["data"]["applied"])
        self.assertNotIn("combined:apply", self.read()["calls"])

    def test_concurrent_system_edit_blocks_deployment(self):
        self.update(fail={"system:import": "conflict"})
        self.assertEqual(self.run_theme("set", "graphite-dark", code=4)["status"], "conflict")
        self.assertNotIn("combined:plan", self.read()["calls"])
        self.assertEqual(self.read()["system"]["preferences"]["scheme"], "everforest")

    def test_unavailable_desktop_fails_before_system_write(self):
        self.update(fail={"user:show": "unavailable"})
        self.run_theme("set", "graphite-dark", code=3)
        self.assertNotIn("system:import", self.read()["calls"])

    def test_unchanged_theme_needs_no_build(self):
        self.update(unchanged=True)
        self.assertTrue(self.run_theme("set", "everforest-dark")["data"]["applied"])
        self.assertNotIn("combined:build", self.read()["calls"])

    def test_only_two_actions_and_complete_theme_names(self):
        for args in [
            ("status",),
            ("inherit",),
            ("set", "graphite"),
            ("set", "unknown"),
            ("set", "graphite-dark", "--apply"),
            ("set", "graphite-dark", "--appearance", "light"),
        ]:
            self.assertEqual(self.run_theme(*args, code=2)["status"], "invalid")
        self.assertEqual(self.read()["calls"], [])


if __name__ == "__main__":
    unittest.main()
