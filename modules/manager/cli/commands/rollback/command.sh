command_main() (
case "$FOLIO_COMMAND" in
  cleanup)
    [[ $# == 0 || ( $# == 1 && $1 == --apply ) ]] || finish invalid null 'Usage: folio cleanup [--apply]'
    code=0
    folio-manager-cleanup "$FOLIO_SCOPE" "$@" >"$work/result.json" 2>"$work/error" || code=$?
    ;;
  rollback)
    [[ $# == 1 || ( $# == 2 && $2 == --rebuild ) ]] || finish invalid null 'Usage: folio rollback REVISION_ID [--rebuild]'
    [[ "$1" =~ ^([a-f0-9]{64}|maintenance-[a-z][a-z0-9-]{0,63})$ ]] || finish invalid null 'Invalid retained revision ID'
    profile=${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager
    [[ "$FOLIO_SCOPE" != system ]] || profile=/nix/var/nix/profiles/system
    artifact=$(readlink -e "$profile") || finish unavailable null 'No selected managed closure'
    metadata=$artifact/folio-home.json
    [[ "$FOLIO_SCOPE" != system ]] || metadata=$artifact/folio-system.json
    bootstrap=$(jq -er .bootstrap "$metadata") || finish unavailable null 'Selected closure has no bootstrap identity'
    transaction=rollback-$(tr -d '-' </proc/sys/kernel/random/uuid)
    code=0
    folio-manager-maintain "$FOLIO_SCOPE" "$bootstrap" rollback "$transaction" "$@" >"$work/result.json" 2>"$work/error" || code=$?
    ;;
  *) finish invalid null 'Unsupported maintenance command' ;;
esac
if (( code )); then
  cat "$work/error" >&2
  status=failure
  case "$code" in 2) status=invalid ;; 3) status=unavailable ;; 4) status=conflict ;; esac
  finish "$status" null "$(cat "$work/error")"
fi
finish success "$(jq -ce .data "$work/result.json")"
)
command_main "$@"
