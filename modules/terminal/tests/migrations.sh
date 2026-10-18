#!/usr/bin/env bash
set -euo pipefail
# Real isolated datastore transitions through the module's shipped hash-bound
# migrations. Closure fixtures refuse activation; guest tests own real effects.
bootstrap=$1 history=$2 repository=$3 maintenance=$4
test_root=$(mktemp -d /tmp/folio-terminal-migrations.XXXXXX)
trap 'echo "Retained migration evidence: $test_root" >&2' EXIT
export XDG_STATE_HOME=$test_root/state XDG_RUNTIME_DIR=$test_root/runtime
mkdir -p "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
state=$XDG_STATE_HOME/folio
repo() { "$repository/bin/folio-repository" user "$@"; }
maintain() { "$maintenance/bin/folio-repository-maintain" user "$@" >"$test_root/last-result.json"; }
historical_bootstrap() {
  local revision=$1 directory=$test_root/bootstrap-$1 hash
  mkdir "$directory"
  cp -rL "$bootstrap/." "$directory/"
  chmod -R u+w "$directory"
  cp "$history/$revision/folio-terminal.yang" "$directory/models/user/folio-terminal.yang"
  hash=$(sha256sum <"$directory/models/user/folio-terminal.yang"); hash=${hash%% *}
  jq --arg hash "$hash" '(.models.user[] | select(.name=="folio-terminal.yang").sha256)=$hash' \
    "$bootstrap/identities.json" >"$directory/identities.json"
  nix-store --add "$directory"
}
fixture() {
  local bootstrap=$1 configuration=$2 directory=$test_root/fixture-$3 digest
  mkdir "$directory"
  printf '#!/bin/sh\nexit 99\n' >"$directory/activate"
  chmod 0700 "$directory/activate"
  digest=$(sha256sum <"$configuration"); digest=${digest%% *}
  jq -cnS --arg account "$(id -un)" --arg home "$HOME" --arg bootstrap "$bootstrap" --arg digest "$digest" \
    '{format:1,workerProtocol:1,scope:"user",account:$account,home:$home,bootstrap:$bootstrap,configurationDigest:$digest}' \
    >"$directory/folio-home.json"
  nix-store --add "$directory"
}
initial=$(historical_bootstrap 2026-10-18)
additive=$(historical_bootstrap 2026-10-19)
jq --arg account "$(id -un)" '."folio-environment:environment".account=$account' "$initial/user.json" >"$test_root/defaults.json"
repo init "$initial/models/user" "$test_root/defaults.json"
maintain snapshot additive "$initial" "$initial"
maintain prepare additive "$additive"
backup=$state/backups/repositories/additive
jq -e '."folio-environment:environment".modules[] | select(.name=="terminal") |
  ."folio-terminal:terminal".foot."opacity-percent"==100' "$backup/new-running.json"
artifact=$(fixture "$additive" "$backup/new-running.json" additive)
maintain bind additive "$artifact"
maintain install additive
maintain finalize additive
repo cfg --export --module folio-environment --format json --defaults report-all >"$test_root/additive.json"
jq '(."folio-environment:environment".modules[] | select(.name=="terminal")."folio-terminal:terminal".foot."opacity-percent")=75' \
  "$test_root/additive.json" >"$test_root/percent.json"
repo cfg --import="$test_root/percent.json" --module folio-environment --format json
repo cfg --copy-from running --datastore startup --module folio-environment
maintain snapshot fraction "$additive" "$artifact"
maintain prepare fraction "$bootstrap"
backup=$state/backups/repositories/fraction
jq -e '."folio-environment:environment".modules[] | select(.name=="terminal") |
  ."folio-terminal:terminal".foot | .opacity=="0.75" and (has("opacity-percent") | not)' "$backup/new-running.json"
artifact=$(fixture "$bootstrap" "$backup/new-running.json" fraction)
maintain bind fraction "$artifact"
maintain install fraction
maintain finalize fraction
for datastore in running startup; do
  repo cfg --export --datastore "$datastore" --module folio-environment --format json | \
    jq -e '."folio-environment:environment".modules[] | select(.name=="terminal") | ."folio-terminal:terminal".foot.opacity=="0.75"'
done
# Retained revisions restore the complete old schema/data identity, without
# inventing a reverse percentage migration or reapplying later desired values.
maintain snapshot retained "$bootstrap" "$artifact"
mkdir -p "$state/deployments/revisions"
configuration=$state/backups/repositories/additive/running.json
digest=$(sha256sum <"$configuration"); digest=${digest%% *}
revision=$state/deployments/revisions/$(printf '1%.0s' {1..64}).json
jq -cnS --arg digest "$digest" --slurpfile configuration "$configuration" --slurpfile identities "$initial/identities.json" \
  '{format:1,scope:"user",workerProtocol:1,configuration:$configuration[0],configurationDigest:$digest,
    models:$identities[0].models.user,tools:$identities[0].tools}' >"$revision"
maintain prepare-revision retained "$initial" "$revision"
artifact=$(fixture "$initial" "$state/backups/repositories/retained/new-running.json" retained)
maintain bind retained "$artifact"
maintain install retained
maintain finalize retained
repo init "$initial/models/user" "$test_root/defaults.json"
repo cfg --export --datastore startup --module folio-environment --format json | \
  jq -e '."folio-environment:environment".modules[] | select(.name=="terminal") |
    ."folio-terminal:terminal".foot | (has("opacity") or has("opacity-percent")) | not'
