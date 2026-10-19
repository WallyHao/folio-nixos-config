#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Adoption fixture failed at line $LINENO" >&2' ERR
bootstrap=$1 old=$2 legacy=$3 source=$4 switcher=$5
state=$HOME/.local/state/folio
profile=$HOME/.local/state/nix/profiles/home-manager
mkdir -p "$(dirname "$profile")"
nix-env --profile "$profile" --set "$legacy"
"$legacy/activate" --driver-version 1
session_pid=$(systemctl --user show niri.service --property=MainPID --value)
[[ "$session_pid" != 0 ]]
work=$(mktemp -d)
jq -cS .configuration "$source/folio-input.json" >"$work/desired.json"
cmp "$work/desired.json" "$state/backups/repositories/reorganize/new-running.json"
frozen=$source
# Wrong-account metadata must be rejected before touching the repository/profile.
mkdir "$work/wrong"
ln -s "$legacy/activate" "$work/wrong/activate"
printf '%s\n' '{"protocolVersion":1,"schemaVersion":1,"user":"someone-else","home":"/home/folio"}' >"$work/wrong/sylphy-home.json"
wrong=$(nix-store --add "$work/wrong")
nix-env --profile "$profile" --set "$wrong"
code=0
folio-manager-maintain user "$old" adopt reject-account "$frozen" || code=$?
[[ "$code" == 4 && ! -e "$state/backups/repositories/reject-account" ]]
[[ $(readlink -f "$profile") == "$wrong" ]]
nix-env --profile "$profile" --set "$legacy"
folio-manager-maintain user "$old" adopt legacy-adoption "$frozen"
backup=$state/backups/repositories/legacy-adoption
jq -e '.legacyAdoption==true' "$backup/transaction.json"
jq -e '.phase=="complete"' "$backup/coordinator.json"
[[ $(readlink -f "$backup/artifact-root") == "$legacy" ]]
[[ $(readlink -f "$profile") != "$legacy" ]]
jq -e '.account=="folio" and .home=="/home/folio"' "$profile/folio-home.json"
systemctl --user is-active folio-manager.service
[[ $(systemctl --user show niri.service --property=MainPID --value) == "$session_pid" ]]
mkdir "$work/no-previous-units"
"$switcher/bin/sd-switch" --dry-run --old-units "$work/no-previous-units" \
  --new-units "$profile/home-files/.config/systemd/user" >"$work/first-unit-adoption.log"
if grep -E '^(Stopping|Restarting) units:.*niri.service' "$work/first-unit-adoption.log"; then
  exit 1
fi
setsid --wait env ZDOTDIR="$HOME/.config/zsh" zsh -ic 'whence -w ll compdef; print -r -- "history=$HISTFILE"; (( $+functions[ll] && $+functions[compdef] )) && [[ $HISTFILE == "$HOME/.local/state/folio/zsh/history" ]]' </dev/null
folio --json status | jq -e '.status=="success" and .data.health=="healthy" and .data.offline!=true'
[[ $("$profile/home-path/bin/git" -C "$work" config --get user.name) == 'Fixture Contributor' ]]
[[ $("$profile/home-path/bin/git" -C "$work" config --get user.email) == fixture@example.invalid ]]
folio-repository user cfg --export --module folio-environment --format json |
  jq -e '."folio-environment:environment".modules | any(.[]; .name=="agents") and all(.[]; .name!="git" and .name!="codex")'
for path in .codex .config/gh .dsh; do
  grep -Fx fixture-private-state "$HOME/$path/personal-state"
done
# Explicit recovery restores the independently retained legacy generation and
# its old repository, then the same source can be adopted with a fresh ID.
folio-manager-maintain user "$bootstrap" restore legacy-adoption
[[ $(readlink -f "$profile") == "$legacy" ]]
[[ ! -e "$state/deployments/current.json" ]]
cmp "$state/model-identity" "$backup/model-identity"
folio-repository user cfg --export --module folio-environment --format json |
  jq -e '."folio-environment:environment".modules | any(.[]; .name=="codex") and any(.[]; .name=="git")'
folio-manager-maintain user "$old" adopt legacy-retry "$frozen"
[[ $(systemctl --user show niri.service --property=MainPID --value) == "$session_pid" ]]
folio --json status | jq -e '.status=="success" and .data.health=="healthy" and .data.offline!=true'
