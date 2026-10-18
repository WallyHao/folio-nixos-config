command_main() (
action=$FOLIO_COMMAND
rpc() {
  local tolerate_unavailable=${1:-false}
  if ! timeout --kill-after=2 32 folio-repository "$FOLIO_SCOPE" cfg --rpc="$work/rpc.json" \
      --format json --timeout 30 >"$work/reply.json" 2>"$work/error"; then
    if [[ $(cat "$work/error") == *'no matching subscribers'* ]]; then
      if "$tolerate_unavailable"; then return 1; fi
      cat "$work/error" >&2
      finish unavailable null 'Manager subscriber is unavailable'
    fi
    if "$tolerate_unavailable"; then return 1; fi
    cat "$work/error" >&2
    finish failure null 'Deployment RPC failed'
  fi
  response=$(jq -ce 'to_entries[0].value' "$work/reply.json") || finish failure null 'Invalid manager reply'
  response_status=$(jq -er .status <<<"$response")
  if "$tolerate_unavailable" && [[ "$response_status" == unavailable ]]; then return 1; fi
  response_error=$(jq -r '.error // ""' <<<"$response")
  response_data=$(jq -c '.data["folio-deployment:result"] // .data.result // null' <<<"$response")
}
read_task() {
  jq -cn --arg id "$task_id" '{"folio-deployment:status":{"task-id":$id}}' >"$work/rpc.json"
  rpc true || return 1
  [[ "$response_status" == success ]] || finish "$response_status" "$response_data" "$response_error" "$task_id"
}
case "$action" in
  plan)
    source_path=$PWD
    timeout_seconds=1800
    while (( $# )); do
      case "$1" in
        --source) (( $# >= 2 )) || finish invalid null 'Missing source directory'; source_path=$2; shift 2 ;;
        --timeout-seconds) (( $# >= 2 )) || finish invalid null 'Missing timeout'; timeout_seconds=$2; shift 2 ;;
        *) finish invalid null 'Usage: folio plan [--source DIRECTORY] [--timeout-seconds N]' ;;
      esac
    done
    [[ "$timeout_seconds" =~ ^[1-9][0-9]{0,4}$ && "$timeout_seconds" -le 86400 ]] || finish invalid null 'Timeout must be 1..86400 seconds'
    source_path=$(realpath -e -- "$source_path") || finish invalid null 'Source directory is unavailable'
    jq -cn --arg source "$source_path" --argjson timeout "$timeout_seconds" \
      '{"folio-deployment:plan":{source:$source,"timeout-seconds":$timeout}}' >"$work/rpc.json"
    rpc
    plan_id=$(jq -r '."plan-id" // ""' <<<"$response")
    finish "$response_status" "$(jq -cn --arg id "$plan_id" --argjson plan "$response_data" '{planId:$id,plan:$plan}')" "$response_error" ;;
  build|apply)
    (( $# >= 1 )) || finish invalid null 'Expected a plan ID'
    plan_id=$1; shift
    [[ "$plan_id" =~ ^[a-f0-9]{64}$ ]] || finish invalid null 'Invalid plan ID'
    request_id=r-$(cat /proc/sys/kernel/random/uuid)
    if (( $# )); then
      [[ $# == 2 && $1 == --request-id ]] || finish invalid null 'Usage: folio build|apply PLAN_ID [--request-id ID]'
      request_id=$2
    fi
    [[ "$request_id" =~ ^[a-z][a-z0-9-]{0,63}$ ]] || finish invalid null 'Invalid request ID'
    jq -cn --arg action "folio-deployment:$action" --arg plan "$plan_id" --arg request "$request_id" \
      '{($action):{"plan-id":$plan,"request-id":$request}}' >"$work/rpc.json"
    rpc
    task_id=$(jq -r '."task-id" // ""' <<<"$response")
    [[ "$response_status" == success ]] || finish "$response_status" "$response_data" "$response_error" "$task_id"
    if "$FOLIO_NO_WAIT"; then finish success null '' "$task_id"; fi
    timeout_seconds=$(jq -er .timeoutSeconds <<<"$response_data")
    deadline=$((SECONDS + timeout_seconds + 70))
    while (( SECONDS < deadline )); do
      if ! read_task; then sleep 0.2; continue; fi
      phase=$(jq -er .task.phase <<<"$response_data")
      case "$phase" in
        succeeded) finish success "$(jq -c .task <<<"$response_data")" '' "$task_id" ;;
        failed|interrupted)
          finish "$(jq -r '.task.resultStatus // "failure"' <<<"$response_data")" \
            "$(jq -c .task <<<"$response_data")" "$(jq -r '.task.error // "Task failed"' <<<"$response_data")" "$task_id" ;;
      esac
      sleep 0.2
    done
    finish unavailable "$response_data" 'Stopped waiting at the task timeout; the task remains recorded' "$task_id" ;;
  status)
    (( $# <= 1 )) || finish invalid null 'Usage: folio status [TASK_ID]'
    task_id=${1:-}
    [[ -z "$task_id" || "$task_id" =~ ^t-[a-f0-9]{32}$ ]] || finish invalid null 'Invalid task ID'
    jq -cn --arg id "$task_id" '{"folio-deployment:status":(if $id=="" then {} else {"task-id":$id} end)}' >"$work/rpc.json"
    if ! rpc true; then
      state=${XDG_STATE_HOME:-$HOME/.local/state}/folio
      [[ "$FOLIO_SCOPE" != system ]] || state=/var/lib/folio
      if [[ -n "$task_id" && -r "$state/deployments/tasks/$task_id.json" ]]; then
        finish success "$(jq -cn --slurpfile task "$state/deployments/tasks/$task_id.json" '{offline:true,task:$task[0]}')" '' "$task_id"
      fi
      shopt -s nullglob
      journals=("$state"/offline-coordinator-*.json)
      if (( ${#journals[@]} )); then
        maintenance=$(jq -cs '[.[] | select(.phase!="complete" and .phase!="restored" and .phase!="aborted") |
          {key:.id,value:{phase,scope}}] | from_entries' "${journals[@]}")
        if [[ "$maintenance" != '{}' ]]; then
          finish success "$(jq -cn --argjson maintenance "$maintenance" '{offline:true,health:"degraded",maintenance:$maintenance}')"
        fi
      fi
      finish unavailable null 'Manager subscriber is unavailable'
    fi
    finish "$response_status" "$response_data" "$response_error" "$task_id" ;;
  *) finish invalid null 'Unsupported deployment command' ;;
esac
)
command_main "$@"
