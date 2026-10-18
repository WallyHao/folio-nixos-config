# Private manager operation prelude. Each packaged operation receives modeled
# request JSON on stdin and returns only modeled result fields on stdout.
umask 0077
: "${HOME:?HOME is required}"
: "${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is required}"
: "${FOLIO_BOOTSTRAP:?FOLIO_BOOTSTRAP is required}"
state=${XDG_STATE_HOME:-$HOME/.local/state}/folio
runtime=$XDG_RUNTIME_DIR/folio
models=$FOLIO_BOOTSTRAP/models/user
mkdir -p "$state/configuration" "$runtime"
work=$(mktemp -d "$runtime/operation.XXXXXX")
trap 'rm -rf "$work"' EXIT
cat >"$work/request.json"

reply() {
  local status=$1 error=${2:-} digest=${3:-}
  jq -cn --arg status "$status" --arg error "$error" --arg digest "$digest" \
    '{status:$status} + (if $error == "" then {} else {error:$error} end)
      + (if $digest == "" then {} else {digest:$digest} end)'
}
lock_configuration() {
  exec 9>"$state/mutation.lock"
  flock -x -w 15 9
}
current_configuration() {
  folio-repository user cfg --export --module folio-environment --format json --defaults report-all >"$work/export.json"
  folio-normalize "$models" "$work/export.json"
}
digest_file() {
  local value
  value=$(sha256sum <"$1")
  printf '%s\n' "${value%% *}"
}
recover_configuration() {
  local journal=$state/configuration/transaction.json phase expected
  [[ -e "$journal" ]] || return 0
  phase=$(jq -er .phase "$journal")
  case "$phase" in
    prepared)
      jq -cS .before "$journal" >"$work/recovered.json"
      expected=$(jq -er .beforeDigest "$journal") ;;
    accepted)
      jq -cS .after "$journal" >"$work/recovered.json"
      expected=$(jq -er .afterDigest "$journal") ;;
    saved|restored) return 0 ;;
    *) echo "Unknown configuration journal phase: $phase" >&2; return 1 ;;
  esac
  folio-normalize "$models" "$work/recovered.json" >"$work/validated.json"
  if [[ $(digest_file "$work/validated.json") != "$expected" ]]; then
    echo 'Configuration journal digest mismatch; offline recovery is required' >&2
    return 1
  fi
  folio-repository user cfg --import="$work/validated.json" --datastore running --module folio-environment --format json
  folio-repository user cfg --import="$work/validated.json" --datastore startup --module folio-environment --format json
  jq '.phase = (if .phase == "prepared" then "restored" else "saved" end)' "$journal" |
    folio-atomic-write "$journal"
}
