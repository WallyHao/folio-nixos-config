#!/usr/bin/env bash
set -euo pipefail

root=${FOLIO_REPOSITORY:-${PRJ_ROOT:-$PWD}}
cd -- "$root"
if [[ ! -f flake.nix || ! -d modules ]]; then
  echo 'Run from the Folio checkout, or set FOLIO_REPOSITORY to its path.' >&2
  exit 2
fi
root=$PWD
mode=${1:-fast}
if (( $# )); then shift; fi
if [[ "$mode" == format && ${1:-} == --check ]]; then mode=style; shift; fi
if (( $# )); then echo 'Usage: folio-check [style|format|fast|integration|release]' >&2; exit 2; fi

sources() {
  find modules -type d \( -name node_modules -o -name result -o -name 'result-*' -o -name __pycache__ \) \
    -prune -o -type f -name "$1" -print0
}

case "$mode" in
  style|format)
    mapfile -d '' -t nix_files < <(sources '*.nix')
    mapfile -d '' -t lua_files < <(sources '*.lua')
    if [[ "$mode" == format ]]; then
      nixfmt flake.nix "${nix_files[@]}"
      ruff format modules
      if (( ${#lua_files[@]} )); then stylua "${lua_files[@]}"; fi
    else
      nixfmt --check flake.nix "${nix_files[@]}"
      ruff format --check modules
      ruff check modules
      if (( ${#lua_files[@]} )); then stylua --check "${lua_files[@]}"; fi
      while IFS= read -r -d '' file; do bash -n "$file"; done < <(sources '*.sh')
      shellcheck "${BASH_SOURCE[0]}"
      if [[ -e .git ]]; then git diff --check; fi
    fi
    exit 0 ;;
  fast|integration|release) ;;
  *) echo 'Usage: folio-check [style|format|fast|integration|release]' >&2; exit 2 ;;
esac

if [[ "$mode" == release ]]; then
  : "${FOLIO_TEST_CACHE:?release requires an isolated public Flatpak cache store path}"
  : "${FOLIO_TEST_PLANS:?release requires matching retained application plans}"
  export FOLIO_TEST_SOURCE="path:$root"
  nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths --impure --expr '
    let
      f = builtins.getFlake (builtins.getEnv "FOLIO_TEST_SOURCE");
      fixtureInputs = {
        cache = builtins.storePath (builtins.getEnv "FOLIO_TEST_CACHE");
        plans = builtins.storePath (builtins.getEnv "FOLIO_TEST_PLANS");
      };
    in map (name:
      let check = builtins.getAttr name f.checks.x86_64-linux;
      in if builtins.elem name [ "applications" "desktop" "integrated-release" ]
        then check.override fixtureInputs else check
    ) f.lib.folio.checkGroups.release'
  exit 0
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
nix eval --json --no-update-lock-file "path:$root#lib.folio.checkGroups.$mode" >"$work/checks.json"
mapfile -t checks < <(jq -r '.[]' "$work/checks.json")
targets=()
for check in "${checks[@]}"; do targets+=("path:$root#checks.x86_64-linux.$check"); done
nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths "${targets[@]}"
