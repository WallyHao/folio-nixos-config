command_main() (
action=${1:-}
shift || true
# shellcheck disable=SC2329 # Called by the subshell's EXIT trap.
preserve_editor_draft() {
  local code=$? directory retained
  if (( code )) && [[ "$action" == edit && -s "$work/draft.json" ]]; then
    directory=${XDG_STATE_HOME:-$HOME/.local/state}/folio/drafts
    if mkdir -p "$directory" && chmod 0700 "$directory"; then
      retained=$(mktemp "$directory/$FOLIO_SCOPE-XXXXXXXX.json")
      if cp "$work/draft.json" "$retained"; then
        printf 'Draft preserved: %s\nReview it, then import with: folio --%s config import %q\n' "$retained" "$FOLIO_SCOPE" "$retained" >&2
      fi
    fi
  fi
  rm -rf "$work"
}
trap preserve_editor_draft EXIT
expected_digest=
if [[ "$action" == import && $# == 3 && "$2" == --expected-digest ]]; then
  expected_digest=$3
  [[ "$expected_digest" =~ ^[a-f0-9]{64}$ ]] || finish invalid null 'Invalid expected digest'
  set -- "$1"
fi
case "$action" in
  show|edit) (( $# == 0 )) || finish invalid null 'Unexpected arguments' ;;
  import|export) (( $# == 1 )) || finish invalid null 'Expected one file path' ;;
  get|explain|unset) (( $# == 1 )) || finish invalid null 'Expected one setting path' ;;
  set) (( $# == 2 )) || finish invalid null 'Expected a setting path and JSON value' ;;
  *) finish invalid null 'Usage: folio config show|edit|import FILE|export FILE|get PATH|explain PATH|set PATH JSON|unset PATH' ;;
esac
load_configuration
[[ -z "$expected_digest" || "$expected_digest" == "$configuration_digest" ]] || finish conflict null 'Desired configuration changed; reload before saving'
case "$action" in
  get)
    value=$(python3 @fields@ get "$1" <"$work/normalized.json" 2>"$work/field-error") ||
      finish invalid null "$(cat "$work/field-error")"
    finish success "$value" ;;
  set|unset)
    python3 @fields@ "$action" "$@" <"$work/normalized.json" >"$work/draft.json" 2>"$work/field-error" ||
      finish invalid null "$(cat "$work/field-error")" ;;
  show|explain)
    # Observation is optional: reads remain useful while subscribers are down.
    if ! timeout --kill-after=2 8 folio-repository "$FOLIO_SCOPE" cfg --export --datastore operational \
        --module folio-environment --format json --timeout 5 >"$work/observed.json" 2>"$work/observation-error"; then
      printf '{}\n' >"$work/observed.json"
    fi
    value=$(python3 @describe@ "$action" "$configuration_digest" "$work/observed.json" "$@" \
      <"$work/normalized.json" 2>"$work/field-error") || finish invalid null "$(cat "$work/field-error")"
    finish success "$value" ;;
  export)
    if ! jq --indent 2 . "$work/normalized.json" >"$1"; then finish failure null 'Export could not be written'; fi
    finish success "$(jq -cn --arg path "$1" '{path:$path}')" ;;
  import)
    if ! jq -e 'select(type == "object")' "$1" >"$work/draft.json"; then
      finish invalid null 'Import must contain a JSON configuration object'
    fi ;;
  edit)
    jq --indent 2 . "$work/normalized.json" >"$work/draft.json"
    read -r -a editor <<<"${VISUAL:-${EDITOR:-emacs}}"
    if ! "${editor[@]}" "$work/draft.json" >&2; then finish failure null 'Editor failed'; fi
    if ! jq -e 'type == "object"' "$work/draft.json" >/dev/null; then
      finish invalid null 'Edited configuration is not a JSON object'
    fi ;;
esac
commit_configuration
)
command_main "$@"
