scope=user
json=false
environment=portable
emit_error() {
  local status=$1 message=$2 code=$3
  if "$json"; then
    jq -cn --arg status "$status" --arg error "$message" '{status:$status,data:null,error:$error,taskId:null}'
  else
    printf '%s\n' "$message" >&2
  fi
  exit "$code"
}
arguments=()
while (( $# )); do
  case "$1" in
    --json) json=true; shift ;;
    --system) scope=system; shift ;;
    --environment)
      if (( $# < 2 )); then emit_error invalid 'Missing environment name' 2; fi
      environment=$2; shift 2 ;;
    --help|-h) set -- help; arguments=(); break ;;
    --) shift; arguments+=("$@"); break ;;
    *) arguments+=("$1"); shift ;;
  esac
done
if [[ ${1:-} == help || ${#arguments[@]} == 0 ]]; then
  cat <<'HELP'
Usage: folio [--json] [--environment portable] [--system] COMMAND

Commands:
  config show|edit|import FILE|export FILE   Read or durably save desired data
  modules list|enable NAME|disable NAME     Inspect or change desired selection

User configuration operations require the manager subscriber for writes.
Deployment and rollback commands are unavailable until implemented.
HELP
  exit 0
fi
[[ "$environment" == portable ]] || emit_error invalid 'Unknown environment' 2
command=${arguments[0]}
adapter=$(jq -er --arg command "$command" '.[$command].path' @commands@ 2>/dev/null) || {
  case "$command" in
    plan|build|apply|rollback|status) emit_error unavailable 'This command is not implemented yet' 3 ;;
    *) emit_error invalid "Unknown command: $command" 2 ;;
  esac
}
jq -e --arg command "$command" --arg scope "$scope" '.[$command].scopes | index($scope) != null' @commands@ >/dev/null ||
  emit_error invalid "Command does not support $scope scope" 2
export FOLIO_SCOPE=$scope FOLIO_JSON=$json FOLIO_ENVIRONMENT=$environment
exec "$adapter" "${arguments[@]:1}"
