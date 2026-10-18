#!/usr/bin/env bash
set -euo pipefail
runtime=$1 bootstrap=$2
test_root=$(mktemp -d /tmp/folio-cleanup.XXXXXX)
trap 'echo "Retained cleanup evidence: $test_root" >&2' EXIT
export XDG_STATE_HOME=$test_root/state
state=$XDG_STATE_HOME/folio
mkdir -p "$state/deployments/"{plans,builds,revisions,tasks,roots} "$state/backups/repositories/retained"
ids=()
for number in {1..6}; do
  id=$(printf "$number%.0s" {1..64}); ids+=("$id")
  mkdir "$test_root/source-$number"
  printf '%s\n' "$number" >"$test_root/source-$number/identity"
  source_path=$(nix-store --add "$test_root/source-$number")
  jq -cnS --arg source "$source_path" --arg bootstrap "$bootstrap" \
    '{format:1,source:$source,beforeProfile:$bootstrap,priorDeployment:{artifact:$bootstrap}}' >"$state/deployments/plans/$id.json"
  nix-store --realise "$source_path" --add-root "$state/deployments/roots/plan-$id" --indirect >/dev/null
done
current=${ids[0]} eligible=${ids[1]} active=${ids[2]} previous=${ids[3]} backup=${ids[4]} recovery=${ids[5]}
jq -cnS --arg planId "$current" --arg artifact "$bootstrap" '{planId:$planId,revisionId:$planId,artifact:$artifact}' >"$state/deployments/current.json"
jq -cnS --arg previous "$previous" '{beforeDeployment:{planId:$previous}}' >"$state/deployments/revisions/$current.json"
jq -cnS --arg planId "$backup" '{planId:$planId}' >"$state/backups/repositories/retained/deployment.json"
eligible_task=t-$(printf '2%.0s' {1..32})
active_task=t-$(printf '3%.0s' {1..32})
recovery_task=t-$(printf '6%.0s' {1..32})
jq -cnS --arg id "$eligible_task" --arg planId "$eligible" '{id:$id,planId:$planId,phase:"failed",recoveryRequired:false}' >"$state/deployments/tasks/$eligible_task.json"
jq -cnS --arg id "$active_task" --arg planId "$active" '{id:$id,planId:$planId,phase:"queued"}' >"$state/deployments/tasks/$active_task.json"
jq -cnS --arg id "$recovery_task" --arg planId "$recovery" '{id:$id,planId:$planId,phase:"interrupted",recoveryRequired:true}' >"$state/deployments/tasks/$recovery_task.json"
nix-store --realise "$bootstrap" --add-root "$state/deployments/roots/worker-$eligible_task" --indirect >/dev/null
printf 'preserve adoption evidence\n' >"$state/backups/adoption-original"
exec 8>"$state/deployments/tasks/$eligible_task.lock"
flock -x 8
"$runtime/bin/folio-manager-cleanup" user >"$test_root/locked.json"
jq -e '.data.plans==[]' "$test_root/locked.json"
exec 8>&-
"$runtime/bin/folio-manager-cleanup" user >"$test_root/preview.json"
jq -e --arg eligible "$eligible" '.data.plans==[$eligible] and .data.applied==false' "$test_root/preview.json"
[[ -f "$state/deployments/plans/$eligible.json" ]]
"$runtime/bin/folio-manager-cleanup" user --apply >"$test_root/applied.json"
jq -e --arg eligible "$eligible" '.data.plans==[$eligible] and .data.applied==true' "$test_root/applied.json"
[[ ! -e "$state/deployments/plans/$eligible.json" && ! -L "$state/deployments/roots/plan-$eligible" ]]
[[ ! -e "$state/deployments/tasks/$eligible_task.json" && ! -L "$state/deployments/roots/worker-$eligible_task" ]]
for protected in "$current" "$active" "$previous" "$backup" "$recovery"; do
  [[ -f "$state/deployments/plans/$protected.json" && -L "$state/deployments/roots/plan-$protected" ]]
done
[[ $(cat "$state/backups/adoption-original") == 'preserve adoption evidence' ]]
