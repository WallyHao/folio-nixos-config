umask 0077
: "${HOME:?HOME is required}"
: "${FOLIO_SCOPE:?Invoke through folio}"
: "${FOLIO_JSON:?Invoke through folio}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

finish() {
  local status=$1 data=${2:-null} error=${3:-} task_id=${4:-} code
  case "$status" in
    success) code=0 ;; failure) code=1 ;; invalid) code=2 ;; unavailable) code=3 ;; conflict) code=4 ;;
    *) status=failure; error='Invalid backend result'; code=1 ;;
  esac
  if "$FOLIO_JSON"; then
    jq -cn --arg status "$status" --argjson data "$data" --arg error "$error" --arg taskId "$task_id" \
      '{status:$status,data:$data,error:(if $error=="" then null else $error end),
        taskId:(if $taskId=="" then null else $taskId end)}'
  elif (( code )); then
    printf '%s\n' "$error" >&2
  else
    jq . <<<"$data"
  fi
  exit "$code"
}
