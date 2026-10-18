# Private manager operation prelude. Each packaged operation receives modeled
# request JSON on stdin and returns only modeled result fields on stdout.
umask 0077
: "${HOME:?HOME is required}"
: "${FOLIO_BOOTSTRAP:?FOLIO_BOOTSTRAP is required}"
scope=${FOLIO_SCOPE:-user}
case "$scope" in
  system) state=/var/lib/folio; runtime=/run/folio ;;
  user)
    : "${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is required}"
    state=${XDG_STATE_HOME:-$HOME/.local/state}/folio
    runtime=$XDG_RUNTIME_DIR/folio ;;
  *) echo 'Unsupported manager scope' >&2; exit 2 ;;
esac
models=$FOLIO_BOOTSTRAP/models/$scope
descriptor_path=$FOLIO_BOOTSTRAP/system-descriptor.json
if [[ -f /run/folio/public/system-descriptor.json ]]; then
  descriptor_path=/run/folio/public/system-descriptor.json
  descriptor_owner=$(stat -c %u "$descriptor_path")
  descriptor_permissions=$(stat -c %a "$descriptor_path")
  if [[ -L "$descriptor_path" || "$descriptor_owner" != 0 ]] || (( (8#$descriptor_permissions & 022) != 0 )); then
    echo 'System descriptor publication has unsafe ownership or permissions' >&2
    exit 1
  fi
fi
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
  folio-repository "$scope" cfg --export --module folio-environment --format json --defaults report-all >"$work/export.json"
  folio-normalize "$models" "$work/export.json"
}
digest_file() {
  local value
  value=$(sha256sum <"$1")
  printf '%s\n' "${value%% *}"
}
configuration_is_saved() {
  folio-repository "$scope" cfg --export --datastore startup --module folio-environment --format json --defaults report-all \
    >"$work/startup.json" || return 1
  folio-normalize "$models" "$work/startup.json" >"$work/startup-normalized.json" || return 1
  [[ $(digest_file "$work/startup-normalized.json") == "$1" ]]
}
nix_as_builder() {
  if [[ "$scope" == system ]]; then
    runuser -u folio-builder -- env -i HOME=/var/lib/folio-builder USER=folio-builder \
      LANG=C.UTF-8 NIX_REMOTE=daemon PATH="$PATH" nix "$@"
  else
    nix "$@"
  fi
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
  folio-repository "$scope" cfg --import="$work/validated.json" --datastore running --module folio-environment --format json
  folio-repository "$scope" cfg --import="$work/validated.json" --datastore startup --module folio-environment --format json
  jq '.phase = (if .phase == "prepared" then "restored" else "saved" end)' "$journal" |
    folio-atomic-write "$journal"
}
