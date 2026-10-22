command_main() (
action=${1:-}
shift || true
case "$action" in
  list) (( $# == 0 )) || finish invalid null 'Unexpected arguments' ;;
  enable|disable) (( $# == 1 )) || finish invalid null 'Expected one module name' ;;
  *) finish invalid null 'Usage: folio modules list|enable NAME|disable NAME' ;;
esac
load_configuration
if [[ "$action" == list ]]; then
  finish success "$(jq -cn --arg scope "$FOLIO_SCOPE" --slurpfile catalogue "$FOLIO_CATALOGUE" --slurpfile config "$work/normalized.json" '
    ($config[0]."folio-environment:environment".modules | map({key:.name,value:.}) | from_entries) as $selected |
    [$catalogue[0] | to_entries[] | select(.value.scopes | index($scope)) | .key as $name |
      {name:$name,enabled:($selected[$name].enabled // false),selected:($selected | has($name)),
       scopes:.value.scopes,requirements:(.value.requirements[$scope] // {})}]')"
fi
enabled=false
[[ "$action" != enable ]] || enabled=true
jq --arg name "$1" --argjson enabled "$enabled" \
  '."folio-environment:environment".modules |=
    (if any(.[]; .name==$name) then map(if .name==$name then .enabled=$enabled else . end)
     else . + [{name:$name,enabled:$enabled}] end)' "$work/normalized.json" >"$work/draft.json"
commit_configuration
)
command_main "$@"
