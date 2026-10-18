#!/usr/bin/env bash
set -euo pipefail
# Uses real isolated repositories and a real subscriber; never selects a profile
# or activates a closure on the development host.
bootstrap=$1 repository=$2 maintenance=$3 manager=$4
test_root=$(mktemp -d /tmp/folio-repository-maintenance.XXXXXX)
export XDG_STATE_HOME=$test_root/state XDG_RUNTIME_DIR=$test_root/runtime
mkdir -p "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
state=$XDG_STATE_HOME/folio
subscriber=
cleanup() {
  [[ -z "$subscriber" ]] || { kill "$subscriber" 2>/dev/null || true; wait "$subscriber" 2>/dev/null || true; }
  printf 'Retained repository maintenance evidence: %s\n' "$test_root" >&2
}
trap cleanup EXIT
repo() { "$repository/bin/folio-repository" user "$@"; }
maintain() { "$maintenance/bin/folio-repository-maintain" user "$@"; }
expect() {
  local expected=$1 actual; shift
  set +e
  "$@" >"$test_root/result.json"
  actual=$?
  set -e
  [[ "$actual" == "$expected" ]]
}
jq --arg account "$(id -un)" '."folio-environment:environment".account=$account' \
  "$bootstrap/user.json" >"$test_root/defaults.json"
repo init "$bootstrap/models/user" "$test_root/defaults.json"
"$manager/bin/folio-manager-subscriber" user "$bootstrap" >"$test_root/subscriber.log" 2>&1 &
subscriber=$!
for (( attempt=0; attempt<100; attempt++ )); do
  if rg -q 'subscriptions ready' "$test_root/subscriber.log"; then break; fi
  sleep 0.1
done
rg -q 'subscriptions ready' "$test_root/subscriber.log"
expect 4 maintain snapshot active "$bootstrap" "$bootstrap"
jq -e '.status=="conflict"' "$test_root/result.json"
kill "$subscriber"; wait "$subscriber"; subscriber=
# Schema changes without a revision must fail without touching either datastore.
maintain snapshot migration "$bootstrap" "$bootstrap" >"$test_root/migration-snapshot.json"
mkdir "$test_root/changed-bootstrap"
cp -rL "$bootstrap/." "$test_root/changed-bootstrap/"
chmod -R u+w "$test_root/changed-bootstrap"
sed -i 's/Foot settings independent of activation/Changed settings independent of activation/' \
  "$test_root/changed-bootstrap/models/user/folio-terminal.yang"
changed_bootstrap=$(nix-store --add "$test_root/changed-bootstrap")
expect 2 maintain prepare migration "$changed_bootstrap"
jq -e '.status=="invalid" and .data.phase=="preparing"' "$test_root/result.json"
[[ ! -e "$state/schema-transaction.json" ]]
# An actual revision whose registered transform fails also leaves live data and
# the snapshot intact. This is a test-only future model, never installed live.
sed -i 's/revision 2026-10-18 {/revision 2026-10-19 {/' \
  "$test_root/changed-bootstrap/models/user/folio-terminal.yang"
mkdir -p "$test_root/failing-migration/bin"
printf '#!/bin/sh\nexit 42\n' >"$test_root/failing-migration/bin/folio-test-migrate"
chmod 0700 "$test_root/failing-migration/bin/folio-test-migrate"
transform=$(nix-store --add "$test_root/failing-migration")/bin/folio-test-migrate
old_hash=$(sha256sum <"$bootstrap/models/user/folio-terminal.yang"); old_hash=${old_hash%% *}
new_hash=$(sha256sum <"$test_root/changed-bootstrap/models/user/folio-terminal.yang"); new_hash=${new_hash%% *}
jq -cn --arg fromSha256 "$old_hash" --arg toSha256 "$new_hash" --arg transform "$transform" \
  '[{module:"folio-terminal",from:"2026-10-18",to:"2026-10-19",fromSha256:$fromSha256,
     toSha256:$toSha256,transform:$transform}]' >"$test_root/changed-bootstrap/migrations.json"
