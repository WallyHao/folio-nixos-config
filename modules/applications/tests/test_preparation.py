"""Exercise retained-plan selection with the real worker shell and jq."""

import json
from pathlib import Path
import subprocess

import pytest


@pytest.mark.parametrize(
    "action,offline,cached,expected_calls",
    [
        ("install", False, "missing", 1),
        ("install", False, "changed", 1),
        ("install", False, "complete", 0),
        ("install", True, "missing", 0),
        ("install", True, "changed", 0),
        ("update", False, "complete", 1),
        ("prepare", False, "missing", 1),
    ],
)
def test_retained_plan(tmp_path, action, offline, cached, expected_calls):
    worker = Path(__file__).parent.parent / "runtime/operations/reconcile.sh"
    source = worker.read_text()
    selection = source[
        source.index("      plan_path=") : source.index('      [[ "$action" != prepare ]]')
    ]
    ref = "app/com.tencent.WeChat/x86_64/stable"
    commit = "a" * 64
    plan = {"ref": ref, "commit": commit, "operations": [{"ref": ref, "commit": commit}]}
    prepared = tmp_path / "prepared"
    prepared.mkdir()
    (prepared / f"wechat-{commit}.json").write_text(json.dumps(plan))
    cache = (
        []
        if cached == "missing"
        else [{"ref": ref, "commit": commit if cached == "complete" else "b" * 64}]
    )
    (tmp_path / "refs.json").write_text(json.dumps(cache))
    (tmp_path / "fresh.json").write_text(json.dumps({"data": plan}))
    script = (
        """
set -euo pipefail
app_state=$1; work=$1; action=$2; offline=$3; ref=$4; commit=$5; name=wechat
cached_refs() { cat "$work/refs.json"; }
checkpoint() { :; }
fail() { exit "${3:-1}"; }
folio-atomic-write() { cat >"$1"; }
folio-applications-transaction() {
  test "$1" = prepare && test "$4" = online
  echo prepare >>"$work/calls"
  jq '.data.operations' "$work/fresh.json" >"$work/refs.json"
  cat "$work/fresh.json"
}
"""
        + selection
    )
    if action != "prepare":
        start = source.index(
            '      cached_refs >"$work/cache.json"',
            source.index('      [[ "$action" != prepare ]]'),
        )
        script += source[start : source.index("      # Never change", start)]
    script += '\nprintf "%s\\n" "$plan"\n'
    result = subprocess.run(
        ["bash", "-c", script, "test", str(tmp_path), action, str(offline).lower(), ref, commit],
        capture_output=True,
        text=True,
    )
    unavailable = offline and cached != "complete"
    assert result.returncode == (3 if unavailable else 0), result.stderr
    if not unavailable:
        assert json.loads(result.stdout) == plan
    calls = tmp_path / "calls"
    assert (len(calls.read_text().splitlines()) if calls.exists() else 0) == expected_calls
