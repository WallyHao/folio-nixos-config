"""Describe an immutable candidate without displaying configuration values."""

import hashlib
import json
import os
from pathlib import Path
import sys

candidate, prior, artifact, selected = sys.argv[1:]
source = Path(candidate)
new = json.loads((source / "folio-input.json").read_text())["configuration"][
    "folio-environment:environment"
]
old_source = Path(prior) if prior else None
old = {}
if old_source and (old_source / "folio-input.json").is_file():
    old = json.loads((old_source / "folio-input.json").read_text())["configuration"][
        "folio-environment:environment"
    ]


def files(root):
    if not root or not root.is_dir():
        return {}
    result = {}
    for entry in root.rglob("*"):
        relative = entry.relative_to(root).as_posix()
        if relative == "folio-input.json" or not entry.is_file():
            continue
        result[relative] = hashlib.sha256(entry.read_bytes()).hexdigest()
    return result


before, after = files(old_source), files(source)
changes = []
for name in sorted(before.keys() | after.keys()):
    if before.get(name) == after.get(name):
        continue
    parts = name.split("/")
    module = parts[1] if len(parts) > 2 and parts[0] == "modules" else None
    changes.append(
        {
            "path": name,
            "module": module,
            "shared": module in (None, "manager", "sysrepo"),
            "kind": "added"
            if name not in before
            else "removed"
            if name not in after
            else "modified",
        }
    )
a = {m["name"]: m for m in old.get("modules", [])}
b = {m["name"]: m for m in new.get("modules", [])}
modules = sorted(name for name in a.keys() | b.keys() if a.get(name) != b.get(name))
settings = sorted(
    key for key in old.keys() | new.keys() if key != "modules" and old.get(key) != new.get(key)
)
catalogue_path = os.environ.get("FOLIO_CATALOGUE")
catalogue = json.loads(Path(catalogue_path).read_text()) if catalogue_path else {}
affected = set(modules) | {item["module"] for item in changes if item["module"]}
impacts = [
    {"module": name, "message": message}
    for name in sorted(affected)
    for message in catalogue.get(name, {}).get("impacts", [])
]
disabled = sorted(
    name for name, entry in a.items() if entry.get("enabled") and not b.get(name, {}).get("enabled")
)
# Only public preference fields are eligible for value previews. Module values
# and arbitrary strings are never copied into this presentation record.
safe = {"appearance", "font-size", "font-family", "scheme"}
preferences = [
    {
        "field": key,
        "before": old.get("preferences", {}).get(key),
        "after": new.get("preferences", {}).get(key),
    }
    for key in sorted(safe)
    if old.get("preferences", {}).get(key) != new.get("preferences", {}).get(key)
]
kernel_before, kernel_after = Path(selected or "/nonexistent") / "kernel", Path(artifact) / "kernel"
kernel_changed = (
    kernel_before.exists()
    and kernel_after.exists()
    and kernel_before.resolve() != kernel_after.resolve()
)
print(
    json.dumps(
        {
            "changed": artifact != selected,
            "firstDeployment": not selected,
            "configurationModules": modules,
            "configurationFields": settings,
            "preferenceChanges": preferences,
            "impacts": impacts,
            "disabledModules": disabled,
            "kernelChanged": kernel_changed,
            "sourceChanges": changes,
            "targetArtifact": artifact,
            "baselineArtifact": selected or None,
        },
        sort_keys=True,
    )
)
