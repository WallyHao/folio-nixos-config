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
load_configuration() {
  if ! folio-repository "$FOLIO_SCOPE" cfg --export --module folio-environment --format json --defaults report-all \
      >"$work/configuration.json" 2>"$work/error"; then
    cat "$work/error" >&2
    finish unavailable null 'Desired configuration is unavailable'
  fi
  # Current schema defaults are already emitted by sysrepo. Canonicalize the
  # schema-known lists using the same representation as the manager normalizer.
  jq -cS -f @normalizeFilter@ "$work/configuration.json" >"$work/normalized.json"
  configuration_digest=$(sha256sum <"$work/normalized.json")
  configuration_digest=${configuration_digest%% *}
}
commit_configuration() {
  jq -cn --arg digest "$configuration_digest" --slurpfile configuration "$work/draft.json" \
    '{"folio-environment:configuration-commit":{"expected-digest":$digest,configuration:$configuration[0]}}' >"$work/rpc.json"
  if ! timeout --kill-after=2 32 folio-repository "$FOLIO_SCOPE" cfg \
      --rpc="$work/rpc.json" --format json --timeout 30 >"$work/result.json" 2>"$work/error"; then
    cat "$work/error" >&2
    if [[ $(cat "$work/error") == *'no matching subscribers'* ]]; then
      finish unavailable null 'Manager subscriber is unavailable'
    fi
    finish failure null 'Configuration RPC failed'
  fi
  result=$(jq -ce '."folio-environment:configuration-commit"' "$work/result.json") ||
    finish failure null 'Invalid manager reply'
  status=$(jq -er .status <<<"$result") || finish failure null 'Missing manager status'
  error=$(jq -r '.error // ""' <<<"$result")
  digest=$(jq -r '.digest // ""' <<<"$result")
  finish "$status" "$(jq -cn --arg digest "$digest" 'if $digest=="" then null else {digest:$digest} end')" "$error"
}
