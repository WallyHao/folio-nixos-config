# These helpers run under the scoped mutation lock. Task locks are acquired only
# after it; workers use nonblocking task locks before waiting on that same lock.
has_pending_maintenance() {
  local pending
  shopt -s nullglob
  for pending in "$state"/offline-coordinator-*.json; do
    if ! jq -e '.phase=="complete" or .phase=="restored" or .phase=="aborted"' "$pending" >/dev/null; then return 0; fi
  done
  return 1
}
has_pending_recovery() {
  local pending
  if has_pending_maintenance; then return 0; fi
  shopt -s nullglob
  for pending in "$state/deployments/tasks/"*.json; do
    if jq -e '.recoveryRequired == true' "$pending" >/dev/null; then return 0; fi
  done
  return 1
}
publish_deployment() {
  local task_record=$1 task_identifier plan_identifier plan_record selected_artifact source_path foot_digest=null
  task_identifier=$(jq -er .id "$task_record") || return 1
  plan_identifier=$(jq -er .planId "$task_record") || return 1
  plan_record=$state/deployments/plans/$plan_identifier.json
  [[ $(digest_file "$plan_record") == "$plan_identifier" ]] || return 1
  selected_artifact=$(jq -er .afterProfile "$task_record") || return 1
  source_path=$(jq -er .source "$plan_record") || return 1
  [[ "$selected_artifact" =~ ^/nix/store/[a-z0-9]{32}-[^/]+$ && -d "$selected_artifact" ]] || return 1
  applied_artifact_matches "$selected_artifact" || return 1
  current_configuration >"$work/publication-configuration.json" || return 1
  [[ $(digest_file "$work/publication-configuration.json") == "$(jq -er .configurationDigest "$plan_record")" ]] || return 1
  if [[ "$scope" == user && -f "$selected_artifact/home-files/.config/foot/foot.ini" ]]; then
    foot_digest=$(jq -cn --arg value "$(digest_file "$HOME/.config/foot/foot.ini")" '$value')
  fi
  mkdir -p "$state/deployments/revisions" || return 1
  sync "$state/deployments" "$state/deployments/revisions" || return 1
  jq -cnS --arg scope "$scope" --arg artifact "$selected_artifact" --arg planId "$plan_identifier" \
    --arg taskId "$task_identifier" --arg bootstrap "$FOLIO_BOOTSTRAP" --argjson footDigest "$foot_digest" \
    --slurpfile plan "$plan_record" --slurpfile task "$task_record" --slurpfile input "$source_path/folio-input.json" \
    '{format:1,workerProtocol:1,scope:$scope,artifact:$artifact,planId:$planId,taskId:$taskId,
      bootstrap:$bootstrap,source:$plan[0].source,inputDigest:$plan[0].inputDigest,
      configurationDigest:$plan[0].configurationDigest,footDigest:$footDigest,
      configuration:$input[0].configuration,models:$input[0].models,tools:$input[0].tools,
      beforeProfile:$task[0].beforeProfile,beforeDeployment:$task[0].beforeDeployment}' |
    folio-atomic-write "$state/deployments/revisions/$plan_identifier.json" || return 1
  jq '{format,artifact,planId,taskId,source,inputDigest,configurationDigest,footDigest} + {revisionId:.planId}' \
    "$state/deployments/revisions/$plan_identifier.json" | folio-atomic-write "$state/deployments/current.json"
}
reconcile_interrupted_task() {
  local task_record=$1 before after effect resolved=false action=none message
  before=$(jq -r '.beforeProfile // ""' "$task_record")
  after=$(jq -r '.afterProfile // ""' "$task_record")
  effect=$(jq -r '.effectPhase // (if .phase=="verifying" then "activation-returned" else "none" end)' "$task_record")
  message='Worker disappeared before effects; the operation was not repeated'
  if [[ -z "$after" ]]; then
    resolved=true
  elif [[ "$effect" == activation-returned ]] && applied_artifact_matches "$after" &&
      publish_deployment "$task_record"; then
    jq --arg now "$(date -u +%FT%TZ)" '.phase="succeeded" | .resultStatus="success" |
      .recoveryRequired=false | .recoveryAction="completed-publication" | .recovered=true |
      .error=null | .updatedAt=$now' "$task_record" | folio-atomic-write "$task_record"
    return 0
  elif [[ -n "$before" ]] && artifact_effects_match "$before"; then
    if [[ $(selected_profile) == "$before" ]]; then
      resolved=true
      action=verified-before
    elif [[ $(selected_profile) == "$after" ]]; then
      # Restore only the recorded profile selection. No activation is retried;
      # actual files/running-system must already match the known before closure.
      if nix-env --profile "$profile" --set "$before" && applied_artifact_matches "$before"; then
        resolved=true
        action=restored-profile
      fi
    fi
    message='Interrupted activation retained the verified before revision'
  fi
  if ! "$resolved"; then message='Partial activation requires explicit recovery; inputs and effects are retained'; fi
  jq --arg message "$message" --arg action "$action" --argjson required "$(! "$resolved" && echo true || echo false)" \
    --arg now "$(date -u +%FT%TZ)" '.phase="interrupted" | .resultStatus="unavailable" |
      .error=$message | .recoveryRequired=$required | .recoveryAction=$action | .updatedAt=$now' "$task_record" |
    folio-atomic-write "$task_record"
}
