"""Bounded fixture check for text, links, SQLite and Mozilla session migration."""

import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import lz4.block
import tomlkit

spec = importlib.util.spec_from_file_location("retirement", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as root:
    root = Path(root)
    source = root / "immutable"
    source.write_text("/home/sylphy/.config/zen\n/home/sylphy-other\n")
    source.chmod(0o444)
    path = root / "config"
    path.symlink_to(source)
    module.update(path)
    assert not path.is_symlink()
    assert path.read_text() == "/home/folio/.config/zen\n/home/sylphy-other\n"
    assert source.read_text().startswith("/home/sylphy/")
    path = root / "link"
    path.symlink_to("/home/sylphy/.config/zen")
    module.update(path)
    assert os.readlink(path) == "/home/folio/.config/zen"
    path = root / "profile.sqlite"
    with sqlite3.connect(path) as db:
        db.execute("CREATE TABLE fixture(path TEXT, opaque BLOB)")
        db.execute(
            "INSERT INTO fixture VALUES(?,?)", ("/home/sylphy/Downloads", b"opaque\0credential")
        )
    module.update(path)
    with sqlite3.connect(path) as db:
        assert db.execute("SELECT * FROM fixture").fetchone() == (
            "/home/folio/Downloads",
            b"opaque\0credential",
        )
    path = root / "session.jsonlz4"
    data = {"url": "file:///home/sylphy/Documents/test", "opaque": "retained-fixture"}
    path.write_bytes(b"mozLz40\0" + lz4.block.compress(json.dumps(data).encode(), store_size=True))
    module.update(path)
    result = json.loads(lz4.block.decompress(path.read_bytes()[8:]))
    assert result == {"url": "file:///home/folio/Documents/test", "opaque": "retained-fixture"}
    directory = root / ".codex-account2"
    directory.mkdir()
    path = directory / "config.toml"
    path.write_text(
        '[projects."/home/sylphy/Workspace"]\ntrust_level="trusted"\n[projects."/home/folio/Workspace"]\ntrust_level="untrusted"\n'
    )
    module.update(path)
    projects = tomlkit.parse(path.read_text())["projects"]
    assert list(projects) == ["/home/folio/Workspace"]
    assert projects["/home/folio/Workspace"]["trust_level"] == "untrusted"
print(
    "PASS: immutable source retained; text, absolute links, SQLite and compressed sessions updated; credential fixture preserved"
)
