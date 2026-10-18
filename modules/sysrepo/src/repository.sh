if (( $# < 2 )); then
  echo 'Usage: folio-repository user|system init MODELS DEFAULTS | ctl ARGS... | cfg ARGS...' >&2
  exit 2
fi
scope=$1
action=$2
shift 2
umask 0077
case "$scope" in
  system)
    umask 0007
    state=/var/lib/folio
    runtime=/run/folio
    prefix=folio_system
    ;;
  user)
    : "${HOME:?HOME is required}"
    : "${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is required}"
    state=${XDG_STATE_HOME:-$HOME/.local/state}/folio
    runtime=$XDG_RUNTIME_DIR/folio
    prefix=folio_user_$(id -u)
    ;;
  *) echo "Unsupported scope: $scope" >&2; exit 2 ;;
esac
case "$state:$runtime" in
  /*:/*) ;;
  *) echo 'State and runtime roots must be absolute paths' >&2; exit 2 ;;
esac

# Every client uses the same pinned library and scoped instance. Never inherit a
# caller's alternate repository, plugin directory or shared-memory namespace.
export SYSREPO_REPOSITORY_PATH=$state/sysrepo
export SYSREPO_SHM_DIR=$runtime/sysrepo
export SYSREPO_SHM_PREFIX=$prefix
unset SYSREPO_PLUGINS_PATH

if [[ "$action" == init ]]; then mkdir -p "$state" "$runtime"; fi
[[ -d "$state" ]] || { echo 'Repository is not initialized' >&2; exit 3; }
exec 5<>"$state/repository.lock"
if [[ "$scope" == system && $(id -u) == 0 ]]; then
  chgrp folio-operators "$state/repository.lock"
  chmod 0660 "$state/repository.lock"
fi
flock -s -w 30 5
if [[ -e "$state/schema-transaction.json" ]]; then
  if [[ "$action" != init ]]; then
    echo 'Repository is under offline schema maintenance' >&2; exit 3
  fi
  case "$(jq -er .phase "$state/schema-transaction.json")" in
    installed|restored-pending-activation) ;;
    *) echo 'Schema transaction requires offline recovery before initialization' >&2; exit 3 ;;
  esac
fi

case "$action" in
  ctl) exec sysrepoctl "$@" ;;
  cfg) exec sysrepocfg "$@" ;;
  init) ;;
  *) echo "Unknown repository operation: $action" >&2; exit 2 ;;
esac
if (( $# != 2 )); then
  echo 'Usage: folio-repository SCOPE init MODELS DEFAULTS' >&2
  exit 2
fi
models=$(realpath -e -- "$1")
defaults=$(realpath -e -- "$2")
jq -e --arg scope "$scope" '."folio-environment:environment".scope == $scope' "$defaults" >/dev/null
mkdir -p "$state" "$runtime"
exec 9>"$state/initialize.lock"
flock -x -w 30 9
mkdir -p "$SYSREPO_REPOSITORY_PATH" "$SYSREPO_SHM_DIR" \
  "$state/configuration" "$state/deployments" "$state/backups"
if [[ "$scope" == system ]]; then
  chmod 0750 "$state"
  chmod 0755 "$runtime"
  # Inherit the provisioned operator group even for clients whose primary group
  # differs. The same library can still serve private ordinary-user instances.
  chmod 2770 "$SYSREPO_REPOSITORY_PATH" "$SYSREPO_SHM_DIR"
  chmod 0700 "$state/configuration" "$state/deployments" "$state/backups"
fi

identity=$(mktemp "$runtime/models.XXXXXX")
trap 'rm -f "$identity"' EXIT
for model in "$models"/*.yang; do
  printf '%s ' "$(basename "$model")" >>"$identity"
  sha256sum <"$model" >>"$identity"
done
sysrepoctl --version >>"$identity"
if [[ -e "$state/model-identity" ]]; then
  if ! cmp -s "$identity" "$state/model-identity"; then
    echo 'Model/library identity changed; an explicit offline schema upgrade is required' >&2
    exit 4
  fi
else
  # Do not adopt or overwrite a pre-existing repository without provenance.
  if [[ -e "$SYSREPO_REPOSITORY_PATH/yang/folio-environment@2026-10-18.yang" ]]; then
    echo 'Existing repository has no model identity; offline recovery is required' >&2
    exit 4
  fi
  mv "$identity" "$state/model-identity"
fi

if [[ -e "$state/initialized" ]]; then
  # Initial defaults are not a second desired configuration authority.
  sysrepocfg --export --datastore startup --module folio-environment --format json |
    jq -e --arg scope "$scope" '."folio-environment:environment".scope == $scope' >/dev/null
  exit 0
fi
if sysrepoctl --list | awk '$1 == "folio-environment" { found=1 } END { exit !found }'; then
  # Installation is atomic in sysrepo. A crash after installation but before the
  # marker must not replace already accepted startup data.
  sysrepocfg --export --datastore startup --module folio-environment --format json |
    jq -e --arg scope "$scope" '."folio-environment:environment".scope == $scope' >/dev/null
else
  install_args=()
  for model in "$models"/*.yang; do
    permissions=0600
    [[ "$scope" != system ]] || permissions=0660
    install_args+=(--install "$model" --permissions "$permissions")
  done
  sysrepoctl "${install_args[@]}" --search-dirs "$models" --init-data "$defaults"
fi
touch "$state/initialized"
