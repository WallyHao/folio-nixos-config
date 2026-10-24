# Offline manager entry point. It is intentionally independent of subscriber
# RPC availability, so a damaged repository never has to be opened to recover.
umask 0077
(( $# >= 4 && $# <= 6 )) || { echo 'Usage: folio-manager-maintain SCOPE BOOTSTRAP snapshot|upgrade|adopt|restore|rollback ID [SOURCE_OR_REVISION] [--rebuild]' >&2; exit 2; }
scope=$1 bootstrap=$2 action=$3 id=$4 source_path=${5:-}
rebuild=false
[[ "$id" =~ ^[a-z][a-z0-9-]{0,63}$ ]] || exit 2
immutable() { [[ "$1" =~ ^/nix/store/[a-z0-9]{32}-[^/]+$ && -d "$1" ]]; }
immutable "$bootstrap" || exit 2
case "$scope" in
  user)
    state=${XDG_STATE_HOME:-$HOME/.local/state}/folio
    runtime=${XDG_RUNTIME_DIR:?}/folio
    profile=${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager
    manager_option=--user ;;
  system)
    [[ $(id -u) == 0 ]] || exit 3
    state=/var/lib/folio runtime=/run/folio profile=/nix/var/nix/profiles/system
    manager_option=--system ;;
  *) exit 2 ;;
