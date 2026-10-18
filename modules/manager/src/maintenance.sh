# Offline manager entry point. It is intentionally independent of subscriber
# RPC availability, so a damaged repository never has to be opened to recover.
umask 0077
(( $# == 4 || $# == 5 )) || { echo 'Usage: folio-manager-maintain user|system BOOTSTRAP snapshot|upgrade|restore ID [FROZEN_SOURCE]' >&2; exit 2; }
scope=$1 bootstrap=$2 action=$3 id=$4 source_path=${5:-}
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
case "$action" in snapshot|restore) [[ $# == 4 ]] || exit 2 ;; upgrade) [[ $# == 5 ]] || exit 2 ;; *) exit 2 ;; esac
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
snapshot_artifact_matches() {
  local closure=$1 expected_bootstrap=$2 metadata=$1/folio-home.json
  immutable "$closure" || return 1
  [[ "$scope" != system ]] || metadata=$closure/folio-system.json
  jq -e --arg digest "$(digest "$backup/running.json")" \
    --arg bootstrap "$expected_bootstrap" --arg scope "$scope" --arg account "$(id -un)" --arg home "$HOME" \
    '.format==1 and .configurationDigest==$digest and .bootstrap==$bootstrap and
      (if $scope=="system" then .scope=="system" else .scope=="user" and .account==$account and .home==$home end)' \
    "$metadata" >/dev/null
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
  while IFS= read -r service; do
    systemctl "$manager_option" start "$service" >&2 || return 1
  done < <(jq -r '.active[]' "$journal")
  if jq -e '.active | index("folio-manager.service") != null' "$journal" >/dev/null; then
    printf '{"folio-deployment:status":{}}\n' >"$work/readiness.json"
    deadline=$((SECONDS + 30))
    while (( SECONDS < deadline )); do
      if timeout --kill-after=1 2 folio-repository "$scope" cfg --rpc="$work/readiness.json" \
          --format json --timeout 1 >"$work/readiness-result.json" 2>"$work/readiness-error"; then return 0; fi
      sleep 0.2
    done
    cat "$work/readiness-error" >&2
    return 1
  fi
}
finish() {
  local code=$?
  trap - EXIT
  if "$stopped" && ! "$complete"; then
    # Never start consumers against ambiguous repository/closure effects.
    # Before installation, the unchanged pair is safe to resume.
    if ! "$installed" && [[ ! -e "$state/schema-transaction.json" ]]; then
      flock -u 9
      if restart_consumers; then phase aborted || code=1; else code=1; fi
    elif [[ "$action" == upgrade ]]; then
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
    echo 'Offline maintenance failed; retain the journal and use explicit restore before resuming consumers' >&2
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
if [[ "$action" != restore && -e "$state/schema-transaction.json" ]]; then
  echo 'An incomplete schema transaction requires explicit restore' >&2; exit 4
fi
if [[ "$action" == upgrade ]]; then
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
fi
# Stop and mask registered services before acquiring any repository lock. Never
# hold initialize/repository locks while asking systemd to stop a consumer.
services "$bootstrap" >"$work/services"
if [[ "$action" == upgrade ]]; then services "$new_bootstrap" >>"$work/services"; fi
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
  # An offline snapshot must bind the closure to exactly the saved desired data.
  # Older unidentifiable closures require a supported rebuild, never adoption.
  snapshot_artifact_matches "$old_artifact" "$bootstrap"
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
case "$action" in
  snapshot) phase complete ;;
  upgrade)
    maintain prepare "$id" "$new_bootstrap"
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
    jq -cnS --arg scope "$scope" --arg artifact "$artifact" --arg source "$source_path" \
      --arg bootstrap "$new_bootstrap" --arg id "$id" --arg inputDigest "$(digest "$work/input.json")" \
      --slurpfile input "$work/input.json" --slurpfile transaction "$backup/transaction.json" \
      '{format:1,workerProtocol:1,scope:$scope,artifact:$artifact,source:$source,bootstrap:$bootstrap,
        revisionId:("maintenance-"+$id),maintenanceId:$id,inputDigest:$inputDigest,
        configurationDigest:$input[0].configurationDigest,configuration:$input[0].configuration,
        models:$input[0].models,tools:$input[0].tools,beforeProfile:$transaction[0].oldArtifact}' |
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
