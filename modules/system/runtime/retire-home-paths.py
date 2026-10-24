"""Update live home references while the migrated user's processes are stopped."""

import json
import os
from pathlib import Path
import re
import sqlite3
import stat
import tempfile
import lz4.block
import tomlkit

HOME = Path("/home/folio")
OLD = "/home/sylphy"
NEW = str(HOME)
PATTERN = re.compile(re.escape(OLD) + r"(?=$|[^A-Za-z0-9_.-])")
EXCLUDED = {
    "cache",
    "Cache",
    "CacheStorage",
    "GPUCache",
    "sessions",
    "logs",
    "history",
    "history.jsonl",
    "shell_snapshots",
    "keyrings",
    "migration",
    "backups",
    "home-migration",
    "node_modules",
    ".git",
    "elpa",
    "straight",
    "eln-cache",
    "plugins",
    "rime",
    "flatpak",
}


def replace(value):
    return PATTERN.sub(NEW, value)


def atomic(path, data):
    info = path.stat()
    fd, name = tempfile.mkstemp(prefix=".folio-path-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(name, stat.S_IMODE(info.st_mode) | stat.S_IWUSR)
        os.replace(name, path)
    finally:
        if os.path.lexists(name):
            os.unlink(name)


def database(path):
    # Update typed TEXT cells through SQLite, preserving BLOBs and file formats.
    with sqlite3.connect(path) as db:
        db.create_function("folio_new_home", 1, replace)
        tables = list(
            db.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND sql NOT LIKE '%VIRTUAL TABLE%'"
            )
        )
        for (table,) in tables:
            quoted = '"' + table.replace('"', '""') + '"'
            for row in list(db.execute("PRAGMA table_info(" + quoted + ")")):
                column = '"' + row[1].replace('"', '""') + '"'
                db.execute(
                    f"UPDATE {quoted} SET {column}=folio_new_home({column}) WHERE typeof({column})='text' AND instr({column},?)>0",
                    (OLD,),
                )
        assert db.execute("PRAGMA quick_check").fetchone()[0] == "ok"
    with sqlite3.connect(path) as db:
        db.execute("PRAGMA wal_checkpoint(TRUNCATE)")


def update(path):
    if path.is_symlink():
        target = os.readlink(path)
        changed = replace(target)
        if changed != target:
            temporary = path.with_name(path.name + ".folio-new-link")
            if temporary.exists() or temporary.is_symlink():
                raise RuntimeError("Unexpected temporary link: " + str(temporary))
            temporary.symlink_to(changed)
            os.replace(temporary, path)
        if not path.is_file():
            return
    if not path.is_file() or path.stat().st_size > 32 * 1024 * 1024:
        return
    raw = path.read_bytes()
    if raw.startswith(b"SQLite format 3\0"):
        if OLD.encode() in raw:
            if path.is_symlink():
                raise RuntimeError("Refusing to edit a symlinked database: " + str(path))
            database(path)
        return
    compressed = raw.startswith(b"mozLz40\0")
    data = lz4.block.decompress(raw[8:]) if compressed else raw
    if b"\0" in data or OLD.encode() not in data:
        return
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return
    if path.name == "config.toml" and path.parent.name in (".codex", ".codex-account2"):
        document = tomlkit.parse(text)
        projects = document.get("projects", {})
        for name in list(projects):
            new_name = replace(name)
            if new_name != name:
                if new_name not in projects:
                    projects[new_name] = projects[name]
                else:
                    for key, value in projects[name].items():
                        if key not in projects[new_name]:
                            projects[new_name][key] = value
                del projects[name]
        changed = replace(tomlkit.dumps(document)).encode("utf-8")
        tomlkit.parse(changed.decode("utf-8"))
    else:
        changed = replace(text).encode("utf-8")
    if changed == data:
        return
    if compressed:
        # Validate the complete session before re-encoding the Mozilla format.
        json.loads(changed)
        changed = b"mozLz40\0" + lz4.block.compress(changed, store_size=True)
    atomic(path, changed)


def main():
    if os.getuid() != 1000 or Path.home() != HOME:
        raise RuntimeError("Run offline as folio with HOME=/home/folio")
    roots = [
        ".config",
        ".local/bin",
        ".local/state/sylphy",
        ".local/state/noctalia",
        ".local/share",
        ".ssh",
        ".emacs.d",
    ]
    for relative in roots:
        root = HOME / relative
        for base, dirs, files in os.walk(root, followlinks=False):
            dirs[:] = [name for name in dirs if name not in EXCLUDED]
            for name in dirs + files:
                if name not in EXCLUDED:
                    update(Path(base) / name)
    for path in HOME.iterdir():
        if path.name.startswith(".") and (path.is_file() or path.is_symlink()):
            update(path)
    for directory in (HOME / ".codex", HOME / ".codex-account2"):
        for name in ("config.toml", "state_5.sqlite"):
            path = directory / name
            if path.exists():
                update(path)
    journal = HOME / ".local/state/sylphy/home/transaction.json"
    if journal.exists():
        data = json.loads(journal.read_text())
        if data.get("user") == "sylphy":
            data["user"] = "folio"
            atomic(journal, (json.dumps(data, sort_keys=True) + "\n").encode())
    print("Live home references updated; credentials and historical transcripts retained.")


if __name__ == "__main__":
    main()