esac
unit_runtime=${XDG_RUNTIME_DIR:-/run}/systemd/user
[[ "$scope" != system ]] || unit_runtime=/run/systemd/system
case "$action" in
  snapshot|restore) [[ $# == 4 ]] || exit 2 ;;
  upgrade|adopt) [[ $# == 5 ]] || exit 2 ;;
  rollback)
    [[ $# == 5 || ( $# == 6 && $6 == --rebuild ) ]] || exit 2
    [[ $# != 6 ]] || rebuild=true ;;
  *) exit 2 ;;
esac
[[ "$state" == /* && "$runtime" == /* && -d "$state" ]] || exit 3
[[ "$runtime" != *$'\n'* && "$runtime" != *%* ]] || exit 2
work=$(mktemp -d "$runtime/coordinator.XXXXXX")
backup=$state/backups/repositories/$id
journal=$backup/coordinator.json
entry_journal=$state/offline-coordinator-$id.json
blocker=$runtime/offline-consumers-$id
stopped=false installed=false complete=false
exec 9>"$state/mutation.lock"
flock -x -w 30 9
maintain() { folio-repository-maintain "$scope" "$@" >"$work/primitive.json"; }
digest() { local value; value=$(sha256sum <"$1"); printf '%s\n' "${value%% *}"; }
legacy_artifact_matches() {
  local closure=$1
  [[ "$scope" == user && -x "$closure/activate" && ! -e "$closure/folio-home.json" ]] || return 1
  jq -e --arg account "$(id -un)" --arg home "$HOME" \
    '.protocolVersion==1 and .schemaVersion==1 and .user==$account and .home==$home' \
    "$closure/sylphy-home.json" >/dev/null
}
snapshot_artifact_matches() {
  local closure=$1 expected_bootstrap=$2 metadata=$1/folio-home.json expected_digest
  immutable "$closure" || return 1
  if jq -e '.legacyAdoption==true' "$backup/transaction.json" >/dev/null; then
    legacy_artifact_matches "$closure"
    return
  fi
  [[ "$scope" != system ]] || metadata=$closure/folio-system.json
  expected_digest=$(jq -r '.beforeAppliedDigest // ""' "$backup/transaction.json")
  [[ -n "$expected_digest" ]] || expected_digest=$(digest "$backup/running.json")
  jq -e --arg digest "$expected_digest" \
    --arg bootstrap "$expected_bootstrap" --arg scope "$scope" --arg account "$(id -un)" --arg home "$HOME" \
    '.format==1 and .configurationDigest==$digest and .bootstrap==$bootstrap and
      (if $scope=="system" then .scope=="system" else .scope=="user" and .account==$account and .home==$home end)' \
    "$metadata" >/dev/null
}
bind_before_applied_digest() {
  local closure=$1 expected_bootstrap=$2 before_digest retained_source
  # A saved desired edit need not have been applied to the selected closure.
  # Bind the old closure to its retained deployment, while preserving both
  # desired datastores in the snapshot for migration and recovery.
  if snapshot_artifact_matches "$closure" "$expected_bootstrap"; then return 0; fi
  before_digest=$(jq -er --arg artifact "$closure" \
    'select(.format==1 and .artifact==$artifact) | .configurationDigest' "$backup/deployment.json") || {
      echo 'Pending desired changes require a retained deployment matching the selected closure' >&2; return 1;
    }
  [[ "$before_digest" =~ ^[a-f0-9]{64}$ ]] || return 1
  retained_source=$(jq -er .source "$backup/deployment.json") || return 1
  immutable "$retained_source" && [[ -f "$retained_source/folio-input.json" ]] || return 1
  jq -e --arg digest "$before_digest" --arg scope "$scope" \
    --slurpfile identities "$expected_bootstrap/identities.json" \
    '.format==1 and .scope==$scope and .configurationDigest==$digest and
      .models==$identities[0].models[$scope] and .tools==$identities[0].tools' \
    "$retained_source/folio-input.json" >/dev/null || return 1
  jq -cS .configuration "$retained_source/folio-input.json" >"$work/before-applied.json"
  [[ $(digest "$work/before-applied.json") == "$before_digest" ]] || return 1
  jq --arg digest "$before_digest" '.beforeAppliedDigest=$digest' "$backup/transaction.json" |
    folio-atomic-write "$backup/transaction.json"
  snapshot_artifact_matches "$closure" "$expected_bootstrap"
}
artifact_effects_match() {
  local closure=$1 file relative
  [[ $(readlink -e "$profile") == "$closure" ]] || return 1
  if [[ "$scope" == system ]]; then
    [[ $(readlink -e /run/current-system) == "$closure" ]] || return 1
    [[ $(readlink -e /etc/localtime) == "$(readlink -e "$closure/etc/localtime")" ]] || return 1
  else
    [[ -d "$closure/home-files" ]] || return 1
    while IFS= read -r -d '' file; do
      relative=${file#"$closure/home-files/"}
      [[ $(readlink -e "$HOME/$relative") == "$(readlink -e "$file")" ]] || return 1
    done < <(find -L "$closure/home-files" -type f -print0)
  fi
}
phase() {
  jq --arg phase "$1" '.phase=$phase' "$journal" | folio-atomic-write "$journal"
  if [[ "$journal" != "$entry_journal" ]]; then folio-atomic-write "$entry_journal" <"$journal"; fi
}
services() {
  jq -er --arg scope "$scope" '.[$scope][] | select(test("^folio-[a-z0-9-]+\\.service$"))' "$1/subscribers.json"
}
stop_consumer() {
  local load_state
  load_state=$(systemctl "$manager_option" show --property=LoadState --value "$1" 2>/dev/null || true)
  # Models/registries are available even when an optional capability has never
  # installed its service. Keep its activation condition, but there is no unit
  # to stop in the currently selected generation.
  [[ "$load_state" != not-found ]] || return 0
  systemctl "$manager_option" stop "$1" >&2
}
restart_consumers() {
  local service dropin deadline
  # Only unmask masks owned by this invocation. An interruption retains the
  # exact list in the coordinator journal for the explicit restore command.
  while IFS= read -r service; do
    systemctl "$manager_option" unmask --runtime "$service" >&2 || return 1
    dropin=$unit_runtime/$service.d/99-folio-maintenance-$id.conf
    if [[ -e "$dropin" ]]; then
      printf '[Unit]\nConditionPathExists=!%s\n' "$blocker" >"$work/expected-condition"
      cmp -s "$dropin" "$work/expected-condition" || return 1
      rm "$dropin" || return 1
    fi
  done < <(jq -r '.masked[]' "$journal")
  rm -f "$blocker" || return 1
  systemctl "$manager_option" daemon-reload >&2 || return 1
  jq -r '.active[]' "$journal" >"$work/restart-services"
  if [[ "$action" == adopt && $(readlink -e "$profile") == "${artifact:-}" ]]; then
    # A legacy profile may have no active Folio subscriber. Start newly enabled
    # user units after removing the maintenance condition, not during activation.
    while IFS= read -r service; do
      if systemctl "$manager_option" is-enabled --quiet "$service"; then
        printf '%s\n' "$service" >>"$work/restart-services"
      fi
    done < <(services "$new_bootstrap")
  fi
  sort -u "$work/restart-services" -o "$work/restart-services"
  while IFS= read -r service; do
    systemctl "$manager_option" start "$service" >&2 || return 1
  done <"$work/restart-services"
  if rg -qx 'folio-manager.service' "$work/restart-services"; then
    printf '{"folio-deployment:status":{}}\n' >"$work/readiness.json"
    deadline=$((SECONDS + 30))
    while (( SECONDS < deadline )); do
      # Status verifies every managed file; a normal desktop/tool profile can
      # exceed one second. Let each bounded probe finish instead of queuing retries.
      if timeout --kill-after=1 6 folio-repository "$scope" cfg --rpc="$work/readiness.json" \
          --format json --timeout 5 >"$work/readiness-result.json" 2>"$work/readiness-error"; then return 0; fi
      sleep 0.2
    done
    cat "$work/readiness-error" >&2
    return 1
  fi
}
finish() {
  local code=$? unchanged_resumed=false
  trap - EXIT
  if "$stopped" && ! "$complete"; then
    # Never start consumers against ambiguous repository/closure effects.
    # Before installation, the unchanged pair is safe to resume.
    if ! "$installed" && [[ ! -e "$state/schema-transaction.json" ]]; then
      flock -u 9
      if restart_consumers; then phase aborted || code=1; unchanged_resumed=true; else code=1; fi
    elif [[ "$action" == upgrade || "$action" == adopt || "$action" == rollback ]]; then
      while IFS= read -r service; do stop_consumer "$service" || code=1; done < <(jq -r '.masked[]' "$journal")
      if maintain restore "$id" &&
          snapshot_artifact_matches "$(jq -er .oldArtifact "$backup/transaction.json")" "$(jq -er .oldBootstrap "$backup/transaction.json")" &&
          activate "$(jq -er .oldArtifact "$backup/transaction.json")" && maintain finalize "$id"; then
        if [[ -f "$backup/deployment.json" ]]; then
          folio-atomic-write "$state/deployments/current.json" <"$backup/deployment.json" || code=1
        else rm -f "$state/deployments/current.json"; sync "$state/deployments"; fi
        phase restored || code=1
        flock -u 9
        restart_consumers || code=1
      fi
    fi
  fi
  rm -rf "$work"
  if (( code != 0 )); then
    if "$unchanged_resumed"; then
      echo 'Offline maintenance aborted before installation; the original repository and consumers were resumed. Retain the journal.' >&2
    else
      echo 'Offline maintenance failed; retain the journal and use explicit restore before resuming consumers' >&2
    fi
  fi
  exit "$code"
}
trap finish EXIT
trap 'exit 143' TERM INT HUP
shopt -s nullglob
for pending in "$state"/offline-coordinator-*.json; do
  if [[ "$action" == restore && "$pending" == "$entry_journal" ]]; then continue; fi
  jq -e '.phase=="complete" or .phase=="restored" or .phase=="aborted"' "$pending" >/dev/null || {
    echo 'An interrupted offline coordinator requires explicit recovery first' >&2; exit 4;
  }
done
for task in "$state/deployments/tasks/"*.json; do
  jq -e '. as $task | (.recoveryRequired != true) and
    (["queued","validating","building","activating","verifying"] | index($task.phase) | not)' \
    "$task" >/dev/null || { echo 'Resolve active tasks and pending deployment recovery first' >&2; exit 4; }
done
for job in "$state/vm/jobs/"*/job.json; do
  jq -e '.phase != "queued" and .phase != "building" and .phase != "starting" and .phase != "running"' \
    "$job" >/dev/null || { echo 'Stop active VM jobs before offline maintenance' >&2; exit 4; }
done
for task in "$state/applications/tasks/"*.json; do
  jq -e '(.recoveryRequired != true) and (.phase=="succeeded" or .phase=="failed" or .phase=="interrupted")' "$task" >/dev/null || {
    echo 'Finish or explicitly recover application tasks before offline maintenance' >&2; exit 4;
  }
done
if [[ "$action" != restore && -e "$state/schema-transaction.json" ]]; then
  echo 'An incomplete schema transaction requires explicit restore' >&2; exit 4
fi
if [[ "$action" == rollback ]]; then
  revision_id=$source_path
  [[ "$revision_id" =~ ^([a-f0-9]{64}|maintenance-[a-z][a-z0-9-]{0,63})$ ]] || exit 2
  target_revision=$state/deployments/revisions/$revision_id.json
  [[ -f "$target_revision" && ! -L "$target_revision" ]] || { echo 'Unknown retained revision' >&2; exit 2; }
  jq -e --arg scope "$scope" '.format==1 and .scope==$scope' "$target_revision" >/dev/null || exit 3
  source_path=$(jq -er .source "$target_revision")
  immutable "$source_path" || { echo 'Retained source is unavailable' >&2; exit 3; }
  jq -e --slurpfile input "$source_path/folio-input.json" \
    '.configuration==$input[0].configuration and .configurationDigest==$input[0].configurationDigest and
      .models==$input[0].models and .tools==$input[0].tools' "$target_revision" >/dev/null || {
    echo 'Retained revision differs from its immutable input' >&2; exit 4;
  }
  source_digest=$(nix hash path --type sha256 "$source_path")
  source_digest=$(nix hash convert --hash-algo sha256 --to base16 "$source_digest")
  [[ "$source_digest" == "$(jq -er .inputDigest "$target_revision")" ]] || { echo 'Retained source digest mismatch' >&2; exit 4; }
  if [[ $(jq -r '.workerProtocol // 0' "$target_revision") != 1 ]] && ! "$rebuild"; then
    echo 'Unsupported retained worker protocol; use --rebuild to rebuild with the current protocol' >&2; exit 3
  fi
  if "$rebuild"; then
    mkdir "$work/rebuilt-source"
    cp -R "$source_path/." "$work/rebuilt-source/"
    chmod -R u+w "$work/rebuilt-source"
    # Keep old desired data, models, adapters and lock. Replace the manager
    # implementation and its repository protocol through explicit public source.
    mkdir "$work/frozen-composition"
    # Composition and defaults must continue to describe the retained module
    # inventory, including sources from before optional modules were introduced.
    for component in outputs.nix catalogue.nix defaults.nix targets.nix prepared.nix configuration.nix bootstrap.nix home.nix development.nix; do
      if [[ -f "$work/rebuilt-source/modules/manager/src/$component" ]]; then
        cp "$work/rebuilt-source/modules/manager/src/$component" "$work/frozen-composition/$component"
      fi
    done
    for component in src cli runtime; do
      rm -rf "$work/rebuilt-source/modules/manager/$component"
      cp -R "@compatibilitySource@/modules/manager/$component" "$work/rebuilt-source/modules/manager/$component"
    done
    chmod -R u+w "$work/rebuilt-source/modules/manager"
    cp "$work/frozen-composition/"* "$work/rebuilt-source/modules/manager/src/"
    cp @compatibilitySource@/modules/manager/default.nix "$work/rebuilt-source/modules/manager/default.nix"
    cp -R @compatibilitySource@/modules/sysrepo "$work/rebuilt-source/modules/sysrepo"
    chmod -R u+w "$work/rebuilt-source"
    source_path=$(nix store add-path --name folio-rebuilt-revision "$work/rebuilt-source")
  fi
fi
if [[ "$action" == adopt ]]; then
  [[ "$scope" == user && ! -e "$state/deployments/current.json" ]] || {
    echo 'Adoption requires an unmanaged legacy user profile' >&2; exit 4;
  }
  legacy_artifact_matches "$(readlink -e "$profile")" || {
    echo 'Legacy profile account/home metadata is incompatible' >&2; exit 4;
  }
fi
if [[ "$action" == upgrade || "$action" == adopt || "$action" == rollback ]]; then
  immutable "$source_path" && [[ -f "$source_path/folio-input.json" ]] || exit 2
  nix-store --realise "$source_path" --add-root "$work/source-root" --indirect >/dev/null
  target=homeConfigurations.folio.activationPackage
  [[ "$scope" != system ]] || target=nixosConfigurations.portable.config.system.build.toplevel
  # Evaluation/build never uses root privileges, including candidate bootstrap.
  nix_build() {
    if [[ "$scope" == system ]]; then
      runuser -u folio-builder -- env -i HOME=/var/lib/folio-builder USER=folio-builder LANG=C.UTF-8 \
        NIX_REMOTE=daemon PATH="$PATH" nix build --no-update-lock-file --no-link --json "$1"
    else nix build --no-update-lock-file --no-link --json "$1"; fi
  }
  export -f nix_build
  export scope
  # shellcheck disable=SC2016
  timeout --kill-after=10 900 bash -c 'nix_build "$1"' _ "path:$source_path#manager-bootstrap" >"$work/bootstrap-build.json"
  new_bootstrap=$(jq -er '.[0].outputs.out' "$work/bootstrap-build.json")
  immutable "$new_bootstrap"
  jq -cS .configuration "$source_path/folio-input.json" >"$work/desired.json"
  jq -cS .systemDescriptor "$source_path/folio-input.json" >"$work/descriptor.json"
  folio-prepare-input "$work/desired.json" "$new_bootstrap" "$work/descriptor.json" >"$work/input.json"
  jq -cS . "$source_path/folio-input.json" >"$work/source-input.json"
  cmp "$work/input.json" "$work/source-input.json"
  [[ $(jq -er .scope "$work/input.json") == "$scope" ]]
  # shellcheck disable=SC2016
  timeout --kill-after=10 900 bash -c 'nix_build "$1"' _ "path:$source_path#$target" >"$work/build.json"
  artifact=$(jq -er '.[0].outputs.out' "$work/build.json")
  if [[ "$action" == rollback ]]; then
    jq -e --arg scope "$scope" --slurpfile identities "$new_bootstrap/identities.json" \
      '.models==$identities[0].models[$scope] and .tools==$identities[0].tools' "$target_revision" >/dev/null || {
      echo 'Rebuilt source changed retained model or tool identities; rollback is unavailable' >&2; exit 3;
    }
    metadata=$artifact/folio-home.json
    [[ "$scope" != system ]] || metadata=$artifact/folio-system.json
    jq -e '.workerProtocol==1' "$metadata" >/dev/null || { echo 'Rebuild did not provide a supported worker protocol' >&2; exit 3; }
    if ! "$rebuild"; then
      [[ "$new_bootstrap" == "$(jq -er .bootstrap "$target_revision")" && "$artifact" == "$(jq -er .artifact "$target_revision")" ]] || {
        echo 'Retained closure identity changed; request an explicit compatible rebuild' >&2; exit 4;
      }
    fi
  fi
fi
# Stop and mask registered services before acquiring any repository lock. Never
# hold initialize/repository locks while asking systemd to stop a consumer.
services "$bootstrap" >"$work/services"
if [[ "$action" == upgrade || "$action" == adopt || "$action" == rollback ]]; then services "$new_bootstrap" >>"$work/services"; fi
if [[ "$action" == restore ]]; then
  [[ -f "$journal" && -f "$backup/transaction.json" ]] || exit 2
  jq -r '.masked[],.active[]' "$journal" >>"$work/services"
fi
sort -u "$work/services" -o "$work/services"
jq -Rn '[inputs]' <"$work/services" >"$work/all.json"
: >"$work/active"
while IFS= read -r service; do
  enabled=$(systemctl "$manager_option" is-enabled "$service" 2>/dev/null || true)
  if [[ "$enabled" == masked* ]] || [[ -L "$unit_runtime/$service" && $(readlink "$unit_runtime/$service") == /dev/null ]]; then
    if [[ "$action" != restore ]] || ! jq -e --arg service "$service" '.masked | index($service) != null' "$journal" >/dev/null; then
      echo 'A registered consumer is already masked; preserve its policy and resolve it first' >&2; exit 4
    fi
  fi
  if systemctl "$manager_option" is-active --quiet "$service"; then printf '%s\n' "$service" >>"$work/active"; fi
done <"$work/services"
jq -Rn '[inputs]' <"$work/active" >"$work/active.json"
# Restore reuses the prior mask list after interruption, rather than treating its
# own retained masks as a new external policy. See the restore branch below.
if [[ "$action" != restore ]]; then
  old_artifact=$(readlink -e "$profile")
  immutable "$old_artifact"
  journal=$entry_journal
  [[ ! -e "$journal" && ! -e "$backup" ]] || { echo 'Transaction ID already exists' >&2; exit 4; }
  jq -cnS --arg id "$id" --arg scope "$scope" --slurpfile active "$work/active.json" \
    '{format:1,id:$id,scope:$scope,phase:"quiesced",active:$active[0],masked:[]}' | folio-atomic-write "$journal"
  stopped=true
  while IFS= read -r service; do stop_consumer "$service"; done <"$work/services"
  # VM operations have a separate job lock; recheck after their RPC subscriber
  # is stopped to close the window while candidate builds were running.
  for job in "$state/vm/jobs/"*/job.json; do
    jq -e '.phase != "queued" and .phase != "building" and .phase != "starting" and .phase != "running"' \
      "$job" >/dev/null || { echo 'Stop active VM jobs before offline maintenance' >&2; exit 4; }
  done
  # snapshot creates the backup directory and roots the original pair.
  maintain snapshot "$id" "$bootstrap" "$old_artifact"
  if [[ "$action" == adopt ]]; then
    legacy_artifact_matches "$old_artifact"
    jq '.legacyAdoption=true' "$backup/transaction.json" | folio-atomic-write "$backup/transaction.json"
  fi
  if [[ "$action" == rollback ]]; then
    # A failed later desired revision may differ from the actual successful
    # closure. Retain that desired data as evidence without calling it applied.
    before_digest=$(jq -er --arg artifact "$old_artifact" 'select(.artifact==$artifact) | .configurationDigest' "$backup/deployment.json")
    [[ "$before_digest" =~ ^[a-f0-9]{64}$ ]] || exit 4
    jq --arg digest "$before_digest" '.beforeAppliedDigest=$digest' "$backup/transaction.json" |
      folio-atomic-write "$backup/transaction.json"
  fi
  if [[ "$action" == upgrade ]]; then
    bind_before_applied_digest "$old_artifact" "$bootstrap"
  fi
  # An offline snapshot must bind the closure to exactly the saved desired data.
  # Legacy adoption records the old repository and independently identified
  # Sylphy closure without inventing Folio configuration metadata for it.
  snapshot_artifact_matches "$old_artifact" "$bootstrap"
  artifact_effects_match "$old_artifact" || { echo 'Selected closure has unverified effects; recover those effects before maintenance' >&2; exit 4; }
  cmp "$backup/startup.json" "$backup/running.json"
  folio-atomic-write "$backup/coordinator.json" <"$journal"
  journal=$backup/coordinator.json
else
  stopped=true
  while IFS= read -r service; do stop_consumer "$service"; done <"$work/services"
fi
stopped=true
touch "$blocker"
while IFS= read -r service; do
  # Journal the intention first: unmask is idempotent after a failed mask call.
  jq --arg service "$service" '.masked |= (. + [$service] | unique)' "$journal" | folio-atomic-write "$journal"
  mkdir -p "$unit_runtime/$service.d"
  printf '[Unit]\nConditionPathExists=!%s\n' "$blocker" |
    folio-atomic-write "$unit_runtime/$service.d/99-folio-maintenance-$id.conf"
  chmod 0644 "$unit_runtime/$service.d/99-folio-maintenance-$id.conf"
  systemctl "$manager_option" mask --runtime "$service" >&2
done <"$work/services"
activate() {
  local closure=$1
  [[ ! ${DRY_RUN:-} && ! ${SKIP_SANITY_CHECKS:-} ]] || return 1
  nix-env --profile "$profile" --set "$closure" >&2 || return 1
  if [[ "$scope" == user ]]; then
    unset HOME_MANAGER_BACKUP_OVERWRITE DRY_RUN SKIP_SANITY_CHECKS
    HOME_MANAGER_BACKUP_EXT=folio-maintenance-$id timeout --kill-after=10 300 "$closure/activate" --driver-version 1 >&2 || return 1
  else timeout --kill-after=10 300 "$closure/bin/switch-to-configuration" switch >&2 || return 1; fi
  artifact_effects_match "$closure"
}
case "$action" in
  snapshot) phase complete ;;
  upgrade|adopt|rollback)
    if [[ "$action" != rollback ]]; then maintain prepare "$id" "$new_bootstrap"
    else maintain prepare-revision "$id" "$new_bootstrap" "$target_revision"; fi
    cmp "$backup/new-running.json" "$work/desired.json"
    maintain bind "$id" "$artifact"
    phase installing
    maintain install "$id"
    installed=true
    phase activating
    activate "$artifact"
    phase verified
    nix-store --realise "$source_path" --add-root "$backup/source-root" --indirect >/dev/null
    mkdir -p "$state/deployments/revisions"
    sync "$state/deployments" "$state/deployments/revisions"
    input_hash=$(nix hash path --type sha256 "$source_path")
    input_digest=$(nix hash convert --hash-algo sha256 --to base16 "$input_hash")
    before_deployment=null
    [[ ! -f "$backup/deployment.json" ]] || before_deployment=$(jq -c . "$backup/deployment.json")
    jq -cnS --arg scope "$scope" --arg artifact "$artifact" --arg source "$source_path" \
      --arg bootstrap "$new_bootstrap" --arg id "$id" --arg inputDigest "$input_digest" --argjson beforeDeployment "$before_deployment" \
      --slurpfile input "$work/input.json" --slurpfile transaction "$backup/transaction.json" \
      '{format:1,workerProtocol:1,scope:$scope,artifact:$artifact,source:$source,bootstrap:$bootstrap,
        revisionId:("maintenance-"+$id),maintenanceId:$id,inputDigest:$inputDigest,
        configurationDigest:$input[0].configurationDigest,configuration:$input[0].configuration,
        models:$input[0].models,tools:$input[0].tools,beforeProfile:$transaction[0].oldArtifact,beforeDeployment:$beforeDeployment}' |
      folio-atomic-write "$state/deployments/revisions/maintenance-$id.json"
    jq '{format,artifact,source,inputDigest,configurationDigest,revisionId,maintenanceId}' \
      "$state/deployments/revisions/maintenance-$id.json" | folio-atomic-write "$state/deployments/current.json"
    maintain finalize "$id"
    ;;
  restore)
    installed=true
    phase restoring
    maintain restore "$id"
    old_artifact=$(jq -er .oldArtifact "$backup/transaction.json")
    snapshot_artifact_matches "$old_artifact" "$(jq -er .oldBootstrap "$backup/transaction.json")"
    activate "$old_artifact"
    phase verified
    if [[ -f "$backup/deployment.json" ]]; then
      folio-atomic-write "$state/deployments/current.json" <"$backup/deployment.json"
    else rm -f "$state/deployments/current.json"; sync "$state/deployments"; fi
    maintain finalize "$id" ;;
esac
flock -u 9
restart_consumers
phase complete
complete=true
jq -cn --arg id "$id" '{status:"success",data:{transactionId:$id},error:null}'
