umask 0077
export LC_ALL=C.UTF-8
[[ $(id -u) != 0 && ${HOME:-} == /* && ${XDG_RUNTIME_DIR:-} == /* ]] || exit 3
work=$(mktemp -d "$XDG_RUNTIME_DIR/folio-devices.XXXXXX")
trap 'rm -rf "$work"' EXIT
reply() {
  local status=$1 data=${2:-null} error=${3:-} code
  case "$status" in success) code=0 ;; invalid) code=2 ;; unavailable) code=3 ;; conflict) code=4 ;; *) code=1 ;; esac
  jq -cn --arg status "$status" --argjson data "$data" --arg error "$error" \
    '{status:$status,data:$data,error:(if $error=="" then null else $error end),taskId:null}'
  exit "$code"
}
observe() {
  audio='{"available":false,"backendAvailable":false,"sinks":[]}'
  if timeout --kill-after=1 3 pactl -f json list sinks >"$work/audio.json" 2>"$work/audio-error"; then
    audio=$(jq -ce '{backendAvailable:true,available:(length>0),sinks:map({name,description,mute,volume})}' "$work/audio.json")
  fi
  bluetooth='{"available":false,"backendAvailable":false,"adapters":[]}'
  if timeout --kill-after=1 3 busctl --system --json=short call org.bluez / org.freedesktop.DBus.ObjectManager GetManagedObjects >"$work/bluetooth.json" 2>"$work/bluetooth-error"; then
    bluetooth=$(jq -ce '(.data[0] | keys | map(select(test("^/org/bluez/hci[0-9]+$")))) as $adapters |
      {backendAvailable:true,available:($adapters|length>0),adapters:$adapters}' "$work/bluetooth.json")
  fi
  : >"$work/backlights.jsonl"
  local device current maximum
  shopt -s nullglob
  for device in /sys/class/backlight/*; do
    [[ -r "$device/brightness" && -r "$device/max_brightness" ]] || continue
    read -r current <"$device/brightness"
    read -r maximum <"$device/max_brightness"
    [[ "$current" =~ ^[0-9]+$ && "$maximum" =~ ^[1-9][0-9]*$ ]] || continue
    jq -cn --arg name "${device##*/}" --argjson current "$current" --argjson maximum "$maximum" \
      '{name:$name,current:$current,maximum:$maximum,percent:($current*100/$maximum|floor)}' >>"$work/backlights.jsonl"
  done
  jq -s '{available:(length>0),backlights:.}' "$work/backlights.jsonl" >"$work/brightness.json"
  profile=
  if timeout --kill-after=1 3 powerprofilesctl get >"$work/profile" 2>"$work/profile-error"; then
    profile=$(cat "$work/profile")
    case "$profile" in balanced|power-saver|performance) ;; *) profile= ;; esac
  fi
  memory=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  jq -cn --argjson audio "$audio" --argjson bluetooth "$bluetooth" --slurpfile brightness "$work/brightness.json" \
    --arg profile "$profile" --argjson cpus "$(nproc --all)" --argjson memory "$memory" \
    '{audio:$audio,bluetooth:$bluetooth,brightness:$brightness[0],
      power:{backendAvailable:($profile!=""),profile:(if $profile=="" then null else $profile end),hardware:"unknown"},
      hardware:{logicalCpus:$cpus,memoryKiB:$memory},physicalAcceptance:"unverified"}'
}
cat >"$work/request.json"
action=$(jq -er .action "$work/request.json")
if [[ "$action" != status ]]; then
  exec 9>"$XDG_RUNTIME_DIR/folio-devices.lock"
  flock -x -w 3 9 || reply conflict null 'Device controls are busy'
  command=()
  case "$action" in
    set-volume|set-brightness)
      level=$(jq -er '.level | select(type=="number" and .>=0 and .<=100 and floor==.)' "$work/request.json") || reply invalid null 'Level must be an integer from 0 through 100'
      if [[ "$action" == set-volume ]]; then command=(wpctl set-volume --limit 1.0 @DEFAULT_AUDIO_SINK@ "$level%")
      else command=(brightnessctl --quiet set "$level%"); fi ;;
    adjust-volume|adjust-brightness)
      amount=$(jq -er '.amount | select(type=="number" and .!=0 and .>=(-20) and .<=20 and floor==.)' "$work/request.json") || reply invalid null 'Volume adjustment must be -20..-1 or 1..20'
      suffix=+
      if (( amount < 0 )); then suffix=-; amount=$((-amount)); fi
      if [[ "$action" == adjust-volume ]]; then command=(wpctl set-volume --limit 1.0 @DEFAULT_AUDIO_SINK@ "$amount%$suffix")
      else command=(brightnessctl --quiet set "$amount%$suffix"); fi ;;
    toggle-mute) command=(wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle) ;;
    set-power-profile)
      profile=$(jq -er .profile "$work/request.json")
      case "$profile" in balanced|power-saver|performance) ;; *) reply invalid null 'Unknown power profile' ;; esac
      command=(powerprofilesctl set "$profile") ;;
    *) reply invalid null 'Unknown device action' ;;
  esac
  if ! timeout --kill-after=1 5 "${command[@]}" >"$work/control-output" 2>"$work/control-error"; then
    reply unavailable null "Device backend or authorization is unavailable: $(cat "$work/control-error")"
  fi
fi
data=$(observe)
reply success "$data"
