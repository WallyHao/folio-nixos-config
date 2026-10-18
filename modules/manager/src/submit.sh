request=$(jq -cer 'to_entries[0].value' "$work/request.json")
plan_id=$(jq -er '."plan-id"' <<<"$request")
request_id=$(jq -er '."request-id"' <<<"$request")
plan=$state/deployments/plans/$plan_id.json
if [[ ! -f "$plan" ]]; then reply invalid 'Unknown plan'; exit 0; fi
exec 7>"$state/deployments/queue.lock"
flock -x -w 10 7
request_hash=$(printf '%s' "$request_id" | sha256sum)
task_id=t-${request_hash:0:32}
record=$state/deployments/tasks/$task_id.json
if [[ -f "$record" ]]; then
  if ! jq -e --arg kind "$operation_kind" --arg plan "$plan_id" --arg request "$request_id" \
      '.kind==$kind and .planId==$plan and .requestId==$request' "$record" >/dev/null; then
    reply conflict 'Request ID is already bound to different input'; exit 0
  fi
  if [[ $(jq -er .phase "$record") == queued ]]; then start_task "$task_id" || true; fi
  task_reply "$task_id"; exit 0
fi
if [[ "$operation_kind" == apply ]]; then
  if [[ ! -f "$state/deployments/builds/$plan_id.json" ]]; then
    reply unavailable 'Plan has no successful build'; exit 0
  fi
  lock_configuration
  recover_configuration
  if has_pending_recovery; then reply conflict 'Resolve interrupted deployment effects before applying'; exit 0; fi
  if ! plan_current; then reply conflict 'Plan is stale; create a new plan'; exit 0; fi
fi
worker=@worker@/bin/folio-manager-worker
timeout_seconds=$(jq -er .timeoutSeconds "$plan")
nix-store --realise @worker@ --add-root "$state/deployments/roots/worker-$task_id" --indirect >/dev/null
jq -cnS --arg id "$task_id" --arg kind "$operation_kind" --arg planId "$plan_id" \
  --arg requestId "$request_id" --arg worker "$worker" --arg now "$(date -u +%FT%TZ)" \
  --slurpfile plan "$plan" --argjson timeoutSeconds "$timeout_seconds" \
  '{format:1,id:$id,kind:$kind,planId:$planId,requestId:$requestId,worker:$worker,
    inputDigest:$plan[0].inputDigest,timeoutSeconds:$timeoutSeconds,phase:"queued",
    updatedAt:$now,error:null,resultStatus:null}' | folio-atomic-write "$record"
if ! start_task "$task_id"; then
  jq -cn --arg id "$task_id" '{status:"unavailable","task-id":$id,error:"Task is durably queued; user service dispatch is unavailable"}'
  exit 0
fi
task_reply "$task_id"
