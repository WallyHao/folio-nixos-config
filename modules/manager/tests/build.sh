#!/usr/bin/env bash
set -euo pipefail

# Run in nix develop against the real user service manager. This test only builds;
# it never submits activation or writes to the login user's configuration paths.
repository=$(realpath -e -- "${1:?Repository path is required}")
bootstrap=$(realpath -e -- "${2:?Bootstrap path is required}")
test_root=$(mktemp -d /tmp/folio-build-test.XXXXXX)
original_runtime=${XDG_RUNTIME_DIR:?A real user service manager is required}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$original_runtime/bus}
export HOME=$test_root/home XDG_STATE_HOME=$test_root/state XDG_RUNTIME_DIR=$test_root/run
mkdir -p "$HOME" "$XDG_RUNTIME_DIR" "$test_root/bootstrap" "$test_root/source"
# systemctl's local user transport uses systemd/private independently of the
# D-Bus address. Share only the real service-manager sockets, not Folio state.
mkdir "$XDG_RUNTIME_DIR/systemd"
ln -s "$original_runtime/systemd/private" "$XDG_RUNTIME_DIR/systemd/private"
ln -s "$original_runtime/bus" "$XDG_RUNTIME_DIR/bus"
subscriber=
task_id=
cleanup() {
  local code=$?
  if [[ -n "$subscriber" ]]; then kill "$subscriber" 2>/dev/null || true; wait "$subscriber" || true; fi
  if [[ -n "$task_id" ]]; then
    journalctl --user -u "folio-task-$task_id.service" --no-pager >"$test_root/worker.log" || true
    systemctl --user stop "folio-task-$task_id.service" 2>/dev/null || true
  fi
  if (( code )); then
    cat "$test_root/subscriber.log" >&2
    [[ ! -f "$test_root/worker.log" ]] || cat "$test_root/worker.log" >&2
  fi
  echo "Build integration evidence: $test_root"
}
trap cleanup EXIT
ln -s "$bootstrap/models" "$test_root/bootstrap/models"
cp "$bootstrap/identities.json" "$bootstrap/catalogue.json" "$test_root/bootstrap/"
jq --arg account "$(id -un)" '."folio-environment:environment".account=$account' \
  "$bootstrap/user.json" >"$test_root/bootstrap/user.json"
jq --arg account "$(id -un)" --arg home "$HOME" --argjson uid "$(id -u)" \
  '.users=[{name:$account,home:$home,uid:$uid,groups:[],"login-shell":"bash"}] | .origin="isolated-build-fixture"' \
  "$bootstrap/system-descriptor.json" >"$test_root/bootstrap/system-descriptor.json"
cp -R "$repository/modules" "$repository/flake.nix" "$repository/flake.lock" "$test_root/source/"
bootstrap=$test_root/bootstrap
folio-repository user init "$bootstrap/models/user" "$bootstrap/user.json"
start_subscriber() {
  : >"$test_root/subscriber.log"
  folio-manager-subscriber user "$bootstrap" >"$test_root/subscriber.out" 2>"$test_root/subscriber.log" &
  subscriber=$!
  for (( attempt=0; attempt<100; attempt++ )); do
    [[ $(cat "$test_root/subscriber.log") != *'subscriptions ready'* ]] || return 0
    kill -0 "$subscriber" || return 1
    sleep 0.1
  done
  return 1
}
start_subscriber
folio --json status >"$test_root/status.json"
jq . "$test_root/status.json"
jq -e '.data.health=="unavailable" and .data.applied==null' "$test_root/status.json"
ln -s /etc/passwd "$test_root/source/modules/escape"
code=0
folio --json --user plan --source "$test_root/source" >"$test_root/escape.json" || code=$?
[[ "$code" == 2 ]]
rm "$test_root/source/modules/escape"
folio --json --user plan --source "$test_root/source" >"$test_root/plan.json"
plan_id=$(jq -er .data.planId "$test_root/plan.json")
snapshot=$(jq -er .data.plan.source "$test_root/plan.json")
test -f "$snapshot/flake.lock"
printf '%s\n' 'throw "Mutable source must not be evaluated"' >"$test_root/source/modules/terminal/src/foot.nix"
folio --json --no-wait build "$plan_id" --request-id build-fixture >"$test_root/submitted.json"
task_id=$(jq -er .taskId "$test_root/submitted.json")
folio --json --no-wait build "$plan_id" --request-id build-fixture |
  jq -e --arg id "$task_id" '.taskId==$id'
kill "$subscriber"; wait "$subscriber"; subscriber=

record=$XDG_STATE_HOME/folio/deployments/tasks/$task_id.json
for (( attempt=0; attempt<600; attempt++ )); do
  phase=$(jq -er .phase "$record")
  case "$phase" in succeeded) break ;; failed|interrupted) cat "$record" >&2; exit 1 ;; esac
  sleep 1
done
[[ "$phase" == succeeded ]]
start_subscriber
folio --json status "$task_id" | jq -e '.data.task.phase=="succeeded"'
folio --json status | jq -e '.data.applied==null and .data.health=="unavailable"'
folio --json config show | jq '.data.configuration | ."folio-environment:environment".preferences."font-size"=18' >"$test_root/changed.json"
folio --json config import "$test_root/changed.json" >/dev/null
code=0
folio --json --no-wait apply "$plan_id" >"$test_root/stale.json" || code=$?
[[ "$code" == 4 ]]
jq -e '.status=="conflict"' "$test_root/stale.json"
echo 'Immutable snapshot, real independent build worker, idempotency, unapplied state and stale-plan rejection passed'
