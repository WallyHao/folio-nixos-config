action=${1:-}
shift || true
case "$action" in reboot|poweroff) ;; *) finish invalid null 'Usage: folio --system system reboot|poweroff [--request-id ID]' ;; esac
request_id=p-$(cat /proc/sys/kernel/random/uuid)
if (( $# )); then
  [[ $# == 2 && $1 == --request-id ]] || finish invalid null 'Expected --request-id ID'
  request_id=$2
fi
[[ "$request_id" =~ ^[a-z][a-z0-9-]{0,63}$ ]] || finish invalid null 'Invalid request ID'
jq -cn --arg action "folio-system:$action" --arg id "$request_id" '{($action):{"request-id":$id}}' >"$work/rpc.json"
if ! timeout --kill-after=2 32 folio-repository system cfg --rpc="$work/rpc.json" --format json --timeout 30 >"$work/result.json" 2>"$work/error"; then
  cat "$work/error" >&2
  if [[ $(cat "$work/error") == *'no matching subscribers'* ]]; then finish unavailable null 'System power subscriber is unavailable'; fi
  finish failure null 'Power RPC failed'
fi
result=$(jq -ce 'to_entries[0].value' "$work/result.json")
finish "$(jq -er .status <<<"$result")" \
  "$(jq -cn --arg id "$request_id" --arg action "$action" --arg phase "$(jq -r '.phase // ""' <<<"$result")" \
    '{requestId:$id,action:$action,phase:$phase}')" "$(jq -r '.error // ""' <<<"$result")"
