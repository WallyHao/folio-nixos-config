"""The catalogue delegates mutations and ownership to the applications backend."""

import json
from pathlib import Path
import sys

import pytest
from folio_store import Store, StoreError, repair_icon_theme


@pytest.fixture
def store(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    monkeypatch.delenv("FLATPAK_USER_DIR", raising=False)
    executable = tmp_path / "flatpak"
    executable.write_text(
        f"#!{sys.executable}\n"
        + r"""import pathlib, sys
args = sys.argv[1:]
root = pathlib.Path(__file__).parent
if args[0] == "remotes": print("flathub")
elif args[0] == "remote-ls": print("com.valvesoftware.Steam\tstable")
elif args[0] == "search": print("com.valvesoftware.Steam\tSteam\tGames <script>\t1.0\tstable\tflathub")
elif args[0] == "list":
    if (root / "installed").exists(): print("com.valvesoftware.Steam/x86_64/stable\tSteam\t1.0\tflathub")
else: raise SystemExit(2)
"""
    )
    executable.chmod(0o755)
    cli = tmp_path / "folio"
    cli.write_text(
        f"#!{sys.executable}\n"
        + r"""import json, pathlib, sys
root = pathlib.Path(__file__).parent
args = sys.argv[1:]
with (root / "calls").open("a") as f: f.write(json.dumps(args) + "\n")
if (root / "fail").exists():
    print(json.dumps({"status":"unavailable", "error":"Model upgrade required"})); sys.exit(3)
managed = (root / "managed").exists()
if args == ["--json", "config", "show"]:
    apps = [{"name":"com.valvesoftware.Steam", "ref":"app/com.valvesoftware.Steam/x86_64/stable"}] if managed else []
    data = {"configuration":{"folio-environment:environment":{"modules":[{"name":"applications", "folio-applications:applications":{"app":apps}}]}}}
else:
    assert args[:3] == ["--json", "--no-wait", "apps"]
    action = args[3]
    if action in ("install", "adopt"):
        (root / "managed").touch(); (root / "installed").touch()
        owned = root / "state/owned"; owned.mkdir(parents=True, exist_ok=True)
        (owned / "com.valvesoftware.Steam.json").write_text(json.dumps({"ref":"app/com.valvesoftware.Steam/x86_64/stable"}))
    if action == "remove": (root / "installed").unlink()
    data = {"id":"a-"+"a"*32, "phase":"succeeded", "request":{"action":action, "application":"com.valvesoftware.Steam"}, "createdAt":"2026-10-22"}
    tasks = root / "state/tasks"; tasks.mkdir(parents=True, exist_ok=True)
    (tasks / (data["id"]+".json")).write_text(json.dumps(data))
print(json.dumps({"status":"success", "data":data, "taskId":data.get("id")}))
"""
    )
    cli.chmod(0o755)
    return Store(str(executable), str(cli), tmp_path / "state")


def test_install_uses_shared_backend_and_removal_preserves_ownership(store):
    app = store.search("Steam")["applications"][0]
    task = store.start("install", {k: app[k] for k in ("id", "remote", "branch")})
    assert task["phase"] == "succeeded"
    apps = store.status()["applications"]
    user = next(a for a in apps if a["scope"] == "user")
    system = next(a for a in apps if a["scope"] == "system")
    assert user["managed"] and user["removable"]
    assert not system["managed"] and not system["removable"]
    assert Store(store.executable, store.client, store.directory).task == task
    store.start("remove", {"ref": user["ref"]})
    calls = [
        json.loads(line)
        for line in (Path(store.executable).parent / "calls").read_text().splitlines()
    ]
    assert ["--json", "--no-wait", "apps", "install", app["id"], "--ref", user["ref"]] in calls
    assert ["--json", "--no-wait", "apps", "remove", app["id"]] in calls
    assert not store.status()["applications"]


def test_external_app_requires_explicit_adoption(store):
    (Path(store.executable).parent / "installed").touch()
    app = next(a for a in store.installed() if a["scope"] == "user")
    assert not app["managed"] and not app["removable"]
    with pytest.raises(ValueError):
        store.start("remove", {"ref": app["ref"]})
    store.start("adopt", {"id": app["id"], "remote": "flathub", "branch": "stable"})
    assert next(a for a in store.installed() if a["scope"] == "user")["managed"]


def test_backend_errors_and_restart_observation(store):
    (Path(store.executable).parent / "fail").touch()
    with pytest.raises(StoreError, match="Model upgrade"):
        store.start("refresh", {})
    tasks = store.directory / "tasks"
    tasks.mkdir(parents=True)
    task = {
        "id": "a-" + "b" * 32,
        "phase": "deploying",
        "request": {"action": "install"},
        "createdAt": "2026-10-22",
    }
    path = tasks / (task["id"] + ".json")
    path.write_text(json.dumps(task))
    assert Store(store.executable, store.client, store.directory).task["phase"] == "running"
    assert json.loads(path.read_text())["phase"] == "deploying"


@pytest.mark.parametrize(
    "action,fields",
    [
        ("install", {"id": "--help", "remote": "flathub", "branch": "stable"}),
        ("install", {"id": "org.test.App;touch /tmp/x", "remote": "flathub", "branch": "stable"}),
        ("install", {"id": "org.test.App", "remote": "untrusted", "branch": "stable"}),
        ("remove", {"ref": "runtime/org.test.App/x86_64/stable"}),
        ("setup", {"url": "https://untrusted.example"}),
        ("launch", {}),
    ],
)
def test_invalid_targets_have_no_effect(store, action, fields):
    with pytest.raises(ValueError):
        store.start(action, fields)
    assert not (Path(store.executable).parent / "calls").exists()


def test_readonly_icon_export_is_replaced_without_changing_source(tmp_path, monkeypatch):
    import os

    monkeypatch.setenv("FLATPAK_USER_DIR", str(tmp_path))
    source = tmp_path / "source.theme"
    source.write_text("[Icon Theme]\nName=Hicolor\n")
    source.chmod(0o444)
    target = tmp_path / "exports/share/icons/hicolor/index.theme"
    target.parent.mkdir(parents=True)
    os.link(source, target)
    repair_icon_theme()
    assert target.read_text() == source.read_text()
    assert target.stat().st_mode & 0o200
    assert not source.stat().st_mode & 0o200
    assert target.stat().st_ino != source.stat().st_ino
