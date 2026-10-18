operation=${1:-execute}
if [[ "$operation" == ready ]]; then
  printf '{"folio-deployment:status":{}}\n' >"$work/readiness.json"
  deadline=$((SECONDS + 30))
  while (( SECONDS < deadline )); do
    if timeout --kill-after=1 2 folio-repository user cfg --rpc="$work/readiness.json" --format json --timeout 1 >"$work/ready.json" 2>"$work/error"; then
      result success null
    fi
    sleep 0.2
  done
  result unavailable null 'Wait for manager RPC readiness before starting the applications subscriber'
fi
if [[ "$operation" == recover ]]; then
  # Recovery only dispatches/probes task journals. Do not wait on the manager's
  # configuration lock while Home Manager is starting this subscriber.
  exec 7>"$app_state/mutation.lock"
  flock -n 7 || result success null
  shopt -s nullglob
  for record in "$app_state/tasks/"*.json; do
    task_id=$(jq -er .id "$record")
    [[ "$task_id" =~ ^a-[a-f0-9]{32}$ ]] || result invalid null 'Invalid retained application task'
    phase=$(jq -er .phase "$record")
    if [[ "$phase" == queued ]]; then start_task "$task_id" || result unavailable null 'Unable to dispatch retained application task' "$task_id"
    elif [[ "$phase" != succeeded && "$phase" != failed && "$phase" != interrupted ]] &&
        ! systemctl --user is-active --quiet "folio-app-task-$task_id.service"; then
      jq '.phase="interrupted" | .resultStatus="unavailable" | .error="Worker disappeared; inspect effects and explicitly resume" |
        .recoveryRequired=(.installationStarted==true or .filesStarted==true)' "$record" | folio-atomic-write "$record"
    fi
  done
  result success null
fi
if [[ "$operation" == observed ]]; then
  action=list
else
  [[ "$operation" == execute ]] || result invalid null 'Unknown applications backend entry point'
  cat >"$work/request.json"
  action=$(jq -er .action "$work/request.json")
