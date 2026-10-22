#!/usr/bin/env bash
set -euo pipefail
scratch=$(mktemp -d)
trap 'chmod -R u+rwX "$scratch"; rm -rf "$scratch"' EXIT
export XDG_STATE_HOME=$scratch/state FOLIO_SCOPE=user FOLIO_COMMAND=status
export work=$scratch/work
mkdir -p "$work" "$XDG_STATE_HOME/folio"
journal=$XDG_STATE_HOME/folio/offline-coordinator-private.json
printf '{"id":"private","phase":"complete","scope":"system"}\n' >"$journal"
chmod 000 "$journal"
[[ ! -r "$journal" ]] || { echo 'Run this test without root privileges' >&2; exit 1; }
timeout() { return 1; }
finish() { jq -cn --arg status "$1" --argjson data "$2" --arg error "${3:-}" '{status:$status,data:$data,error:$error}'; exit 0; }
export -f timeout finish
output=$(bash -euo pipefail "$DEPLOY_COMMAND")
jq -e '.status=="unavailable" and .data==null' <<<"$output" >/dev/null
# A journal disappearing or becoming unreadable after the access check must
# also produce a valid response rather than terminating the JSON protocol.
chmod 600 "$journal"
printf 'invalid-json\n' >"$journal"
output=$(bash -euo pipefail "$DEPLOY_COMMAND" 2>/dev/null)
jq -e '.status=="unavailable" and .data==null' <<<"$output" >/dev/null
