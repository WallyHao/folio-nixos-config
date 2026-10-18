#!/usr/bin/env bash
set -euo pipefail

repository=$(realpath -e -- "${1:?Repository path is required}")
bootstrap=$(realpath -e -- "${2:?Bootstrap path is required}")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/source"
cp -R "$repository/modules" "$repository/flake.nix" "$repository/flake.lock" "$work/source/"
jq '."folio-environment:environment".preferences."font-size" = 18' "$bootstrap/user.json" >"$work/user.json"
folio-prepare-input "$work/user.json" "$bootstrap" >"$work/source/folio-input.json"
rendered=$(nix eval --offline --no-update-lock-file --raw \
  "path:$work/source#homeConfigurations.folio.config.xdg.configFile.\"foot/foot.ini\".text")
case "$rendered" in
  *'font=Maple Mono NF CN:size=18'*) ;;
  *) echo 'Frozen preference did not reach the Foot renderer' >&2; exit 1 ;;
esac

jq '.configuration."folio-environment:environment".preferences."font-size" = 19' \
  "$work/source/folio-input.json" >"$work/invalid.json"
mv "$work/invalid.json" "$work/source/folio-input.json"
if nix eval --offline --no-update-lock-file --raw \
    "path:$work/source#homeConfigurations.folio.activationPackage.drvPath" >"$work/out" 2>"$work/error"; then
  echo 'Tampered frozen input was accepted' >&2; exit 1
fi
case "$(cat "$work/error")" in
  *'invalid frozen input'*) ;;
  *) cat "$work/error" >&2; exit 1 ;;
esac

jq '."folio-environment:environment".modules += [{name:"unknown",enabled:false}]' \
  "$work/user.json" >"$work/unknown.json"
folio-prepare-input "$work/unknown.json" "$bootstrap" >"$work/source/folio-input.json"
if nix eval --offline --no-update-lock-file --raw \
    "path:$work/source#homeConfigurations.folio.activationPackage.drvPath" >"$work/out" 2>"$work/error"; then
  echo 'Unknown disabled module was accepted' >&2; exit 1
fi
case "$(cat "$work/error")" in
  *'unknown module unknown'*) ;;
  *) cat "$work/error" >&2; exit 1 ;;
esac
echo 'Pure frozen input rendering, digest validation and disabled-module validation passed'
