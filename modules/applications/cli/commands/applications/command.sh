command_main() (
action=${1:-}; shift || true
case "$action" in init|refresh|list|install|update|remove|reconcile|adopt|rollback|prepare|resume|status) ;; *) finish invalid null 'Usage: folio apps init|refresh|list|install|update|remove|reconcile|adopt|rollback|prepare|resume|status [APPLICATION|REVISION]' ;; esac
application=all
revision=
application_ref=
adopt_files=false
offline=false
request_id=app-$(cat /proc/sys/kernel/random/uuid)
if [[ "$action" == rollback || "$action" == resume || "$action" == status ]]; then
  (( $# > 0 )) || finish invalid null 'Missing application revision or task ID'
  revision=$1; shift
fi
if (( $# > 0 )) && [[ "$1" != --* ]]; then application=$1; shift; fi
[[ "$application" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || finish invalid null 'Invalid application identity'
while (( $# )); do
  case "$1" in
    --adopt-files) adopt_files=true; shift ;;
    --offline) offline=true; shift ;;
    --ref) (( $# >= 2 )) || finish invalid null 'Missing application ref'; application_ref=$2; shift 2 ;;
    --request-id) (( $# >= 2 )) || finish invalid null 'Missing request ID'; request_id=$2; shift 2 ;;
    *) finish invalid null 'Unknown application option' ;;
  esac
done
config() { FOLIO_COMMAND=config FOLIO_JSON=true folio-config "$@"; }
config show >"$work/config-result.json"
jq -e '.status=="success"' "$work/config-result.json" >/dev/null || finish unavailable null 'User configuration is unavailable'
jq '.data.configuration' "$work/config-result.json" >"$work/configuration.json"
if [[ -n "$application_ref" ]]; then
  [[ "$action" == install || "$action" == adopt ]] || finish invalid null '--ref is supported for install/adopt'
  [[ "$application_ref" =~ ^app/[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}/x86_64/[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}$ ]] || finish invalid null 'Invalid application ref'
  case "$application" in
    zen) [[ "$application_ref" == app/app.zen_browser.zen/x86_64/stable ]] || finish invalid null 'Ref does not match zen' ;;
    obs) [[ "$application_ref" == app/com.obsproject.Studio/x86_64/stable ]] || finish invalid null 'Ref does not match obs' ;;
    all) finish invalid null 'Use one application with --ref' ;;
    *) [[ "$application_ref" == "app/$application/x86_64/"* && "$application" != app.zen_browser.zen && "$application" != com.obsproject.Studio ]] || finish invalid null 'Ref does not match application; use zen/obs aliases for these apps' ;;
  esac
  branch=${application_ref##*/}
  if jq -e --arg app "$application" --arg ref "$application_ref" '
    any(."folio-environment:environment".modules[] | select(.name=="applications") |
      ."folio-applications:applications".app[]?; .name==$app and .ref!=$ref)' "$work/configuration.json" >/dev/null; then
    finish conflict null 'Application already uses a different ref; review its saved selection before switching branches'
  fi
  jq --arg app "$application" --arg ref "$application_ref" --arg branch "$branch" '
    ."folio-environment:environment".modules |= map(if .name=="applications" then
      ."folio-applications:applications".app = ((."folio-applications:applications".app // []) |
        if any(.[]; .name==$app) then . else . + [{name:$app,ref:$ref,branch:$branch,selected:true}] end)
      else . end)' "$work/configuration.json" >"$work/with-ref.json"
  mv "$work/with-ref.json" "$work/configuration.json"
fi
if [[ "$application" != all && "$action" != status && "$action" != resume ]]; then
  jq -e --arg app "$application" '."folio-environment:environment".modules[] | select(.name=="applications" and .enabled) |
    ."folio-applications:applications".app[]? | select(.name==$app)' "$work/configuration.json" >/dev/null ||
    finish invalid null 'Application is not selected; use install/adopt APP --ref app/ID/x86_64/BRANCH'
fi
if [[ "$action" == install || "$action" == remove || -n "$application_ref" ]]; then
  selected=true
  [[ "$action" != remove ]] || selected=false
  jq --arg app "$application" --argjson selected "$selected" '
    ."folio-environment:environment".modules |= map(if .name=="applications" then
      ."folio-applications:applications".app |= map(if $app=="all" or .name==$app then .selected=$selected else . end)
      else . end)' "$work/configuration.json" >"$work/desired.json"
  config import "$work/desired.json" --expected-digest "$(jq -er .data.digest "$work/config-result.json")" >"$work/commit-result.json"
  jq -e '.status=="success"' "$work/commit-result.json" >/dev/null || finish conflict null 'Application selection could not be committed'
  config show >"$work/config-result.json"
fi
digest=$(jq -er .data.digest "$work/config-result.json")
rpc() {
  jq -cn --arg action "$1" --arg application "$application" --arg revision "$revision" --arg id "$request_id" \
    --arg digest "$digest" --argjson adopt "$adopt_files" --argjson offline "$offline" \
    -f @requestFilter@ >"$work/request.json"
  if ! timeout --kill-after=2 55 folio-repository user cfg --rpc="$work/request.json" --format json --timeout 50 >"$work/reply.json" 2>"$work/error"; then
    cat "$work/error" >&2
    finish unavailable null 'Applications subscriber is unavailable; enable and apply its user contribution'
  fi
  response=$(jq -ce 'to_entries[0].value' "$work/reply.json") || finish failure null 'Invalid applications reply'
  reply=$(jq -ce '."result-json" | fromjson' <<<"$response") || finish unavailable null 'Applications backend did not return a result'
}
rpc "$action"
task_id=$(jq -r '.taskId // ""' <<<"$reply")
if [[ -n "$task_id" && "$action" != status && $(jq -r .status <<<"$reply") == success ]] && ! "$FOLIO_NO_WAIT"; then
  revision=$task_id
  deadline=$((SECONDS + 1860))
  while (( SECONDS < deadline )); do
    rpc status
    phase=$(jq -r '.data.phase // ""' <<<"$reply")
    case "$phase" in
      succeeded) break ;;
      failed|interrupted) finish "$(jq -r '.data.resultStatus // "failure"' <<<"$reply")" "$(jq -c .data <<<"$reply")" "$(jq -r '.data.error // "Application task failed"' <<<"$reply")" "$task_id" ;;
    esac
    sleep 1
  done
  [[ "$phase" == succeeded ]] || finish unavailable "$(jq -c .data <<<"$reply")" 'Stopped waiting; application task remains recorded' "$task_id"
fi
finish "$(jq -r .status <<<"$reply")" "$(jq -c .data <<<"$reply")" "$(jq -r '.error // ""' <<<"$reply")" "$task_id"
)
command_main "$@"
