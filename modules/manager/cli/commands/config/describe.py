"""Describe desired preferences, their inheritance and observed deployment state."""

import json
import os
from pathlib import Path
import sys

from fields import canonical_path, catalogue, resolve


def read_object(path):
    try:
        value = json.loads(Path(path).read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError, TypeError):
        return {}


def describe(document, digest, observed_path):
    environment = document["folio-environment:environment"]
    defaults = read_object(os.environ["FOLIO_PREFERENCE_DEFAULTS"])
    inherited_origin = "bootstrap-default"
    descriptor = read_object("/run/folio/public/system-descriptor.json")
    if (
        descriptor.get("environment") == environment["name"]
        and descriptor.get("platform") == environment["platform"]
        and isinstance(descriptor.get("preferences"), dict)
    ):
        defaults.update(descriptor["preferences"])
        inherited_origin = "system-default"
    preferences = environment.get("preferences", {})
    if environment["scope"] == "user":
        preferences = {
            key: value for key, value in preferences.items() if key not in {"scheme", "appearance"}
        }
    else:
        # System desired settings inherit the bootstrap choices, not the
        # currently applied descriptor that this deployment will replace.
        defaults = read_object(os.environ["FOLIO_PREFERENCE_DEFAULTS"])
        inherited_origin = "bootstrap-default"
    values = defaults | preferences
    origin = "user-configuration" if environment["scope"] == "user" else "system-configuration"
    observed = read_object(observed_path).get("folio-environment:environment", {})
    state = observed.get("state", {})
    persistence = observed.get("configuration", {})
    applied = state.get("applied-digest")
    current = persistence.get("digest") == digest
    return {
        "configuration": document,
        "digest": digest,
        "preferences": {
            "defaults": defaults,
            "values": values,
            "origins": {key: origin if key in preferences else inherited_origin for key in values},
        },
        "deployment": {
            "appliedDigest": applied,
            "pending": applied != digest if current else None,
            "saved": persistence.get("saved") if current else None,
            "recoveryRequired": persistence.get("recovery-required") if current else None,
        },
    }


def main():
    try:
        action, digest, observed_path, *paths = sys.argv[1:]
        document = json.load(sys.stdin)
        data = describe(document, digest, observed_path)
        if action == "explain":
            path = paths[0]
            definitions = catalogue()
            parts = canonical_path(path, definitions)
            if parts[0] == "preferences":
                value = data["preferences"]["values"][parts[1]]
                origin = data["preferences"]["origins"][parts[1]]
                impacts = []
            else:
                parent, key = resolve(document, path, definitions=definitions)
                value = parent[key]
                origin = "desired-configuration-or-model-default"
                impacts = definitions.get(parts[1], {}).get("impacts", [])
            data = {
                "path": path,
                "canonicalPath": "/" + "/".join(parts),
                "value": value,
                "origin": origin,
                "impacts": impacts,
                "scope": document["folio-environment:environment"]["scope"],
                "digest": digest,
                "deployment": data["deployment"],
            }
        print(json.dumps(data, ensure_ascii=False))
    except (OSError, ValueError, KeyError, IndexError, TypeError) as error:
        print(f"Configuration inspection failed: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
