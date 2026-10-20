#!/usr/bin/env bash
set -euo pipefail
bootstrap=$1 old=$2 repository=$3 maintenance=$4
# Independent disposable repository, never the active user's subscriber state.
export XDG_STATE_HOME=$HOME/pi-migration-state XDG_RUNTIME_DIR=$HOME/pi-migration-runtime
mkdir -p "$XDG_RUNTIME_DIR"
state=$XDG_STATE_HOME/folio
repo() { "$repository/bin/folio-repository" user "$@"; }
maintain() { "$maintenance/bin/folio-repository-maintain" user "$@"; }
fixture() {
  local seed=$1 configuration=$2 directory digest
  directory=$(mktemp -d)
  printf '#!/bin/sh\nexit 99\n' >"$directory/activate"
  chmod 0700 "$directory/activate"
  digest=$(sha256sum <"$configuration"); digest=${digest%% *}
  jq -cnS --arg bootstrap "$seed" --arg digest "$digest" \
    '{format:1,workerProtocol:1,scope:"user",account:"folio",home:"/home/folio",
      bootstrap:$bootstrap,configurationDigest:$digest}' >"$directory/folio-home.json"
  nix-store --add "$directory"
}
repo init "$old/models/user" "$old/user.json"
repo cfg --export --module folio-environment --format json --defaults report-all | jq -cS . >"$HOME/pi-before.json"
before=$(fixture "$old" "$HOME/pi-before.json")
maintain snapshot replace-dsh "$old" "$before"
bad=$(mktemp -d)
cp -RL "$bootstrap/." "$bad/"
chmod -R u+w "$bad"
jq 'map(if .module=="folio-agents" then .fromSha256=("0" * 64) else . end)' \
  "$bootstrap/migrations.json" >"$bad/migrations.json"
bad=$(nix-store --add "$bad")
code=0
maintain prepare replace-dsh "$bad" || code=$?
[[ "$code" == 3 ]]
repo cfg --export --module folio-environment --format json --defaults report-all | jq -cS . >"$HOME/pi-rejected.json"
cmp "$HOME/pi-before.json" "$HOME/pi-rejected.json"
maintain prepare replace-dsh "$bootstrap"
backup=$state/backups/repositories/replace-dsh
for datastore in running startup; do
  jq -e '."folio-environment:environment".modules | any(.[];
    .name=="agents" and .enabled and (."folio-agents:agents" |
      .pi.enabled and .codex.enabled==false and .codex.theme==false and
      .codex."shell-completion"==false and (has("dsh")|not)))' "$backup/new-$datastore.json"
done
after=$(fixture "$bootstrap" "$backup/new-running.json")
maintain bind replace-dsh "$after"
maintain install replace-dsh
maintain finalize replace-dsh
for datastore in running startup; do
  repo cfg --export --datastore "$datastore" --module folio-environment --format json |
    jq -e '."folio-environment:environment".modules | any(.[];
      .name=="agents" and (."folio-agents:agents" | .pi.enabled and (has("dsh")|not)))'
done
# Restore the exact retained schema/data, not a reverse transform.
maintain restore replace-dsh
repo init "$old/models/user" "$old/user.json"
maintain finalize replace-dsh
repo cfg --export --module folio-environment --format json --defaults report-all | jq -cS . >"$HOME/pi-restored.json"
cmp "$HOME/pi-before.json" "$HOME/pi-restored.json"
