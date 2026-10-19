command_main() (
  action=${1:-status}; shift || true
  level=null amount=null profile=
  case "$action" in
    status) (( $# == 0 )) || finish invalid null 'Status takes no arguments' ;;
    volume)
      [[ $# == 1 ]] || finish invalid null 'Usage: folio devices volume LEVEL|+DELTA|-DELTA'
      if [[ "$1" =~ ^[+-]([1-9]|1[0-9]|20)$ ]]; then action=adjust-volume; amount=${1#+}
      elif [[ "$1" =~ ^(0|[1-9][0-9]?|100)$ ]]; then action=set-volume; level=$1
      else finish invalid null 'Volume must be 0..100 or an adjustment up to 20'; fi ;;
    mute) (( $# == 0 )) || finish invalid null 'Mute takes no arguments'; action=toggle-mute ;;
    brightness)
      [[ $# == 1 ]] || finish invalid null 'Expected a brightness level or adjustment'
      if [[ "$1" =~ ^[+-]([1-9]|1[0-9]|20)$ ]]; then action=adjust-brightness; amount=${1#+}
      elif [[ "$1" =~ ^(0|[1-9][0-9]?|100)$ ]]; then action=set-brightness; level=$1
      else finish invalid null 'Brightness must be 0..100 or an adjustment up to 20'; fi ;;
    profile)
      [[ $# == 1 ]] || finish invalid null 'Expected balanced, power-saver or performance'
      case "$1" in balanced|power-saver|performance) ;; *) finish invalid null 'Unknown power profile' ;; esac
      profile=$1; action=set-power-profile ;;
    *) finish invalid null 'Usage: folio devices status|volume|mute|brightness|profile' ;;
  esac
  jq -cn --arg action "$action" --argjson level "$level" --argjson amount "$amount" --arg profile "$profile" \
    -f @requestFilter@ >"$work/request.json"
  if ! timeout --kill-after=2 25 folio-repository user cfg --rpc="$work/request.json" --format json --timeout 20 >"$work/reply.json" 2>"$work/error"; then
    cat "$work/error" >&2
    finish unavailable null 'Devices subscriber is unavailable; enable and apply its user contribution'
  fi
  reply=$(jq -ce 'to_entries[0].value."result-json" | fromjson' "$work/reply.json") || finish unavailable null 'Invalid devices reply'
  finish "$(jq -r .status <<<"$reply")" "$(jq -c .data <<<"$reply")" "$(jq -r '.error // ""' <<<"$reply")"
)
command_main "$@"
