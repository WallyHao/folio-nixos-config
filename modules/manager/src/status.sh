task_id=$(jq -r '."folio-deployment:status"."task-id" // ""' "$work/request.json")
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
jq -cn --arg desiredDigest "$desired_digest" --arg health "$health" --argjson applied "$applied" --argjson saved "$saved" \
  --argjson recovery "$recovery" \
  '{status:"success",data:{"folio-deployment:result":({desiredDigest:$desiredDigest,configurationSaved:$saved,health:$health,applied:$applied}
    + (if $recovery=={} then {} else {recovery:$recovery} end))}}'
