task_id=$(jq -r '."folio-deployment:status"."task-id" // ""' "$work/request.json")
if [[ $(jq -r '."folio-deployment:status".history // false' "$work/request.json") == true ]]; then
  shopt -s nullglob
  plans=("$state/deployments/plans/"*.json)
  : >"$work/history.jsonl"
  for plan in "${plans[@]}"; do
    id=$(basename "$plan" .json)
    [[ "$id" =~ ^[a-f0-9]{64}$ ]] || continue
    phase=planned
    [[ ! -f "$state/deployments/builds/$id.json" ]] || phase=built
    [[ ! -f "$state/deployments/revisions/$id.json" ]] || phase=applied
    jq -c --arg id "$id" --arg phase "$phase" \
      '{planId:$id,status:$phase,comment,createdAt,scope,inputDigest,configurationDigest,source,owner,
        artifact:.review.targetArtifact}' "$plan" >>"$work/history.jsonl"
  done
  current=null
  [[ ! -f "$state/deployments/current.json" ]] || current=$(jq -c . "$state/deployments/current.json")
  current_configuration >"$work/desired.json"
  selected=$(selected_profile)
  effects_match=false
  if [[ -n "$selected" ]] && applied_artifact_matches "$selected"; then effects_match=true; fi
  saved=false
  if configuration_is_saved "$(digest_file "$work/desired.json")"; then saved=true; fi
  recovery_required=false
  if has_pending_recovery; then recovery_required=true; fi
  revisions=("$state/deployments/revisions/"*.json)
  jq -cs '[.[] | {revisionId:(.revisionId // .planId),artifact,configurationDigest}]' "${revisions[@]}" </dev/null >"$work/revisions.json"
  jq -cn --argjson current "$current" --slurpfile plans "$work/history.jsonl" \
    --arg selected "$selected" --arg desiredDigest "$(digest_file "$work/desired.json")" --slurpfile revisions "$work/revisions.json" \
    --argjson effectsMatch "$effects_match" --argjson saved "$saved" --argjson recoveryRequired "$recovery_required" \
    '{status:"success",data:{"folio-deployment:result":{plans:$plans,current:$current,
      selectedProfile:$selected,desiredDigest:$desiredDigest,revisions:$revisions[0],effectsMatch:$effectsMatch,
      configurationSaved:$saved,recoveryRequired:$recoveryRequired}}}'
  exit 0
fi
if [[ -n "$task_id" ]]; then
  record=$state/deployments/tasks/$task_id.json
  if [[ ! -f "$record" ]]; then reply invalid 'Unknown task'; exit 0; fi
  jq -cn --slurpfile task "$record" '{status:"success",data:{"folio-deployment:result":{task:$task[0]}}}'
  exit 0
fi
current_configuration >"$work/current.json"
desired_digest=$(digest_file "$work/current.json")
saved=true
if ! configuration_is_saved "$desired_digest"; then saved=false; fi
applied=null
health=unavailable
if [[ -f "$state/deployments/current.json" ]]; then
  applied=$(jq -c . "$state/deployments/current.json")
  health=degraded
  if [[ $(selected_profile) == "$(jq -r .artifact <<<"$applied")" &&
        "$desired_digest" == "$(jq -r .configurationDigest <<<"$applied")" ]]; then
    if applied_artifact_matches "$(jq -r .artifact <<<"$applied")"; then health=healthy; fi
    expected_foot=$(jq -r '.footDigest // ""' <<<"$applied")
    if [[ -n "$expected_foot" ]] && { [[ ! -f "$HOME/.config/foot/foot.ini" ]] ||
        [[ $(digest_file "$HOME/.config/foot/foot.ini") != "$expected_foot" ]]; }; then health=degraded; fi
  fi
fi
if [[ "$health" == healthy && "$saved" == false ]]; then health=degraded; fi
shopt -s nullglob
task_records=("$state/deployments/tasks/"*.json)
recovery=$(jq -cs '[.[] | select(.recoveryRequired==true) | {key:.id,value:{phase,beforeProfile,afterProfile,error}}] | from_entries' "${task_records[@]}" </dev/null)
[[ "$recovery" == '{}' ]] || health=degraded
maintenance_records=("$state"/offline-coordinator-*.json)
maintenance=$(jq -cs '[.[] | {key:.id,value:{phase,scope}}] | from_entries' "${maintenance_records[@]}" </dev/null)
if has_pending_maintenance; then health=degraded; fi
jq -cn --arg desiredDigest "$desired_digest" --arg health "$health" --argjson applied "$applied" --argjson saved "$saved" \
  --argjson recovery "$recovery" --argjson maintenance "$maintenance" \
  '{status:"success",data:{"folio-deployment:result":({desiredDigest:$desiredDigest,configurationSaved:$saved,health:$health,applied:$applied}
    + (if $recovery=={} then {} else {recovery:$recovery} end)
    + (if $maintenance=={} then {} else {maintenance:$maintenance} end))}}'
