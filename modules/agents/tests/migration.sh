#!/usr/bin/env bash
set -euo pipefail
bootstrap=$1 old=$2 repository=$3 maintenance=$4
export XDG_STATE_HOME="$HOME/.local/state"
state=$XDG_STATE_HOME/folio
repo() { "$repository/bin/folio-repository" user "$@"; }
maintain() { "$maintenance/bin/folio-repository-maintain" user "$@"; }
mkdir -p "$HOME/.codex" "$HOME/.config/gh" "$HOME/.dsh"
printf 'fixture-private-state\n' >"$HOME/.codex/personal-state"
cp "$HOME/.codex/personal-state" "$HOME/.config/gh/personal-state"
cp "$HOME/.codex/personal-state" "$HOME/.dsh/personal-state"
repo init "$old/models/user" "$old/user.json"
repo cfg --export --module folio-environment --format json --defaults report-all | jq -cS . >"$HOME/before.json"
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
before=$(fixture "$old" "$HOME/before.json")
maintain snapshot reorganize "$old" "$before"
# A stale/forged source hash must be rejected before either live datastore changes.
bad=$(mktemp -d)
cp -RL "$bootstrap/." "$bad/"
chmod -R u+w "$bad"
jq 'map(if .module=="folio-codex" then .fromSha256=("0" * 64) else . end)' \
  "$bootstrap/migrations.json" >"$bad/migrations.json"
bad=$(nix-store --add "$bad")
code=0
maintain prepare reorganize "$bad" >"$HOME/rejected.json" || code=$?
[[ "$code" == 3 ]]
repo cfg --export --module folio-environment --format json --defaults report-all |
  jq -cS . >"$HOME/after-rejection.json"
cmp "$HOME/before.json" "$HOME/after-rejection.json"
maintain prepare reorganize "$bootstrap"
backup=$state/backups/repositories/reorganize
jq -e '."folio-environment:environment".modules |
  all(.[]; .name!="git" and .name!="codex") and
  any(.[]; .name=="agents" and .enabled and
    ."folio-agents:agents".codex.theme==false and
    ."folio-agents:agents".codex."shell-completion"==false and
    ."folio-agents:agents".pi.enabled==false) and
  any(.[]; .name=="terminal" and (."folio-terminal:terminal".git |
    .enabled and ."user-name"=="Fixture Contributor" and
    ."user-email"=="fixture@example.invalid" and ."github-cli"==false and
    ."default-branch"=="trunk" and ."pull-rebase"==false))' "$backup/new-running.json"
after=$(fixture "$bootstrap" "$backup/new-running.json")
maintain bind reorganize "$after"
maintain install reorganize
maintain finalize reorganize
for datastore in running startup; do
  repo cfg --export --datastore "$datastore" --module folio-environment --format json |
    jq -e '."folio-environment:environment".modules | any(.[]; .name=="agents") and all(.[]; .name!="git" and .name!="codex")'
done
repo ctl --list | grep folio-agents
if repo ctl --list | grep -E 'folio-(codex|git)[[:space:]]'; then exit 1; fi
# Restore the complete retained identity; never invent a reverse data transform.
maintain snapshot restore-old "$bootstrap" "$after"
mkdir -p "$state/deployments/revisions"
revision=$state/deployments/revisions/$(printf '2%.0s' {1..64}).json
digest=$(sha256sum <"$HOME/before.json"); digest=${digest%% *}
jq -cnS --arg digest "$digest" --slurpfile configuration "$HOME/before.json" \
  --slurpfile identities "$old/identities.json" \
  '{format:1,scope:"user",workerProtocol:1,configuration:$configuration[0],configurationDigest:$digest,
    models:$identities[0].models.user,tools:$identities[0].tools}' >"$revision"
maintain prepare-revision restore-old "$old" "$revision"
maintain bind restore-old "$before"
maintain install restore-old
maintain finalize restore-old
repo init "$old/models/user" "$old/user.json"
repo cfg --export --format json --module folio-environment |
  jq -e '."folio-environment:environment".modules | any(.[]; .name=="git") and any(.[]; .name=="codex")'
for path in .codex .config/gh .dsh; do
  grep -Fx fixture-private-state "$HOME/$path/personal-state"
done
