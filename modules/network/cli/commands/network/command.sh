command_main() (
  action=${1:-status}; shift || true
  connection="" interface="" mode="" node=""
  case "$action" in
    status) (( $# == 0 )) || finish invalid null 'Status takes no arguments' ;;
    connect)
      [[ $# == 2 ]] || finish invalid null 'Usage: folio --system network connect UUID INTERFACE'
      connection=$1; interface=$2
      [[ "$connection" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || finish invalid null 'Invalid connection UUID' ;;
    disconnect) [[ $# == 1 ]] || finish invalid null 'Expected an interface'; interface=$1 ;;
    proxy-select) [[ $# == 1 && -n "$1" && ${#1} -le 256 ]] || finish invalid null 'Expected a provider node name'; node=$1
      [[ "$node" != *$'\n'* && "$node" != *$'\r'* ]] || finish invalid null 'Invalid proxy node' ;;
    proxy-mode) [[ $# == 1 ]] || finish invalid null 'Expected rule, direct or global'; mode=$1
      case "$mode" in rule|direct|global) ;; *) finish invalid null 'Invalid proxy mode' ;; esac ;;
    *) finish invalid null 'Usage: folio --system network status|connect|disconnect|proxy-mode|proxy-select' ;;
  esac
  [[ -z "$interface" || "$interface" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,14}$ ]] || finish invalid null 'Invalid interface'
  jq -cn --arg action "$action" --arg connection "$connection" --arg interface "$interface" --arg mode "$mode" --arg node "$node" \
    -f @requestFilter@ >"$work/request.json"
  if ! timeout --kill-after=2 35 folio-repository system cfg --rpc="$work/request.json" --format json --timeout 30 >"$work/reply.json" 2>"$work/error"; then
    cat "$work/error" >&2
    finish unavailable null 'Network subscriber is unavailable or this account lacks system operator access'
  fi
  reply=$(jq -ce 'to_entries[0].value."result-json" | fromjson' "$work/reply.json") || finish unavailable null 'Invalid network reply'
  finish "$(jq -r .status <<<"$reply")" "$(jq -c .data <<<"$reply")" "$(jq -r '.error // ""' <<<"$reply")"
)
command_main "$@"
