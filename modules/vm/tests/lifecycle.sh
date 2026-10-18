#!/usr/bin/env bash
set -euo pipefail
# Run as an ordinary user with a working systemd user manager and KVM access.
# Arguments are immutable package paths followed by the immutable source snapshot.
bootstrap=$1 repository=$2 cli=$3 subscriber=$4 tools=$5 source_path=$6
test_root=$(mktemp -d /tmp/folio-vm-lifecycle.XXXXXX)
original_runtime=${XDG_RUNTIME_DIR:?}
export XDG_STATE_HOME=$test_root/state XDG_RUNTIME_DIR=$test_root/runtime
mkdir -p "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR/systemd"
chmod 0700 "$test_root" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
ln -s "$original_runtime/systemd/private" "$XDG_RUNTIME_DIR/systemd/private"
ln -s "$original_runtime/bus" "$XDG_RUNTIME_DIR/bus"
export DBUS_SESSION_BUS_ADDRESS=unix:path=$original_runtime/bus
job_id=gate-$(date +%s)
subscriber_pid=
cleanup() {
  [[ -z "$subscriber_pid" ]] || { kill "$subscriber_pid" 2>/dev/null || true; wait "$subscriber_pid" 2>/dev/null || true; }
  printf 'Retained VM lifecycle evidence: %s\n' "$test_root" >&2
}
trap cleanup EXIT
"$repository/bin/folio-repository" user init "$bootstrap/models/user" "$bootstrap/user.json"
"$subscriber/bin/folio-vm-subscriber" >"$test_root/subscriber.log" 2>&1 &
subscriber_pid=$!
for (( attempt=0; attempt<100; attempt++ )); do
  if rg -q 'subscriptions ready' "$test_root/subscriber.log"; then break; fi
  sleep 0.1
done
rg -q 'subscriptions ready' "$test_root/subscriber.log"
"$cli/bin/folio" --json --no-wait vm build "$job_id" "$source_path" >"$test_root/submission.json"
kill "$subscriber_pid"; wait "$subscriber_pid"
"$subscriber/bin/folio-vm-subscriber" >>"$test_root/subscriber.log" 2>&1 &
subscriber_pid=$!
sleep 1
deadline=$((SECONDS + 1860))
while (( SECONDS < deadline )); do
  "$cli/bin/folio" --json vm status "$job_id" >"$test_root/status.json"
  phase=$(jq -r .data.phase "$test_root/status.json")
  case "$phase" in ready) break ;; failed|interrupted) cat "$test_root/status.json"; exit 1 ;; esac
  sleep 1
done
[[ "$phase" == ready ]]
"$cli/bin/folio" --json vm start "$job_id" >"$test_root/start.json"
if "$cli/bin/folio" --json vm cleanup "$job_id" >"$test_root/refused-cleanup.json"; then exit 1; fi
jq -e '.status=="conflict"' "$test_root/refused-cleanup.json"
serial=$XDG_STATE_HOME/folio/vm/jobs/$job_id/serial.log
deadline=$((SECONDS + 120))
while (( SECONDS < deadline )); do
  if rg -q 'login:' "$serial"; then break; fi
  sleep 1
done
rg -q 'login:' "$serial"
"$cli/bin/folio" --json vm stop "$job_id" >"$test_root/stop.json"
"$tools/bin/folio-vm-tool" status "$job_id" >"$test_root/final.json"
jq -e '.data.phase=="stopped" and .data.exitCode==0' "$test_root/final.json"
"$cli/bin/folio" --json vm cleanup "$job_id" >"$test_root/cleanup.json"
[[ ! -e "$XDG_STATE_HOME/folio/vm/jobs/$job_id" ]]
find "$XDG_STATE_HOME/folio/vm/logs" -name serial.log -exec rg -l 'login:' {} \;
