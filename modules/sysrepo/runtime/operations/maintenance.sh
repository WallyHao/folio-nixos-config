# Offline repository primitives. The manager owns service quiescing and paired
# closure activation; this module owns model/data validation and repository swaps.
umask 0077
(( $# >= 3 )) || { echo 'Usage: folio-repository-maintain user|system ACTION ID [ARGUMENTS]' >&2; exit 2; }
scope=$1 action=$2 transaction_id=$3; shift 3
[[ "$transaction_id" =~ ^[a-z][a-z0-9-]{0,63}$ ]] || exit 2
case "$scope" in
  user)
    state=${XDG_STATE_HOME:-$HOME/.local/state}/folio
    runtime=${XDG_RUNTIME_DIR:?}/folio
    prefix=folio_user_$(id -u) ;;
  system)
    [[ $(id -u) == 0 ]] || { echo 'System repository maintenance requires root' >&2; exit 3; }
    state=/var/lib/folio runtime=/run/folio prefix=folio_system ;;
  *) exit 2 ;;
esac
[[ "$state" == /* && "$runtime" == /* && ! -L "$state/sysrepo" ]] || exit 3
[[ -d "$state/sysrepo" || "$action" == restore ]] || exit 3
backup=$state/backups/repositories/$transaction_id
record=$backup/transaction.json
guard=$state/schema-transaction.json
work=$(mktemp -d "$runtime/maintenance.XXXXXX")
emit() {
  local status=$1 message=${2:-} code=${3:-0} data=null
  trap - EXIT
  [[ ! -f "$record" ]] || data=$(jq -c . "$record")
  rm -rf "$work"
  jq -cn --arg status "$status" --arg error "$message" --argjson data "$data" \
    '{status:$status,data:$data,error:(if $error=="" then null else $error end)}'
  exit "$code"
}
trap 'emit failure "Offline repository operation failed; retain the transaction and inspect its journal" 1' EXIT
# A manager coordinator can hold this same open file description across all
# phases and activation. Standalone invocations acquire the identical lock.
if [[ $(readlink /proc/self/fd/9 2>/dev/null || true) != "$state/mutation.lock" ]]; then exec 9>"$state/mutation.lock"; fi
flock -x -w 30 9
case "$action" in
  finalize|inspect) ;;
  *) folio-repository-quiescent "$state/sysrepo" "$backup/live-repository" ||
       emit conflict 'Stop all subscribers and clients before offline repository maintenance' 4 ;;
esac
exec 5>"$state/repository.lock"
if [[ "$scope" == system ]]; then chgrp folio-operators "$state/repository.lock"; chmod 0660 "$state/repository.lock"; fi
case "$action" in finalize|inspect) ;; *) flock -x -w 30 5 ;; esac
exec 8>"$state/initialize.lock"
flock -x -w 30 8
export SYSREPO_REPOSITORY_PATH=$state/sysrepo SYSREPO_SHM_DIR=$runtime/sysrepo SYSREPO_SHM_PREFIX=$prefix
unset SYSREPO_PLUGINS_PATH
if [[ -e "$guard" ]] && [[ $(jq -er .id "$guard") != "$transaction_id" ]]; then
  emit conflict 'Another schema transaction requires offline recovery' 4
fi
immutable_directory() { [[ "$1" =~ ^/nix/store/[a-z0-9]{32}-[^/]+$ && -d "$1" ]]; }
artifact_identity() {
  local artifact=$1 bootstrap=$2 configuration=$3 metadata digest
  immutable_directory "$artifact" || return 1
  digest=$(sha256sum <"$configuration"); digest=${digest%% *}
  if [[ "$scope" == user ]]; then
    metadata=$artifact/folio-home.json
    [[ -x "$artifact/activate" && -f "$metadata" ]] || return 1
    jq -e --arg account "$(id -un)" --arg home "$HOME" --arg digest "$digest" \
      --arg bootstrap "$bootstrap" --slurpfile configuration "$configuration" \
      '.format==1 and .scope=="user" and .account==$account and .home==$home and
       .account==$configuration[0]."folio-environment:environment".account and
       .bootstrap==$bootstrap and .configurationDigest==$digest' "$metadata" >/dev/null
  else
    metadata=$artifact/folio-system.json
    [[ -x "$artifact/bin/switch-to-configuration" && -f "$metadata" ]] || return 1
    jq -e --arg bootstrap "$bootstrap" --arg digest "$digest" --slurpfile configuration "$configuration" \
      '.format==1 and .scope=="system" and .bootstrap==$bootstrap and
       .environment==$configuration[0]."folio-environment:environment".name and
       .configuration==$configuration[0] and .configurationDigest==$digest' "$metadata" >/dev/null
  fi
}
model_identity() {
  local directory=$1 model
  for model in "$directory/"*.yang; do
    printf '%s ' "$(basename "$model")"
    sha256sum <"$model"
  done
  sysrepoctl --version
}
inventory() {
  local bootstrap=$1 model revision name hash
  for model in "$bootstrap/models/$scope/"*.yang; do
    name=$(basename "$model" .yang); name=${name%%@*}
    revision=$(awk '$1=="revision" {gsub(/[";]/,"",$2);print $2;exit}' "$model")
    [[ "$revision" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
    hash=$(sha256sum <"$model"); hash=${hash%% *}
    jq -cn --arg name "$name" --arg revision "$revision" --arg sha256 "$hash" \
      '{name:$name,revision:$revision,sha256:$sha256}'
  done | jq -sS 'sort_by(.name)'
}
quiescent() {
  folio-repository-quiescent "$state/sysrepo" "$backup/live-repository" ||
    emit conflict 'Stop all subscribers and clients before offline repository maintenance' 4
}
phase() {
  jq --arg phase "$1" '.phase=$phase' "$record" | folio-atomic-write "$record"
}
write_guard() {
  jq --arg phase "$1" '{format:1,id,scope,backup,phase:$phase,oldBootstrap,newBootstrap,oldArtifact,newArtifact}' "$record" |
    folio-atomic-write "$guard"
}
reset_runtime() {
  [[ ! -L "$runtime/sysrepo" ]]
  rm -rf "$runtime/sysrepo"
  mkdir "$runtime/sysrepo"
  if [[ "$scope" == system ]]; then chgrp folio-operators "$runtime/sysrepo"; chmod 2770 "$runtime/sysrepo"; fi
}
candidate_command() {
  (if [[ "$scope" == system ]]; then umask 0007; fi
    export SYSREPO_REPOSITORY_PATH=$backup/candidate-repository
    export SYSREPO_SHM_DIR=$backup/candidate-runtime
    SYSREPO_SHM_PREFIX=folio_candidate_$(id -u); export SYSREPO_SHM_PREFIX
    # The JSON datastore replaces startup files using the caller's primary
    # group. Match the provisioned system service even during init-data writes.
    if [[ "$scope" == system ]]; then setpriv --regid folio-operators --keep-groups "$@"
    else "$@"; fi)
}
migrate_document() {
  local document=$1 old target entry name target_name from to hash target_hash transform count hop next_revision next_name
  cp "$document" "$work/migrating.json"
  while IFS= read -r old; do
    name=$(jq -er .name <<<"$old")
    from=$(jq -er .revision <<<"$old"); hash=$(jq -er .sha256 <<<"$old")
    target_name=$name
    if ! target=$(jq -ce --arg name "$name" '.[] | select(.name==$name)' "$backup/new-models.json"); then
      # Model retirement requires an exact, hash-bound replacement declaration.
      # Never silently drop a removed module or infer its destination by name.
      entry=$(jq -c --arg name "$name" --arg from "$from" --arg hash "$hash" \
        '[.[] | select(.module==$name and .from==$from and .fromSha256==$hash and (.toModule | type=="string"))]' \
        "$new_bootstrap/migrations.json")
      [[ $(jq length <<<"$entry") == 1 ]] || emit unavailable 'Removing a model requires an explicit supported migration' 3
      target_name=$(jq -er '.[0].toModule' <<<"$entry")
      target=$(jq -ce --arg name "$target_name" '.[] | select(.name==$name)' "$backup/new-models.json") ||
        emit unavailable 'Replacement model is absent from the target bootstrap' 3
    fi
    to=$(jq -er .revision <<<"$target"); target_hash=$(jq -er .sha256 <<<"$target")
    for (( hop=0; hop<32; hop++ )); do
      [[ "$name" != "$target_name" || "$from" != "$to" || "$hash" != "$target_hash" ]] || break
      [[ "$from" != "$to" ]] || emit invalid 'A model changed without a new YANG revision' 2
      entry=$(jq -c --arg name "$name" --arg from "$from" --arg hash "$hash" \
        '[.[] | select(.module==$name and .from==$from and .fromSha256==$hash)]' "$new_bootstrap/migrations.json")
      count=$(jq length <<<"$entry")
      [[ "$count" == 1 ]] || emit unavailable 'No unique module-owned migration matches the installed revision and hash' 3
      next_name=$(jq -er '.[0].toModule // .[0].module' <<<"$entry")
      [[ "$next_name" == "$name" || "$next_name" == "$target_name" ]] ||
        emit invalid 'Migration changes the declared replacement model' 2
      transform=$(jq -er '.[0].transform' <<<"$entry")
      [[ "$transform" =~ ^/nix/store/[a-z0-9]{32}-[^/]+/bin/[a-zA-Z0-9-]+$ && -x "$transform" ]]
      timeout --kill-after=2 20 "$transform" <"$work/migrating.json" >"$work/migrated.json"
      jq -e 'type=="object"' "$work/migrated.json" >/dev/null
      mv "$work/migrated.json" "$work/migrating.json"
      next_revision=$(jq -er '.[0].to' <<<"$entry")
      [[ "$next_revision" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ && "$next_revision" > "$from" ]] ||
        emit invalid 'Migration revisions must advance monotonically' 2
      name=$next_name; from=$next_revision; hash=$(jq -er '.[0].toSha256' <<<"$entry")
    done
    [[ "$name" == "$target_name" && "$from" == "$to" && "$hash" == "$target_hash" ]] || emit unavailable 'Migration chain does not reach the target revision' 3
  done < <(jq -c '.[]' "$backup/old-models.json")
  folio-normalize "$new_bootstrap/models/$scope" "$work/migrating.json" >"$document"
}
case "$action" in
  snapshot)
    [[ $# == 2 && ! -e "$backup" ]] || emit conflict 'Snapshot ID already exists or arguments are invalid' 4
    old_bootstrap=$1 old_artifact=$2
    immutable_directory "$old_bootstrap"; immutable_directory "$old_artifact"
    model_identity "$old_bootstrap/models/$scope" >"$work/model-identity"
    cmp "$work/model-identity" "$state/model-identity"
    quiescent
    if [[ -f "$state/configuration/transaction.json" ]]; then
      jq -e '.phase=="saved" or .phase=="restored"' "$state/configuration/transaction.json" >/dev/null ||
        emit conflict 'Recover the configuration journal before taking an upgrade snapshot' 4
    fi
    mkdir -p "$backup"
    sync "$state/backups" "$state/backups/repositories" "$backup"
    sysrepocfg --export --datastore startup --module folio-environment --format json --defaults report-all >"$work/startup.json"
    sysrepocfg --export --datastore running --module folio-environment --format json --defaults report-all >"$work/running.json"
    for datastore in startup running; do
      folio-normalize "$old_bootstrap/models/$scope" "$work/$datastore.json" >"$backup/$datastore.json"
      sync "$backup/$datastore.json"
    done
    cp -a "$state/sysrepo" "$backup/repository"
    cp "$state/model-identity" "$backup/model-identity"
    [[ ! -f "$state/configuration/transaction.json" ]] || cp "$state/configuration/transaction.json" "$backup/configuration-journal.json"
    [[ ! -f "$state/deployments/current.json" ]] || cp "$state/deployments/current.json" "$backup/deployment.json"
    inventory "$old_bootstrap" >"$backup/old-models.json"
    nix-store --realise "$old_bootstrap" --add-root "$backup/bootstrap-root" --indirect >/dev/null
    nix-store --realise "$old_artifact" --add-root "$backup/artifact-root" --indirect >/dev/null
    sync -f "$backup"
    jq -cnS --arg id "$transaction_id" --arg scope "$scope" --arg backup "$backup" \
      --arg bootstrap "$old_bootstrap" --arg artifact "$old_artifact" \
      '{format:1,id:$id,scope:$scope,backup:$backup,phase:"backed-up",oldBootstrap:$bootstrap,oldArtifact:$artifact}' |
      folio-atomic-write "$record" ;;
  prepare|prepare-revision)
    [[ -f "$record" ]] || emit invalid 'Prepare requires a snapshot and target bootstrap' 2
    if [[ "$action" == prepare ]]; then [[ $# == 1 ]] || emit invalid 'Prepare requires a target bootstrap' 2
    else [[ $# == 2 ]] || emit invalid 'Prepare-revision requires a target bootstrap and retained revision' 2; fi
    case "$(jq -er .phase "$record")" in
      backed-up|preparing) ;;
      *) emit conflict 'Snapshot is not ready for preparation' 4 ;;
    esac
    # Retain incomplete candidates as evidence before an explicit retry.
    if [[ -e "$backup/candidate-repository" || -e "$backup/candidate-runtime" ]]; then
      attempt=$(mktemp -d "$backup/failed-preparation.XXXXXX")
      for path in candidate-repository candidate-runtime new-startup.json new-running.json new-models.json new-model-identity; do
        [[ ! -e "$backup/$path" ]] || mv "$backup/$path" "$attempt/$path"
      done
      sync -f "$backup"
    fi
    phase preparing
    new_bootstrap=$1; immutable_directory "$new_bootstrap"
    inventory "$new_bootstrap" >"$backup/new-models.json"
    if [[ "$action" == prepare ]]; then
      cp "$backup/startup.json" "$backup/new-startup.json"
      cp "$backup/running.json" "$backup/new-running.json"
      migrate_document "$backup/new-startup.json"
      migrate_document "$backup/new-running.json"
    else
      revision=$2
      [[ "$revision" == "$state/deployments/revisions/"* && -f "$revision" && ! -L "$revision" ]] ||
        emit invalid 'Rollback requires a retained scoped revision' 2
      jq -e --arg scope "$scope" --slurpfile identities "$new_bootstrap/identities.json" \
        '.format==1 and .scope==$scope and .models==$identities[0].models[$scope] and .tools==$identities[0].tools' \
        "$revision" >/dev/null || emit unavailable 'Retained models or tool identities require a compatible rebuild' 3
      jq -cS .configuration "$revision" >"$work/revision.json"
      folio-normalize "$new_bootstrap/models/$scope" "$work/revision.json" >"$backup/new-running.json"
      revision_digest=$(sha256sum <"$backup/new-running.json"); revision_digest=${revision_digest%% *}
      [[ "$revision_digest" == "$(jq -er .configurationDigest "$revision")" ]] || emit invalid 'Retained configuration digest mismatch' 2
      cp "$backup/new-running.json" "$backup/new-startup.json"
    fi
    mkdir "$backup/candidate-repository" "$backup/candidate-runtime"
    if [[ "$scope" == system ]]; then
      chgrp folio-operators "$backup/candidate-repository" "$backup/candidate-runtime"
      chmod 2770 "$backup/candidate-repository" "$backup/candidate-runtime"
    fi
    install_args=()
    for model in "$new_bootstrap/models/$scope/"*.yang; do
      permissions=0600
      [[ "$scope" != system ]] || permissions=0660
      install_args+=(--install "$model" --permissions "$permissions")
      [[ "$scope" != system ]] || install_args+=(--group folio-operators)
    done
    candidate_command sysrepoctl "${install_args[@]}" --search-dirs "$new_bootstrap/models/$scope" \
      --init-data "$backup/new-startup.json" >&2
    candidate_command sysrepocfg --import="$backup/new-running.json" --datastore running --module folio-environment --format json
    model_identity "$new_bootstrap/models/$scope" >"$backup/new-model-identity"
    sync -f "$backup"
    nix-store --realise "$new_bootstrap" --add-root "$backup/new-bootstrap-root" --indirect >/dev/null
    jq --arg bootstrap "$new_bootstrap" '.newBootstrap=$bootstrap | .phase="prepared"' "$record" | folio-atomic-write "$record" ;;
  bind)
    [[ $# == 1 && $(jq -er .phase "$record") == prepared ]] || emit invalid 'Bind requires a prepared snapshot and closure' 2
    new_bootstrap=$(jq -er .newBootstrap "$record")
    cmp -s "$backup/new-startup.json" "$backup/new-running.json" ||
      emit conflict 'Candidate startup and running data must agree before binding a closure' 4
    artifact_identity "$1" "$new_bootstrap" "$backup/new-running.json" ||
      emit invalid 'Closure scope, account, bootstrap or configuration identity does not match the candidate' 2
    nix-store --realise "$1" --add-root "$backup/new-artifact-root" --indirect >/dev/null
    jq --arg artifact "$1" '.newArtifact=$artifact' "$record" | folio-atomic-write "$record" ;;
  install)
    [[ $# == 0 && $(jq -er .phase "$record") == prepared ]] || emit conflict 'Candidate is not prepared' 4
    jq -e '.newArtifact | type=="string"' "$record" >/dev/null
    quiescent
    old_bootstrap=$(jq -er .oldBootstrap "$record")
    cmp "$state/model-identity" "$backup/model-identity" || emit conflict 'Installed models changed after the snapshot' 4
    for datastore in startup running; do
      sysrepocfg --export --datastore "$datastore" --module folio-environment --format json --defaults report-all >"$work/current.json"
      folio-normalize "$old_bootstrap/models/$scope" "$work/current.json" >"$work/current-normalized.json"
      cmp -s "$work/current-normalized.json" "$backup/$datastore.json" || emit conflict 'Configuration changed after the snapshot' 4
    done
    write_guard installing
    mv "$state/sysrepo" "$backup/live-repository"
    mv "$backup/candidate-repository" "$state/sysrepo"
    folio-atomic-write "$state/model-identity" <"$backup/new-model-identity"
    reset_runtime
    rm -f "$state/configuration/transaction.json"
    sync "$state" "$backup" "$state/configuration"
    phase installed; write_guard installed ;;
  restore)
    [[ $# == 0 && -f "$record" && -d "$backup/repository" ]] || emit invalid 'No complete repository snapshot is available' 2
    quiescent
    write_guard restoring
    replacement=$(mktemp -d "$state/.restore.XXXXXX")
    cp -a "$backup/repository/." "$replacement/"
    sync -f "$replacement"
    displaced=$(mktemp -d "$backup/displaced.XXXXXX"); rmdir "$displaced"
    [[ ! -d "$state/sysrepo" ]] || mv "$state/sysrepo" "$displaced"
    mv "$replacement" "$state/sysrepo"
    folio-atomic-write "$state/model-identity" <"$backup/model-identity"
    reset_runtime
    sysrepocfg --import="$backup/startup.json" --datastore startup --module folio-environment --format json
    sysrepocfg --import="$backup/running.json" --datastore running --module folio-environment --format json
    rm -f "$state/configuration/transaction.json"
    [[ ! -f "$backup/configuration-journal.json" ]] ||
      folio-atomic-write "$state/configuration/transaction.json" <"$backup/configuration-journal.json"
    sync "$state" "$backup" "$state/configuration"
    phase restored-pending-activation; write_guard restored-pending-activation ;;
  finalize)
    [[ $# == 0 && -f "$record" ]] || emit invalid 'No schema transaction is available' 2
    case "$(jq -er .phase "$record")" in
      installed) phase complete ;;
      restored-pending-activation) phase restored ;;
      *) emit conflict 'Activate and verify the paired closure before finalizing' 4 ;;
    esac
    rm -f "$guard"; sync "$state" ;;
  inspect) [[ $# == 0 && -f "$record" ]] || emit invalid 'Unknown repository snapshot' 2 ;;
  *) emit invalid 'Unknown repository maintenance operation' 2 ;;
esac
emit success