changed_bootstrap=$(nix-store --add "$test_root/changed-bootstrap")
expect 1 maintain prepare migration "$changed_bootstrap"
jq -e '.status=="failure" and .data.phase=="preparing"' "$test_root/result.json"
[[ ! -e "$state/schema-transaction.json" ]]
repo cfg --export --datastore startup --module folio-environment --format json | \
  jq -e '."folio-environment:environment".preferences."font-size"==16'
maintain prepare migration "$bootstrap" >"$test_root/migration-retry.json"
maintain snapshot original "$bootstrap" "$bootstrap" >"$test_root/snapshot.json"
# Reproduce interruption while installing an isolated candidate. Retry retains
# the incomplete tree instead of silently deleting evidence or failing mkdir.
backup=$state/backups/repositories/original
mkdir "$backup/candidate-repository" "$backup/candidate-runtime"
printf 'interrupted candidate\n' >"$backup/candidate-repository/evidence"
maintain prepare original "$bootstrap" >"$test_root/prepare.json"
retained=("$backup"/failed-preparation.*/candidate-repository/evidence)
[[ ${#retained[@]} == 1 && -f "${retained[0]}" ]]
expect 2 maintain bind original "$bootstrap"
jq -e '.status=="invalid"' "$test_root/result.json"
# A metadata fixture tests binding only; its executable deliberately refuses
# activation. No profile is selected and no activation is invoked in this test.
mkdir "$test_root/artifact"
printf '#!/bin/sh\nexit 99\n' >"$test_root/artifact/activate"
chmod 0700 "$test_root/artifact/activate"
digest=$(sha256sum <"$backup/new-running.json"); digest=${digest%% *}
jq -cnS --arg account "$(id -un)" --arg home "$HOME" --arg bootstrap "$bootstrap" --arg digest "$digest" \
  '{format:1,scope:"user",account:$account,home:$home,bootstrap:$bootstrap,configurationDigest:$digest}' \
  >"$test_root/artifact/folio-home.json"
artifact=$(nix-store --add "$test_root/artifact")
maintain bind original "$artifact" >"$test_root/bind.json"
jq '."folio-environment:environment".preferences."font-size"=22' "$test_root/defaults.json" >"$test_root/changed.json"
repo cfg --import="$test_root/changed.json" --datastore running --module folio-environment --format json
repo cfg --copy-from running --datastore startup --module folio-environment
expect 4 maintain install original
jq -e '.status=="conflict"' "$test_root/result.json"
for datastore in startup running; do
  repo cfg --import="$state/backups/repositories/original/$datastore.json" --datastore "$datastore" --module folio-environment --format json
done
maintain install original >"$test_root/install.json"
expect 3 repo cfg --export --module folio-environment --format json
maintain finalize original >"$test_root/finalize.json"
repo cfg --export --module folio-environment --format json | jq -e '."folio-environment:environment".preferences."font-size"==16'
# A failed restoration must leave the maintenance barrier and current repository.
maintain snapshot denied "$bootstrap" "$bootstrap" >"$test_root/denied-snapshot.json"
maintain prepare denied "$bootstrap" >"$test_root/denied-prepare.json"
maintain bind denied "$artifact" >"$test_root/denied-bind.json"
maintain install denied >"$test_root/denied-install.json"
chmod 0500 "$state"
expect 1 maintain restore denied
chmod 0700 "$state"
[[ -f "$state/schema-transaction.json" ]]
maintain restore denied >"$test_root/restore.json"
maintain finalize denied >"$test_root/restored-finalize.json"
# Recover the actual directory-swap boundary with the live repository absent.
mv "$state/sysrepo" "$state/interrupted-repository"
maintain restore original >"$test_root/interrupted-restore.json"
maintain finalize original >"$test_root/interrupted-finalize.json"
repo init "$bootstrap/models/user" "$test_root/defaults.json"
repo cfg --export --datastore startup --module folio-environment --format json | jq -e '."folio-environment:environment".preferences."font-size"==16'
repo cfg --export --datastore running --module folio-environment --format json | jq -e '."folio-environment:environment".preferences."font-size"==16'
[[ -L "$state/backups/repositories/original/bootstrap-root" && -L "$state/backups/repositories/original/artifact-root" ]]
