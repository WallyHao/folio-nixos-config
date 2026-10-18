umask 0077
export LC_ALL=C.UTF-8
unset FLATPAK_USER_DIR FLATPAK_SYSTEM_DIR FLATPAK_CONFIG_DIR
[[ $(id -u) != 0 ]] || { echo 'Applications require an ordinary provisioned user' >&2; exit 3; }
: "${HOME:?}" "${XDG_RUNTIME_DIR:?}" "${FOLIO_BOOTSTRAP:?}"
state=${XDG_STATE_HOME:-$HOME/.local/state}/folio
app_state=$state/applications
flatpak_root=${XDG_DATA_HOME:-$HOME/.local/share}/flatpak
[[ "$HOME" == /* && "$state" == /* && "$flatpak_root" == /* && "$XDG_RUNTIME_DIR" == /* ]] || exit 2
mkdir -p "$app_state/"{tasks,owned,revisions,files,roots,prepared} "$XDG_RUNTIME_DIR/folio"
work=$(mktemp -d "$XDG_RUNTIME_DIR/folio/applications.XXXXXX")
trap 'rm -rf "$work"' EXIT
result() {
  local status=$1 data=${2:-null} message=${3:-} task=${4:-} code
  case "$status" in success) code=0 ;; failure) code=1 ;; invalid) code=2 ;; unavailable) code=3 ;; conflict) code=4 ;; *) code=1 ;; esac
  jq -cn --arg status "$status" --argjson data "$data" --arg error "$message" --arg task "$task" \
    '{status:$status,data:$data,error:(if $error=="" then null else $error end),taskId:(if $task=="" then null else $task end)}'
  exit "$code"
}
hash_file() { local value; value=$(sha256sum <"$1"); printf '%s\n' "${value%% *}"; }
configuration() {
  folio-repository user cfg --export --module folio-environment --format json --defaults report-all >"$work/export.json"
  folio-normalize "$FOLIO_BOOTSTRAP/models/user" "$work/export.json"
}
lock_mutation() {
  exec 9>"$state/mutation.lock"; flock -x -w 10 9 || result conflict null 'Configuration is busy'
  exec 7>"$app_state/mutation.lock"; flock -x -w 10 7 || result conflict null 'Applications are busy'
  [[ ! -e "$state/schema-transaction.json" ]] || result conflict null 'Finish offline schema recovery first'
  shopt -s nullglob
  for pending in "$state"/offline-coordinator-*.json; do
    jq -e '.phase=="complete" or .phase=="restored" or .phase=="aborted"' "$pending" >/dev/null ||
      result conflict null 'Finish offline maintenance first'
  done
}
# Shared with the worker; the RPC dispatcher does not resolve IDs itself.
# shellcheck disable=SC2329
app_id() {
  case "$1" in zen) printf '%s\n' app.zen_browser.zen ;; obs) printf '%s\n' com.obsproject.Studio ;; *) return 2 ;; esac
}
inventory() {
  local kind ref remote runtime commit
  : >"$work/inventory.jsonl"
  for kind in app runtime; do
    flatpak list --user "--$kind" --columns=ref:full,origin:full,runtime:full >"$work/inventory.tsv"
    while IFS=$'\t' read -r ref remote runtime; do
      [[ -n "$ref" ]] || continue
      [[ "$ref" == "$kind/"* ]] || ref=$kind/$ref
      # The list 'active' column is abbreviated even with :full in this version.
      # info's dedicated machine option returns the entire deployed commit.
      commit=$(flatpak info --user --show-commit "$ref") || return 1
      [[ "$commit" =~ ^[a-f0-9]{64}$ ]] || return 1
      jq -cn --arg ref "$ref" --arg remote "$remote" --arg runtime "$runtime" --arg commit "$commit" \
        '{ref:$ref,commit:$commit,remote:$remote,runtime:$runtime}' >>"$work/inventory.jsonl"
    done <"$work/inventory.tsv"
  done
  jq -s 'sort_by(.ref)' "$work/inventory.jsonl"
}
# shellcheck disable=SC2329
cached_refs() {
  [[ -d "$flatpak_root/repo" ]] || { printf '[]\n'; return; }
  ostree --repo="$flatpak_root/repo" refs --revision >"$work/refs.tsv"
  jq -Rn '[inputs | split("\t") | select(length==2 and (.[0]|startswith("flathub:"))) |
    {ref:(.[0]|ltrimstr("flathub:")),commit:.[1]}] | sort_by(.ref)' <"$work/refs.tsv"
}
manifest() {
  local artifact
  artifact=$(readlink -e "${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager") || return 1
  [[ "$artifact" =~ ^/nix/store/[a-z0-9]{32}-[^/]+$ && -f "$artifact/folio-applications.json" ]] || return 1
  jq -e --arg digest "$configuration_digest" --arg account "$(id -un)" --arg home "$HOME" \
    '.format==1 and .scope=="user" and .configurationDigest==$digest and .account==$account and .home==$home' \
    "$artifact/folio-applications.json" >/dev/null || return 1
  printf '%s\n' "$artifact"
}
start_task() {
  local id=$1 worker
  worker=$(jq -er .worker "$app_state/tasks/$id.json")
  [[ "$worker" =~ ^/nix/store/[a-z0-9]{32}-[^/]+/bin/folio-applications-worker$ && -x "$worker" ]] || return 1
  systemctl --user is-active --quiet "folio-app-task-$id.service" && return 0
  systemd-run --user --collect --quiet --service-type=exec --unit="folio-app-task-$id" \
    --property=RuntimeMaxSec=1860 --property=TimeoutStopSec=10 \
    --setenv="HOME=$HOME" --setenv="USER=$(id -un)" --setenv="XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" \
    --setenv="XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}" \
    --setenv="XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}" \
    --setenv="XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}" \
    --setenv="XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}" --setenv="FOLIO_BOOTSTRAP=$FOLIO_BOOTSTRAP" \
    "$worker" "$id"
}
