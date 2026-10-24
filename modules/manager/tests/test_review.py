"""Public value previews, module impact hints and actual kernel target changes."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class ReviewTests(unittest.TestCase):
    def test_public_preview_preserves_private_settings_and_detects_kernel_change(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name, size, enabled, secret in [
                ("old", 16, True, "old-private-value"),
                ("new", 18, False, "new-private-value"),
            ]:
                source = root / name
                (source / "modules/terminal/src").mkdir(parents=True)
                (source / "modules/terminal/src/file").write_text(name)
                config = {
                    "preferences": {"font-size": size},
                    "modules": [
                        {"name": "terminal", "enabled": enabled, "settings": {"token": secret}}
                    ],
                }
                (source / "folio-input.json").write_text(
                    json.dumps({"configuration": {"folio-environment:environment": config}})
                )
                kernel = root / ("kernel-" + name)
                kernel.write_text(name)
                (source / "kernel").symlink_to(kernel)
            catalogue = root / "catalogue.json"
            catalogue.write_text(json.dumps({"terminal": {"impacts": ["Open a new terminal."]}}))
            result = subprocess.run(
                [
                    sys.executable,
                    os.environ["REVIEW_COMMAND"],
                    str(root / "new"),
                    str(root / "old"),
                    str(root / "new"),
                    str(root / "old"),
                ],
                capture_output=True,
                text=True,
                check=True,
                env=os.environ | {"FOLIO_CATALOGUE": str(catalogue)},
            )
            review = json.loads(result.stdout)
            self.assertEqual(
                review["preferenceChanges"], [{"field": "font-size", "before": 16, "after": 18}]
            )
            self.assertEqual(review["disabledModules"], ["terminal"])
            self.assertTrue(review["kernelChanged"])
            self.assertEqual(review["impacts"][0]["message"], "Open a new terminal.")
            self.assertNotIn("private-value", result.stdout)
            self.assertNotIn("token", result.stdout)


if __name__ == "__main__":
    unittest.main()
