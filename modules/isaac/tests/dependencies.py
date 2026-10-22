"""Reject unreviewed conflicts while honoring exactly the upstream overrides."""
import contextlib
import io
import json
import os
from pathlib import Path
import runpy
import tempfile
from types import SimpleNamespace
from unittest.mock import patch


def dist(name, version, requires=()):
    return SimpleNamespace(metadata={"Name": name}, version=version, requires=requires)


with tempfile.TemporaryDirectory() as temporary:
    os.chdir(temporary)
    Path("pyproject.toml").write_text('[tool.uv]\noverride-dependencies = ["torch==2.11.0"]\n')
    cases = [
        ([dist("sim", "6.2", ["torch==2.10.0"]), dist("torch", "2.11.0")], True),
        ([dist("sim", "6.2", ["torch==2.10.0"]), dist("torch", "2.9.0")], False),
        ([dist("sim", "6.2", ["missing>=1"])], False),
    ]
    for installed, expected in cases:
        output = io.StringIO()
        code = 0
        with patch("importlib.metadata.distributions", return_value=installed), contextlib.redirect_stdout(output):
            try:
                runpy.run_path(os.environ["ISAAC_DEPENDENCY_CHECK"], run_name="__main__")
            except SystemExit as error:
                code = error.code
        report = json.loads(output.getvalue())
        assert (code == 0) == expected, report
        assert (report["status"] == "passed") == expected
    print("Reviewed overrides, wrong overridden versions and missing dependencies passed")
