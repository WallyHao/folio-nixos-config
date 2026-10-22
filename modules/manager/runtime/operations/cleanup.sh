umask 0077
scope=${1:-}; shift || true
apply=false
case "${1:-}" in '') ;; --apply) apply=true; shift ;; *) exit 2 ;; esac
[[ $# == 0 ]] || exit 2
case "$scope" in
  user) state=${XDG_STATE_HOME:-$HOME/.local/state}/folio ;;
  system) [[ $(id -u) == 0 ]] || exit 3; state=/var/lib/folio ;;
  *) exit 2 ;;
esac
[[ "$state" == /* && -d "$state/deployments" ]] || exit 3
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Submission takes queue before mutation; match that order, including build
# submissions that do not otherwise need the configuration mutation lock.
exec 7>"$state/deployments/queue.lock"
flock -x -w 30 7
exec 9>"$state/mutation.lock"
flock -x -w 30 9
shopt -s nullglob
references=()
[[ ! -f "$state/deployments/current.json" ]] || references+=("$state/deployments/current.json")
[[ ! -f "$state/schema-transaction.json" ]] || references+=("$state/schema-transaction.json")
references+=("$state"/offline-coordinator-*.json)
# Retain all explicit backup/recovery references. Cleanup never deletes backup
# repositories, adoption backups, conflict evidence or application data.
references+=("$state/backups/repositories/"*/transaction.json "$state/backups/repositories/"*/deployment.json)
for retained in "$state/deployments/plans/"*.json; do
  if jq -e '.retained == true' "$retained" >/dev/null; then references+=("$retained"); fi
done
for task in "$state/deployments/tasks/"*.json; do
  if ! jq -e '(.recoveryRequired != true) and (.phase=="succeeded" or .phase=="failed" or .phase=="interrupted")' "$task" >/dev/null; then
    references+=("$task")
  fi
done
if [[ -f "$state/deployments/current.json" ]]; then
  revision=$(jq -r '.revisionId // .planId // ""' "$state/deployments/current.json")
  [[ "$revision" =~ ^([a-f0-9]{64}|maintenance-[a-z][a-z0-9-]{0,63})$ ]] || exit 4
  [[ ! -f "$state/deployments/revisions/$revision.json" ]] || references+=("$state/deployments/revisions/$revision.json")
fi
jq -cs '.' "${references[@]}" </dev/null >"$work/references.json"
# The current revision includes only its immediate before deployment. Traverse
# recorded reference objects, not every historical revision's predecessor chain.
jq '[.. | strings] | unique' "$work/references.json" >"$work/protected.json"
: >"$work/plans"
: >"$work/tasks"
for plan in "$state/deployments/plans/"*.json; do
  id=$(basename "$plan" .json)
  [[ "$id" =~ ^[a-f0-9]{64}$ && ! -L "$plan" ]] || exit 4
  # Reviewed plans are referenced by cross-scope history. Keep their snapshots
  # and successful revisions available for explicit rollback.
  if jq -e '.retained == true' "$plan" >/dev/null; then continue; fi
  paths=("$plan")
  [[ ! -f "$state/deployments/builds/$id.json" ]] || paths+=("$state/deployments/builds/$id.json")
  [[ ! -f "$state/deployments/revisions/$id.json" ]] || paths+=("$state/deployments/revisions/$id.json")
  if jq -e --arg id "$id" --slurpfile protected "$work/protected.json" \
      '([$id] + [.[] | .source?, .artifact? | strings]) as $values |
       any($values[]; . as $value | $protected[0] | index($value) != null)' \
      < <(jq -cs . "${paths[@]}") >/dev/null; then continue; fi
  # Exclude live workers even if they already published a terminal phase but
  # have not released their task lock yet. Use nonblocking locks only.
  busy=false
  for task in "$state/deployments/tasks/"*.json; do
    [[ $(jq -r .planId "$task") == "$id" ]] || continue
    task_id=$(basename "$task" .json)
    [[ "$task_id" =~ ^t-[a-f0-9]{32}$ && ! -L "$task" ]] || exit 4
    exec 8>"$state/deployments/tasks/$task_id.lock"
    if ! flock -n 8; then busy=true; fi
    exec 8>&-
  done
  "$busy" && continue
  printf '%s\n' "$id" >>"$work/plans"
  for task in "$state/deployments/tasks/"*.json; do
    [[ $(jq -r .planId "$task") != "$id" ]] || basename "$task" .json >>"$work/tasks"
  done
done
jq -Rn '[inputs]' <"$work/plans" >"$work/plans.json"
jq -Rn '[inputs]' <"$work/tasks" >"$work/tasks.json"
cleanup_id=c-$(tr -d '-' </proc/sys/kernel/random/uuid)
jq -cnS --arg id "$cleanup_id" --arg scope "$scope" --argjson applied "$apply" \
  --slurpfile plans "$work/plans.json" --slurpfile tasks "$work/tasks.json" \
  '{format:1,id:$id,scope:$scope,applied:$applied,plans:$plans[0],tasks:$tasks[0]}' >"$work/selection.json"
if "$apply"; then
  mkdir -p "$state/deployments/cleanup"
  sync "$state/deployments" "$state/deployments/cleanup"
  folio-atomic-write "$state/deployments/cleanup/$cleanup_id.json" <"$work/selection.json"
  while IFS= read -r task_id; do
    for root in worker apply before; do
      path=$state/deployments/roots/$root-$task_id
      [[ ! -e "$path" || -L "$path" ]] || exit 4
      rm -f "$path"
    done
    rm -f "$state/deployments/tasks/$task_id.json"
  done <"$work/tasks"
  while IFS= read -r id; do
    for root in plan build; do
      path=$state/deployments/roots/$root-$id
      [[ ! -e "$path" || -L "$path" ]] || exit 4
      rm -f "$path"
    done
    rm -f "$state/deployments/plans/$id.json" "$state/deployments/builds/$id.json" "$state/deployments/revisions/$id.json"
  done <"$work/plans"
  sync -f "$state/deployments"
fi
jq -cn --slurpfile selection "$work/selection.json" '{status:"success",data:$selection[0],error:null,taskId:null}'
