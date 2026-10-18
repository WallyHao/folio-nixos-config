scope=user
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
arguments=()
while (( $# )); do
  case "$1" in
    --json) json=true; shift ;;
    --no-wait) no_wait=true; shift ;;
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
  plan [--source DIRECTORY]                Freeze configuration and source
  build|apply PLAN_ID [--request-id ID]     Build or activate a recorded plan
  status [TASK_ID]                         Query observed state or a task
  rollback REVISION_ID [--rebuild]          Restore retained desired data and closure
  cleanup [--apply]                        Preview or remove unreferenced deployment records
  vm build|start|stop|status|cleanup ID     Manage a disposable user VM
  --system system reboot|poweroff          Accept a guest power request

User configuration operations require the manager subscriber for writes.
Build/apply wait by default; --no-wait returns the durable task ID.
Offline system rollback/cleanup require root. User maintenance runs as its owner.
HELP
  exit 0
fi
[[ "$environment" == portable ]] || emit_error invalid 'Unknown environment' 2
command=${arguments[0]}
if "$no_wait" && [[ "$command" != build && "$command" != apply && "$command" != vm ]]; then
  emit_error invalid '--no-wait applies to deployment tasks and VM builds' 2
fi
adapter=$(jq -er --arg command "$command" '.[$command].path' @commands@ 2>/dev/null) || {
  case "$command" in
    plan|build|apply|rollback|status) emit_error unavailable 'This command is not implemented yet' 3 ;;
    *) emit_error invalid "Unknown command: $command" 2 ;;
  esac
}
jq -e --arg command "$command" --arg scope "$scope" '.[$command].scopes | index($scope) != null' @commands@ >/dev/null ||
  emit_error invalid "Command does not support $scope scope" 2
export FOLIO_SCOPE=$scope FOLIO_JSON=$json FOLIO_ENVIRONMENT=$environment FOLIO_COMMAND=$command FOLIO_NO_WAIT=$no_wait
exec "$adapter" "${arguments[@]:1}"
