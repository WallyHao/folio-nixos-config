command_main() (
action=${1:-}
shift || true
case "$action" in
  show|edit) (( $# == 0 )) || finish invalid null 'Unexpected arguments' ;;
  import|export) (( $# == 1 )) || finish invalid null 'Expected one file path' ;;
  *) finish invalid null 'Usage: folio config show|edit|import FILE|export FILE' ;;
esac
load_configuration
case "$action" in
  show)
    finish success "$(jq -cn --slurpfile configuration "$work/normalized.json" --arg digest "$configuration_digest" \
      '{configuration:$configuration[0],digest:$digest}')" ;;
  export)
    if ! cat "$work/normalized.json" >"$1"; then finish failure null 'Export could not be written'; fi
    finish success "$(jq -cn --arg path "$1" '{path:$path}')" ;;
  import)
    if ! jq -e 'select(type == "object")' "$1" >"$work/draft.json"; then
      finish invalid null 'Import must contain a JSON configuration object'
    fi ;;
  edit)
    cp "$work/normalized.json" "$work/draft.json"
    read -r -a editor <<<"${VISUAL:-${EDITOR:-emacs}}"
    if ! "${editor[@]}" "$work/draft.json" >&2; then finish failure null 'Editor failed'; fi
    if ! jq -e 'type == "object"' "$work/draft.json" >/dev/null; then
      finish invalid null 'Edited configuration is not a JSON object'
    fi ;;
esac
commit_configuration
)
command_main "$@"
