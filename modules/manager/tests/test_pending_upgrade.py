"""Pending desired edits must retain a verified old closure during model upgrade."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

source = Path(os.environ['ROLLBACK_SOURCE']).read_text()
functions = '\n'.join(re.search(r'^' + name + r'\(\) \{\n.*?^\}', source, re.M | re.S)[0]
                      for name in ['snapshot_artifact_matches', 'bind_before_applied_digest'])


class PendingUpgradeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.closure = os.environ['FIXTURE_CLOSURE']
        self.bootstrap = os.environ['FIXTURE_BOOTSTRAP']
        self.deployment = {'format': 1, 'artifact': self.closure, 'source': os.environ['FIXTURE_RETAINED'],
                           'configurationDigest': os.environ['FIXTURE_DIGEST']}
        self.write('running.json', {'pending': 'desired edit'})
        self.write('transaction.json', {'phase': 'backed-up'})

    def write(self, name, value):
        (self.root / name).write_text(json.dumps(value))

    def bind(self):
        self.write('deployment.json', self.deployment)
        prelude = '''set -euo pipefail
scope=user
backup=$1
work=$1
export HOME=/home/fixture
id() { printf 'fixture\\n'; }
immutable() { [[ "$1" =~ ^/nix/store/[a-z0-9]{32}-[^/]+$ && -d "$1" ]]; }
digest() { local v; v=$(sha256sum <"$1"); printf '%s' "${v%% *}"; }
folio-atomic-write() { cat >"$1.tmp"; mv "$1.tmp" "$1"; }
'''
        return subprocess.run(['bash', '-c', prelude + functions + '\nbind_before_applied_digest "$2" "$3"',
                               'test', str(self.root), self.closure, self.bootstrap], capture_output=True, text=True)

    def test_pending_edits_keep_their_own_digest(self):
        before = (self.root / 'running.json').read_bytes()
        result = self.bind()
        self.assertEqual(result.returncode, 0, result.stderr)
        transaction = json.loads((self.root / 'transaction.json').read_text())
        self.assertEqual(transaction['beforeAppliedDigest'], os.environ['FIXTURE_DIGEST'])
        self.assertEqual((self.root / 'running.json').read_bytes(), before)

    def test_wrong_selected_closure_is_rejected(self):
        self.deployment['artifact'] = '/nix/store/not-the-selected-closure'
        self.assertNotEqual(self.bind().returncode, 0)

    def test_wrong_deployment_digest_is_rejected(self):
        self.deployment['configurationDigest'] = '0' * 64
        self.assertNotEqual(self.bind().returncode, 0)

    def test_corrupt_retained_configuration_is_rejected(self):
        self.deployment['source'] = os.environ['FIXTURE_CORRUPT']
        self.assertNotEqual(self.bind().returncode, 0)

    def test_missing_retained_input_is_rejected(self):
        self.deployment['source'] = self.bootstrap
        self.assertNotEqual(self.bind().returncode, 0)


if __name__ == '__main__':
    unittest.main()
