current_configuration >"$work/current.json"
desired_digest=$(digest_file "$work/current.json")
health=unavailable
applied_digest=
if [[ -f "$state/deployments/current.json" ]]; then
  artifact=$(jq -er .artifact "$state/deployments/current.json")
  applied_digest=$(jq -er .configurationDigest "$state/deployments/current.json")
  health=degraded
  if [[ $(readlink -e "$profile" || true) == "$artifact" && "$applied_digest" == "$desired_digest" ]] &&
      managed_files_match "$artifact"; then health=healthy; fi
fi
saved=true
if ! configuration_is_saved "$desired_digest"; then saved=false; fi
if [[ -f "$state/configuration/transaction.json" ]]; then
  phase=$(jq -er .phase "$state/configuration/transaction.json")
  case "$phase" in saved|restored) ;; *) saved=false ;; esac
fi
if [[ "$health" == healthy && "$saved" == false ]]; then health=degraded; fi
jq --arg digest "$desired_digest" --arg applied "$applied_digest" --arg health "$health" --argjson saved "$saved" \
  '."folio-environment:environment".configuration={digest:$digest,saved:$saved,"recovery-required":($saved|not)} |
   ."folio-environment:environment".state=({health:$health} + (if $applied=="" then {} else {"applied-digest":$applied} end))' \
  "$work/current.json" >"$work/observed.json"
: >"$work/plans.jsonl"
: >"$work/tasks.jsonl"
shopt -s nullglob
for record in "$state/deployments/plans/"*.json; do
  id=$(basename "$record" .json)
  jq -c --arg id "$id" '{id:$id,"input-digest":.inputDigest,"configuration-digest":.configurationDigest,
    "descriptor-digest":.descriptorDigest,scope,environment,owner,
    "timeout-seconds":.timeoutSeconds,"prior-deployment":.priorDeployment.inputDigest} |
    with_entries(select(.value!=null))' "$record" >>"$work/plans.jsonl"
done
for record in "$state/deployments/tasks/"*.json; do
  jq -c '{id,"request-id":.requestId,"input-digest":.inputDigest,plan:.planId,phase,
    "before-profile":.beforeProfile,"after-profile":.afterProfile,error,"updated-at":.updatedAt} |
    with_entries(select(.value!=null))' "$record" >>"$work/tasks.jsonl"
done
jq -s . "$work/plans.jsonl" >"$work/plans.json"
jq -s . "$work/tasks.jsonl" >"$work/tasks.json"
jq --slurpfile plans "$work/plans.json" --slurpfile tasks "$work/tasks.json" \
  '. + {"folio-deployment:deployment":{plans:$plans[0],tasks:$tasks[0]}}' "$work/observed.json"
