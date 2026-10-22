set -euo pipefail
bootstrap=$1
subscriber=
cleanup() {
  local code=$?
  if [[ -n "$subscriber" ]]; then kill "$subscriber" 2>/dev/null || true; wait "$subscriber" || true; fi
  if (( code )); then
    for evidence in subscriber.log saved.json result.json; do
      if [[ -f "$evidence" ]]; then cat "$evidence" >&2; fi
    done
  fi
}
trap cleanup EXIT
start_subscriber() {
  : >subscriber.log
  folio-manager-subscriber user "$bootstrap" >subscriber.out 2>subscriber.log &
  subscriber=$!
  for (( attempt=0; attempt<100; attempt++ )); do
    if [[ $(cat subscriber.log) == *'subscriptions ready'* ]]; then return 0; fi
    if ! kill -0 "$subscriber" 2>/dev/null; then cat subscriber.log >&2; return 1; fi
    sleep 0.1
  done
  echo 'Subscriber startup timed out' >&2; return 1
}
stop_subscriber() { kill "$subscriber"; wait "$subscriber"; subscriber=; }
expect_code() {
  local expected=$1 actual=0
  shift
  "$@" >result.json || actual=$?
  [[ "$actual" == "$expected" ]] || { cat result.json >&2; echo "Expected $expected, got $actual" >&2; exit 1; }
  jq -e 'has("status") and has("data") and has("error") and has("taskId")' result.json >/dev/null
}

folio-repository user init "$bootstrap/models/user" "$bootstrap/user.json"
folio doctor --help >/dev/null
folio resume --help >/dev/null
start_subscriber
folio-repository user cfg --export --datastore operational --module folio-environment --format json |
  jq -e '."folio-environment:environment".state.health=="unavailable" and
    ."folio-environment:environment".configuration.saved==true'
jq '."folio-environment:environment".preferences."font-size"=17' "$bootstrap/user.json" >maintenance.json
folio-repository user cfg --import=maintenance.json --module folio-environment --format json
folio-repository user cfg --export --datastore operational --module folio-environment --format json |
  jq -e '."folio-environment:environment".configuration.saved==false'
folio-repository user cfg --copy-from startup --datastore running --module folio-environment
folio --json config show >before.json
jq -e '.status=="success" and (.data.digest|length)==64' before.json
jq '.data.configuration | ."folio-environment:environment".preferences."font-size"=18' before.json >draft.json
folio --json config import draft.json >saved.json
jq -e '.status=="success" and .error==null' saved.json
folio-repository user cfg --export --datastore startup --module folio-environment --format json --defaults report-all |
  jq -e '."folio-environment:environment".preferences."font-size"==18'

# Optimistic editing submits a private document, never a shared candidate lock.
cat >editor.sh <<'EDITOR'
set -euo pipefail
jq '."folio-environment:environment".preferences."font-size"=20' "$1" >concurrent.json
folio --json config import concurrent.json >concurrent-result.json
jq -e '.status=="success"' concurrent-result.json >/dev/null
jq '."folio-environment:environment".preferences."font-size"=19' "$1" >edited.json
cat edited.json >"$1"
EDITOR
export EDITOR="bash $PWD/editor.sh"
expect_code 4 folio --json config edit
jq -e '.status=="conflict"' result.json
drafts=("$XDG_STATE_HOME/folio/drafts/"user-*.json)
[[ ${#drafts[@]} == 1 && $(stat -c %a "${drafts[0]}") == 600 ]]
jq -e '."folio-environment:environment".preferences."font-size"==19' "${drafts[0]}"
folio --json config show | jq -e '.data.configuration."folio-environment:environment".preferences."font-size"==20'
expect_code 2 folio --json modules enable unknown
jq -e '.status=="invalid"' result.json
expect_code 2 folio --json --environment unknown config show

# A genuine durable-write failure must be a failed modeled result, with no save.
chmod 0500 "$XDG_STATE_HOME/folio/configuration"
expect_code 1 folio --json config import draft.json
jq -e '.status=="failure"' result.json
chmod 0700 "$XDG_STATE_HOME/folio/configuration"

stop_subscriber
expect_code 3 folio --json config import draft.json
jq -e '.status=="unavailable"' result.json

# Simulate accepted-before-startup: startup must roll forward before subscribing.
journal=$XDG_STATE_HOME/folio/configuration/transaction.json
jq '.phase="accepted" | .after."folio-environment:environment".preferences."font-size"=22' "$journal" >journal.json
after_digest=$(jq -cS .after journal.json | sha256sum)
jq --arg digest "${after_digest%% *}" '.afterDigest=$digest' journal.json >journal-with-digest.json
cat journal-with-digest.json >"$journal"
start_subscriber
folio --json config show | jq -e '.data.configuration."folio-environment:environment".preferences."font-size"==22'
folio-repository user cfg --export --datastore startup --module folio-environment --format json --defaults report-all |
  jq -e '."folio-environment:environment".preferences."font-size"==22'
stop_subscriber
start_subscriber
folio --json config show | jq -e '.data.configuration."folio-environment:environment".preferences."font-size"==22'
stop_subscriber
jq '.phase="prepared"' "$journal" >prepared.json
cat prepared.json >"$journal"
start_subscriber
folio --json config show | jq -e '.data.configuration."folio-environment:environment".preferences."font-size"==18'
echo 'Real C subscriber: durable commits, private editing, conflicts, errors and restart recovery passed'

# Field edits retain the same optimistic commit and server-side validation.
folio --json config set /preferences/font-size 21 | jq -e '.status=="success"'
folio --json config get /preferences/font-size | jq -e '.data==21'
folio --json config show >before.json
folio --json config set /preferences/appearance '"light"' >/dev/null
jq .data.configuration before.json >stale.json
expect_code 4 folio --json config import stale.json --expected-digest "$(jq -r .data.digest before.json)"
expect_code 2 folio --json config set /preferences/font-size 100
expect_code 2 folio --json config set /modules/terminal/name '"other"'
expect_code 2 folio --json modules disable appearance
folio --json modules list | jq -e 'any(.data[]; .name=="isaac" and .enabled==false and .selected==false)'

# Generic Flathub selections survive real libyang normalization and persistence.
folio --json config show | jq '.data.configuration |
  ."folio-environment:environment".modules |= map(if .name=="applications" then
    ."folio-applications:applications".app += [{name:"org.example.App",ref:"app/org.example.App/x86_64/stable",branch:"stable",selected:true}]
    else . end)' >generic.json
folio --json config import generic.json | jq -e '.status=="success"'
expect_code 4 folio --json apps install org.example.App --ref app/org.example.App/x86_64/beta
folio --json config show | jq -e 'any(.data.configuration."folio-environment:environment".modules[] |
  select(.name=="applications") | ."folio-applications:applications".app[]; .name=="org.example.App" and .selected)'
folio --json config unset /preferences/font-size | jq -e '.status=="success"'
echo 'Field edits, stale draft protection, early prerequisites, catalogue discovery and generic Flathub schema passed'
