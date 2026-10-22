"""Validate installed requirements with the pinned upstream uv overrides applied."""
import importlib.metadata as metadata
import json
import os
from pathlib import Path
import sys
import tomllib

from packaging.requirements import Requirement
from packaging.specifiers import SpecifierSet
from packaging.utils import canonicalize_name

project = tomllib.loads(Path("pyproject.toml").read_text())
overrides = {canonicalize_name(req.name): req for req in
             map(Requirement, project["tool"]["uv"]["override-dependencies"])}
installed = {canonicalize_name(dist.metadata["Name"]): dist for dist in metadata.distributions()}
errors = []
profile = json.loads(Path(os.environ["ISAAC_VERSIONS"]).read_text()) if "ISAAC_VERSIONS" in os.environ else {}
for name, expected in profile.get("compatibilityPins", {}).items():
    if name not in installed or installed[name].version != expected:
        errors.append(f"Compatibility overlay requires {name}=={expected}")
used = set()
for name, dist in installed.items():
    python = dist.metadata.get("Requires-Python")
    if python and ".".join(map(str, sys.version_info[:3])) not in SpecifierSet(python):
        errors.append(f"{name}: Python {python} required")
    for raw in dist.requires or []:
        requirement = Requirement(raw)
        if requirement.marker and not requirement.marker.evaluate({"extra": ""}):
            continue
        target = canonicalize_name(requirement.name)
        effective = overrides.get(target, requirement)
        other = installed.get(target)
        if other is None:
            errors.append(f"{name}: missing {effective}")
        elif effective.specifier and other.version not in effective.specifier:
            errors.append(f"{name}: requires {effective}, installed {other.version}")
        elif target in overrides and requirement.specifier and other.version not in requirement.specifier:
            used.add(f"{name}: {requirement} -> {effective}")
result = {"stage": "dependencies", "status": "failed" if errors else "passed",
          "distributionCount": len(installed), "upstreamOverridesUsed": sorted(used), "errors": errors}
print(json.dumps(result, indent=2))
if errors:
    sys.exit(1)
