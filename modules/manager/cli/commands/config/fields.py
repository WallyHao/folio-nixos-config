"""Resolve public setting paths and edit private desired documents."""

import json
import os
from pathlib import Path
import sys


def catalogue():
    path = os.environ.get("FOLIO_CATALOGUE")
    return json.loads(Path(path).read_text()) if path else {}


def canonical_path(path, definitions):
    parts = path.split("/")[1:]
    if not path.startswith("/") or not parts or parts[0] not in {"preferences", "modules"}:
        raise ValueError("Use /preferences/FIELD or /modules/NAME/SETTING")
    if any(not part or "~" in part for part in parts):
        raise ValueError("Empty or escaped path components are unsupported")
    if parts[0] == "preferences":
        if len(parts) != 2:
            raise ValueError("Select an individual preference")
    else:
        if len(parts) < 3:
            raise ValueError("Select an individual module setting")
        if parts[2] not in {"name", "enabled"} and ":" not in parts[2]:
            key = definitions.get(parts[1], {}).get("settingsKey", f"folio-{parts[1]}:{parts[1]}")
            parts.insert(2, key)
    return parts


def resolve(document, path, *, create=False, definitions=None):
    parts = canonical_path(path, definitions if definitions is not None else catalogue())
    current = document["folio-environment:environment"]
    for part in parts[:-1]:
        if isinstance(current, list):
            matches = [entry for entry in current if entry.get("name") == part]
            if len(matches) != 1:
                raise ValueError("Named entry is missing or ambiguous: " + part)
            current = matches[0]
        elif isinstance(current, dict):
            if part not in current and create:
                current[part] = {}
            current = current[part]
        else:
            raise ValueError("Path traverses a scalar")
    if not isinstance(current, dict):
        raise ValueError("Select an individual setting")
    return current, parts[-1]


def main():
    try:
        action, path, *values = sys.argv[1:]
        document = json.load(sys.stdin)
        parts = canonical_path(path, catalogue())
        if action != "get" and parts[0] == "modules" and parts[-1] == "name":
            raise ValueError("Module identities cannot be edited")
        try:
            parent, key = resolve(document, path, create=action == "set")
            if action == "get":
                print(json.dumps(parent[key], ensure_ascii=False))
                return 0
            if action == "set":
                parent[key] = json.loads(values[0])
            elif action == "unset":
                parent.pop(key, None)
            else:
                raise ValueError("Unknown field operation")
        except KeyError:
            if action != "unset":
                raise ValueError("Setting is unavailable: " + path) from None
        print(json.dumps(document, ensure_ascii=False))
    except (OSError, ValueError, KeyError, IndexError, TypeError) as error:
        print(str(error), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
