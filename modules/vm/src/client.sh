action=${1:-}; shift || true
case "$action" in build|start|stop|status|cleanup) ;; *) finish invalid null 'Usage: folio vm build|start|stop|status|cleanup JOB_ID [SOURCE]' ;; esac
(( $# >= 1 )) || finish invalid null 'Missing VM job ID'
job_id=$1; shift
[[ "$job_id" =~ ^[a-z][a-z0-9-]{0,63}$ ]] || finish invalid null 'Invalid VM job ID'
source_path=
if [[ "$action" == build ]]; then
  [[ $# == 1 ]] || finish invalid null 'Build requires an immutable source snapshot'
  source_path=$1; shift
fi
(( $# == 0 )) || finish invalid null 'Unexpected VM arguments'
if "$FOLIO_NO_WAIT" && [[ "$action" != build ]]; then finish invalid null '--no-wait applies to VM build'; fi
rpc() {
  jq -cn --arg action "$1" --arg id "$job_id" --arg source "$source_path" \
    '{"folio-vm:execute":({action:$action,"job-id":$id} + (if $source=="" then {} else {source:$source} end))}' >"$work/request.json"
  if ! timeout --kill-after=2 55 folio-repository user cfg --rpc="$work/request.json" --format json --timeout 50 \
      >"$work/reply.json" 2>"$work/error"; then
    cat "$work/error" >&2
    finish unavailable null 'VM subscriber is unavailable; enable and apply the VM user module' "$job_id"
  fi
  response=$(jq -ce 'to_entries[0].value' "$work/reply.json") || finish failure null 'Invalid VM reply'
  result=$(jq -ce '."result-json" | fromjson' <<<"$response") ||
    finish "$(jq -r '.status // "failure"' <<<"$response")" null "$(jq -r '.error // "Invalid VM result"' <<<"$response")" "$job_id"
}
rpc "$action"
if [[ "$action" == build && $(jq -r .status <<<"$result") == success ]] && ! "$FOLIO_NO_WAIT"; then
  deadline=$((SECONDS + 1860))
  while (( SECONDS < deadline )); do
    rpc status
    phase=$(jq -r .data.phase <<<"$result")
    case "$phase" in
      ready) break ;;
      failed|interrupted) finish failure "$(jq -c .data <<<"$result")" 'VM build failed; inspect retained logs' "$job_id" ;;
    esac
    sleep 1
  done
  [[ "$phase" == ready ]] || finish unavailable "$(jq -c .data <<<"$result")" 'Stopped waiting; the VM build remains recorded' "$job_id"
fi
finish "$(jq -r .status <<<"$result")" "$(jq -c .data <<<"$result")" "$(jq -r '.error // ""' <<<"$result")" "$job_id"
