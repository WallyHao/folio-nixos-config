umask 0077
export LC_ALL=C.UTF-8
[[ $(id -u) == 0 && -d /run/folio/network ]] || exit 3
work=$(mktemp -d /run/folio/network/operation.XXXXXX)
trap 'rm -rf "$work"' EXIT
reply() {
  local status=$1 data=${2:-null} error=${3:-} code
  case "$status" in success) code=0 ;; invalid) code=2 ;; unavailable) code=3 ;; conflict) code=4 ;; *) code=1 ;; esac
  jq -cn --arg status "$status" --argjson data "$data" --arg error "$error" \
    '{status:$status,data:$data,error:(if $error=="" then null else $error end),taskId:null}'
  exit "$code"
}
proxy_request() {
  curl --silent --show-error --fail --noproxy '*' --connect-timeout 1 --max-time 3 \
    --unix-socket /run/folio-mihomo/controller.sock "$@"
}
observe() {
  network='{"available":false,"connectivity":"unknown","devices":[]}'
  if timeout --kill-after=1 3 nmcli --terse --escape no --fields DEVICE,TYPE,STATE device status >"$work/devices" 2>"$work/nm-error" &&
     timeout --kill-after=1 3 nmcli --terse --fields CONNECTIVITY general status >"$work/connectivity" 2>>"$work/nm-error"; then
    network=$(jq -Rn --rawfile connectivity "$work/connectivity" \
      '[inputs | split(":") | {interface:.[0],type:.[1],state:.[2]}] |
       {available:true,connectivity:($connectivity|rtrimstr("\n")),devices:.}' <"$work/devices")
  fi
  proxy='{"available":false,"mode":null}'
  if proxy_request http://localhost/configs >"$work/proxy" 2>"$work/proxy-error"; then
    selected=null
    if proxy_request http://localhost/proxies/PROXY >"$work/group" 2>/dev/null; then
      selected=$(jq -c '.now // null' "$work/group")
    fi
    proxy=$(jq -ce --argjson selected "$selected" '{available:true,mode:.mode,selectedNode:$selected}' "$work/proxy")
  fi
  jq -cn --argjson network "$network" --argjson proxy "$proxy" \
    '{network:$network,proxy:$proxy,physicalAcceptance:"unverified"}'
}
cat >"$work/request.json"
action=$(jq -er .action "$work/request.json")
if [[ "$action" != status ]]; then
  exec 9>/run/folio/network/control.lock
  flock -x -w 2 9 || reply conflict null 'Network controls are busy'
  case "$action" in
    connect|disconnect)
      interface=$(jq -er '.interface | select(type=="string")' "$work/request.json")
      [[ "$interface" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,14}$ ]] || reply invalid null 'Invalid interface'
      if [[ "$action" == connect ]]; then
        connection=$(jq -er .connection "$work/request.json")
        [[ "$connection" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || reply invalid null 'Invalid connection UUID'
        command=(nmcli --wait 5 connection up uuid "$connection" ifname "$interface")
      else command=(nmcli --wait 5 device disconnect "$interface"); fi
      if ! timeout --kill-after=1 7 "${command[@]}" >"$work/control-output" 2>"$work/control-error"; then
        reply unavailable null "Network backend, connection or authorization is unavailable: $(cat "$work/control-error")"
      fi ;;
    proxy-mode)
      mode=$(jq -er .mode "$work/request.json")
      case "$mode" in rule|direct|global) ;; *) reply invalid null 'Invalid proxy mode' ;; esac
      jq -cn --arg mode "$mode" '{mode:$mode}' >"$work/mode.json"
      if ! proxy_request --request PATCH --header 'Content-Type: application/json' --data-binary @"$work/mode.json" \
          http://localhost/configs >"$work/control-output" 2>"$work/control-error"; then
        reply unavailable null 'Mihomo control socket is unavailable; enable and apply the system proxy contribution'
      fi ;;
    proxy-select)
      node=$(jq -er '.node | select(type=="string" and length>0 and length<=256)' "$work/request.json") || reply invalid null 'Invalid proxy node'
      [[ "$node" != *$'\n'* && "$node" != *$'\r'* ]] || reply invalid null 'Invalid proxy node'
      jq -cn --arg name "$node" '{name:$name}' >"$work/node.json"
      if ! proxy_request --request PUT --header 'Content-Type: application/json' --data-binary @"$work/node.json" \
          http://localhost/proxies/PROXY >"$work/control-output" 2>"$work/control-error"; then
        reply unavailable null 'Mihomo or the requested provider node is unavailable'
      fi ;;
    *) reply invalid null 'Unknown network action' ;;
  esac
fi
data=$(observe)
reply success "$data"