fi
if [[ "$action" == list ]]; then
  configuration >"$work/configuration.json"
  configuration_digest=$(hash_file "$work/configuration.json")
  inventory >"$work/installed.json"
  flatpak ps --columns=instance,application >"$work/instances.tsv"
  jq -Rn '[inputs | split("\t") | .[0]]' <"$work/instances.tsv" >"$work/instances.json"
  : >"$work/apps.jsonl"
  shopt -s nullglob
  while IFS= read -r desired; do
    name=$(jq -er .name <<<"$desired")
    ref=$(jq -er .ref <<<"$desired")
    owned=null
    [[ ! -f "$app_state/owned/$name.json" ]] || owned=$(jq -c . "$app_state/owned/$name.json")
    jq -cn --argjson desired "$desired" --argjson owned "$owned" --slurpfile inventory "$work/installed.json" \
      --arg ref "$ref" --arg digest "$configuration_digest" --slurpfile instances "$work/instances.json" \
      '($inventory[0] | map(select(.ref==$ref)) | .[0]) as $actual |
       {name:$desired.name,desired:$desired,installed:($actual!=null),owned:($owned!=null),actual:$actual,
        configurationState:(if $owned==null or $owned.configurationDigest!=$digest then "configuration-pending"
          elif $owned.configurationState=="restart-required" and
            ([($owned.restartInstances // [])[] | . as $id | select($instances[0]|index($id))] | length)==0 then "applied"
          else ($owned.configurationState // "configuration-pending") end),
        dependencies:[$inventory[0][] | select(.ref|startswith("runtime/"))],
        unsupported:(if $desired.name=="obs" then ["OBS appearance remains application-owned"]
          else ["Workspace seeding is unavailable without a supported browser API"] end)}' >>"$work/apps.jsonl"
  done < <(jq -c '."folio-environment:environment".modules[] | select(.name=="applications") | ."folio-applications:applications".app[]?' "$work/configuration.json")
  result success "$(jq -cs '{applications:.,scope:"user"}' "$work/apps.jsonl")"
fi
request_id=$(jq -er '."request-id"' "$work/request.json")
[[ "$request_id" =~ ^[a-z][a-z0-9-]{0,63}$ ]] || result invalid null 'Invalid application request ID'
if [[ "$action" == status ]]; then
  task_id=$(jq -er .revision "$work/request.json")
  [[ "$task_id" =~ ^a-[a-f0-9]{32}$ && -f "$app_state/tasks/$task_id.json" ]] || result invalid null 'Unknown application task'
  result success "$(jq -c . "$app_state/tasks/$task_id.json")" '' "$task_id"
fi
application=$(jq -er '.application // "all"' "$work/request.json")
[[ "$application" == all || "$application" == zen || "$application" == obs ]] || result invalid null 'Unknown supported application'
if [[ "$action" == resume ]]; then
  task_id=$(jq -er .revision "$work/request.json")
  [[ "$task_id" =~ ^a-[a-f0-9]{32}$ && -f "$app_state/tasks/$task_id.json" ]] || result invalid null 'Unknown application task'
  lock_mutation
  record=$app_state/tasks/$task_id.json
  jq -e '.phase=="interrupted" or .phase=="failed"' "$record" >/dev/null || result conflict null 'Task is not resumable' "$task_id"
  configuration >"$work/configuration.json"
  [[ $(hash_file "$work/configuration.json") == "$(jq -er .configurationDigest "$record")" ]] || result conflict null 'Desired data changed; resolve the retained effects before making another plan' "$task_id"
  adopt=$(jq -r '."adopt-files"' "$work/request.json")
  jq --argjson adopt "$adopt" '.phase="queued" | .adoptFiles=(.adoptFiles or $adopt) | .error=null' "$record" | folio-atomic-write "$record"
  start_task "$task_id" || result unavailable null 'Task remains durably queued' "$task_id"
  result success "$(jq -c . "$record")" '' "$task_id"
fi
case "$action" in init|install|update|remove|reconcile|adopt|rollback|prepare) ;; *) result invalid null 'Unknown applications operation' ;; esac
request_hash=$(printf '%s' "$request_id" | sha256sum)
task_id=a-${request_hash:0:32}
record=$app_state/tasks/$task_id.json
if [[ -f "$record" ]]; then
  jq -e --slurpfile request "$work/request.json" '.request==$request[0]' "$record" >/dev/null || result conflict null 'Request ID is already bound to different input'
  if [[ $(jq -er .phase "$record") == queued ]]; then start_task "$task_id" || result unavailable null 'Task remains queued' "$task_id"; fi
  result success "$(jq -c . "$record")" '' "$task_id"
fi
lock_mutation
shopt -s nullglob
for pending in "$app_state/tasks/"*.json; do
  jq -e '(.recoveryRequired != true) and (.phase=="succeeded" or .phase=="failed" or .phase=="interrupted")' "$pending" >/dev/null ||
    result conflict null 'Finish or explicitly resume the existing application task'
done
configuration >"$work/configuration.json"
configuration_digest=$(hash_file "$work/configuration.json")
[[ $(jq -er '."folio-environment:environment".account' "$work/configuration.json") == "$(id -un)" ]] || result invalid null 'Applications require the provisioned account'
jq -e '."folio-environment:environment".modules[] | select(.name=="applications" and .enabled==true)' "$work/configuration.json" >/dev/null || result unavailable null 'Enable and apply the applications contribution first'
if [[ "$action" != init ]]; then
  [[ $(jq -er '."configuration-digest"' "$work/request.json") == "$configuration_digest" ]] || result conflict null 'Application request configuration became stale'
fi
generation=$(manifest || true)
nix-store --realise @worker@ --add-root "$app_state/roots/worker-$task_id" --indirect >/dev/null
if [[ -n "$generation" ]]; then nix-store --realise "$generation" --add-root "$app_state/roots/manifest-$task_id" --indirect >/dev/null; fi
jq -cnS --arg id "$task_id" --arg worker @worker@/bin/folio-applications-worker \
  --arg digest "$configuration_digest" --arg generation "$generation" --arg now "$(date -u +%FT%TZ)" \
  --slurpfile request "$work/request.json" --slurpfile configuration "$work/configuration.json" \
  '{format:1,id:$id,worker:$worker,request:$request[0],configuration:$configuration[0],configurationDigest:$digest,
    generation:$generation,phase:"queued",resultStatus:null,error:null,recoveryRequired:false,
    adoptFiles:$request[0]."adopt-files",offline:$request[0].offline,createdAt:$now,updatedAt:$now}' |
  folio-atomic-write "$record"
start_task "$task_id" || result unavailable null 'Task is durably queued; user service dispatch is unavailable' "$task_id"
result success "$(jq -c . "$record")" '' "$task_id"
