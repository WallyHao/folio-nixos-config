action=${1:-}
shift || true
case "$action" in
  list) (( $# == 0 )) || finish invalid null 'Unexpected arguments' ;;
  enable|disable) (( $# == 1 )) || finish invalid null 'Expected one module name' ;;
  *) finish invalid null 'Usage: folio modules list|enable NAME|disable NAME' ;;
esac
load_configuration
if [[ "$action" == list ]]; then
  finish success "$(jq -c '."folio-environment:environment".modules' "$work/normalized.json")"
fi
enabled=false
[[ "$action" != enable ]] || enabled=true
jq --arg name "$1" --argjson enabled "$enabled" \
  '."folio-environment:environment".modules |=
    (if any(.[]; .name==$name) then map(if .name==$name then .enabled=$enabled else . end)
     else . + [{name:$name,enabled:$enabled}] end)' "$work/normalized.json" >"$work/draft.json"
commit_configuration
