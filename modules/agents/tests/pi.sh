#!/usr/bin/env bash
set -euo pipefail
pi=$1 fixture=$2
work=$(mktemp -d)
export FOLIO_PI_CONFIG_DIR=$work/checkout/config
export PI_CODING_AGENT_DIR=$work/private
mkdir -p "$FOLIO_PI_CONFIG_DIR/extensions" "$FOLIO_PI_CONFIG_DIR/packages/local/prompts" "$work/project"
cp "$fixture" "$FOLIO_PI_CONFIG_DIR/extensions/fixture.ts"
printf '%s\n' '{"theme":"system","defaultProvider":"folio-fixture","defaultModel":"fixture","defaultProjectTrust":"always"}' >"$FOLIO_PI_CONFIG_DIR/settings.json"
printf 'Local package fixture\n' >"$FOLIO_PI_CONFIG_DIR/packages/local/prompts/fixture.md"
printf '%s\n' '{"name":"folio-local-fixture","pi":{"prompts":["./prompts"]}}' >"$FOLIO_PI_CONFIG_DIR/packages/local/package.json"
cd "$work/project"
"$pi/bin/pi" install "$FOLIO_PI_CONFIG_DIR/packages/local"
jq -e '.packages | length==1' "$FOLIO_PI_CONFIG_DIR/settings.json"
"$pi/bin/pi" list | grep -F 'packages/local'
timeout --kill-after=2 30 "$pi/bin/pi" --offline -p /folio-fixture >"$work/loaded"
jq -e '.theme=="dark"' "$FOLIO_PI_CONFIG_DIR/settings.json"
test -L "$PI_CODING_AGENT_DIR/settings.json"
grep -Fx loaded "$PI_CODING_AGENT_DIR/fixture-loaded"
test -n "$(find "$PI_CODING_AGENT_DIR/sessions" -name '*.jsonl' -print -quit)"
test ! -e "$FOLIO_PI_CONFIG_DIR/sessions"
test ! -e "$FOLIO_PI_CONFIG_DIR/auth.json"
test ! -e "$HOME/.pi"
"$pi/bin/pi" remove "$FOLIO_PI_CONFIG_DIR/packages/local"
jq -e '(.packages // []) | length==0' "$FOLIO_PI_CONFIG_DIR/settings.json"
mkdir -p .pi/extensions
printf '%s\n' 'import {writeFileSync} from "node:fs"; export default function(pi:any) { pi.on("session_start", () => {writeFileSync("project-loaded", "yes");}); }' >.pi/extensions/project.ts
timeout --kill-after=2 30 "$pi/bin/pi" --offline -p /folio-fixture >/dev/null
test -f project-loaded
if FOLIO_PI_CONFIG_DIR=$work/missing "$pi/bin/pi" --version >"$work/missing.log" 2>&1; then exit 1; fi
grep -F 'configuration directory does not exist' "$work/missing.log"
mkdir -p "$work/conflict"
printf 'keep\n' >"$work/conflict/settings.json"
if PI_CODING_AGENT_DIR=$work/conflict "$pi/bin/pi" --version >"$work/conflict.log" 2>&1; then exit 1; fi
grep -Fx keep "$work/conflict/settings.json"
test ! -e "$work/conflict/models.json"
cp -R "$FOLIO_PI_CONFIG_DIR" "$work/next-config"
FOLIO_PI_CONFIG_DIR=$work/next-config "$pi/bin/pi" --version
test "$(readlink "$PI_CODING_AGENT_DIR/settings.json")" = "$work/next-config/settings.json"
printf 'private-state\n' >"$PI_CODING_AGENT_DIR/auth.json"
"$pi/bin/pi" --version
grep -Fx private-state "$PI_CODING_AGENT_DIR/auth.json"
if PI_CODING_AGENT_DIR=$FOLIO_PI_CONFIG_DIR/private "$pi/bin/pi" --version >"$work/nested.log" 2>&1; then exit 1; fi
grep -F 'runtime state must be outside' "$work/nested.log"
