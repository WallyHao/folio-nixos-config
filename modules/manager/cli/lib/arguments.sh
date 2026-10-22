scope=user
scope_explicit=false
json=false
environment=portable
no_wait=false
emit_error() {
  local status=$1 message=$2 code=$3
  if "$json"; then
    jq -cn --arg status "$status" --arg error "$message" '{status:$status,data:null,error:$error,taskId:null}'
  else
    printf '%s\n' "$message" >&2
  fi
  exit "$code"
}
parse_arguments() {
  arguments=()
  help_requested=false
while (( $# )); do
  case "$1" in
    --json) json=true; shift ;;
    --no-wait) no_wait=true; shift ;;
    --system) scope=system; scope_explicit=true; shift ;;
    --user) scope=user; scope_explicit=true; shift ;;
    --environment)
      if (( $# < 2 )); then emit_error invalid 'Missing environment name' 2; fi
      environment=$2; shift 2 ;;
    --help|-h) help_requested=true; shift ;;
    --) shift; arguments+=("$@"); break ;;
    *) arguments+=("$1"); shift ;;
  esac
done
  if [[ ${arguments[0]:-} == help ]]; then arguments=("${arguments[@]:1}"); help_requested=true; fi
  if (( ${#arguments[@]} == 0 )); then help_requested=true; fi
}
