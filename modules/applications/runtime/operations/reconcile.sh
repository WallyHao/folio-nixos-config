task_id=${1:-}
[[ "$task_id" =~ ^a-[a-f0-9]{32}$ ]] || exit 2
record=$app_state/tasks/$task_id.json
[[ -f "$record" && ! -L "$record" ]] || exit 2
exec 8>"$app_state/tasks/$task_id.lock"
flock -n 8 || exit 0
[[ $(jq -er .phase "$record") != succeeded ]] || exit 0
finished=false
failure_status=failure
failure_message='Application worker failed; inspect the retained task and journal'
finish_worker() {
  local code=$?
  trap - EXIT INT TERM
  if [[ "$finished" != true ]]; then
    jq --arg status "$failure_status" --arg message "$failure_message" --arg now "$(date -u +%FT%TZ)" \
      '.phase="failed" | .resultStatus=$status | .error=$message | .updatedAt=$now |
       .recoveryRequired=(.installationStarted==true or .filesStarted==true)' "$record" |
      folio-atomic-write "$record" || true
  fi
  rm -rf "$work"
  exit "$code"
}
trap finish_worker EXIT
trap 'failure_status=unavailable; failure_message="Application worker interrupted; explicitly resume the retained task"; exit 3' INT TERM
fail() { failure_status=$1; failure_message=$2; exit "${3:-1}"; }
checkpoint() {
  jq --arg phase "$1" --arg now "$(date -u +%FT%TZ)" '.phase=$phase | .updatedAt=$now' "$record" |
    folio-atomic-write "$record"
}
# The same lock order is used by configuration commits and application dispatch.
lock_mutation
configuration >"$work/configuration.json"
configuration_digest=$(hash_file "$work/configuration.json")
[[ "$configuration_digest" == "$(jq -er .configurationDigest "$record")" ]] ||
  fail conflict 'Desired configuration changed; no new application effects are permitted' 4
action=$(jq -er .request.action "$record")
application=$(jq -er '.request.application // "all"' "$record")
offline=$(jq -r '.offline // false' "$record")
generation=$(manifest || true)
checkpoint preflight
inventory >"$work/before.json"
if ! jq -e 'has("before")' "$record" >/dev/null; then
  jq --slurpfile before "$work/before.json" '.before=$before[0]' "$record" | folio-atomic-write "$record"
fi
if [[ "$action" == rollback ]]; then
  revision=$(jq -er .request.revision "$record")
  [[ "$revision" =~ ^a-[a-f0-9]{32}$ && -f "$app_state/revisions/$revision.json" ]] || fail unavailable 'Application rollback revision is unavailable' 3
  cached_refs >"$work/rollback-cache.json"
  # All requested applications must pass before the first application changes.
  while IFS= read -r rollback_name; do
    [[ "$application" == all || "$application" == "$rollback_name" ]] || continue
    rollback_plan=$(jq -ce --arg name "$rollback_name" '.applications[$name].plan' "$app_state/revisions/$revision.json") || fail unavailable 'Rollback has no retained application plan' 3
    jq -e --slurpfile cache "$work/rollback-cache.json" --slurpfile actual "$work/before.json" '
      .operations | length>0 and all(.[]; . as $op |
        any($cache[0][]; .ref==$op.ref and .commit==$op.commit) and
        (if (.ref|startswith("runtime/")) then
          all($actual[0][]; .ref!=$op.ref or .commit==$op.commit) else true end))' <<<"$rollback_plan" >/dev/null ||
      fail unavailable 'Application rollback content is unavailable or would change a shared runtime' 3
  done < <(jq -r '."folio-environment:environment".modules[] | select(.name=="applications") | ."folio-applications:applications" as $settings | $settings.app[]? | select(.selected and (($settings.native[.name] // false)==false)) | .name' "$work/configuration.json")
fi
if [[ "$action" == init ]]; then
  [[ "$offline" != true ]] || fail unavailable 'Remote initialization requires an explicit online request' 3
  # Existing remotes are never replaced. The transaction helper separately checks
  # Flathub origin and signature verification before any preparation/deployment.
  if ! flatpak remotes --user --columns=name | awk '$0=="flathub" {found=1} END {exit !found}'; then
    flatpak remote-add --user --noninteractive flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  fi
  folio-applications-transaction verify-remote || fail conflict 'Existing Flathub remote is disabled, unverified or has a different origin' 4
  flatpak update --user --appstream --noninteractive
elif [[ "$action" == refresh ]]; then
  flatpak update --user --appstream --noninteractive
else
  while IFS= read -r desired; do
    name=$(jq -er .name <<<"$desired")
    [[ "$application" == all || "$application" == "$name" ]] || continue
    ref=$(jq -er .ref <<<"$desired")
    id=$(app_id "$name")
    owned=$app_state/owned/$name.json
    inventory >"$work/actual.json"
    actual=$(jq -c --arg ref "$ref" '[.[] | select(.ref==$ref)][0] // null' "$work/actual.json")
    actual_commit=$(jq -r '.commit // ""' <<<"$actual")
    selected=$(jq -r .selected <<<"$desired")
    previous=null
    [[ ! -f "$owned" ]] || previous=$(jq -c . "$owned")
    if [[ "$actual" != null && "$previous" != null && "$actual_commit" != "$(jq -er .commit <<<"$previous")" ]]; then
      intent=$(jq -r --arg name "$name" '.appEffects[$name].commit // ""' "$record")
      [[ "$intent" == "$actual_commit" ]] || fail conflict 'Owned application was changed outside Folio; inspect it before continuing' 4
    fi
    if [[ "$actual" != null && "$previous" == null && "$action" != adopt ]]; then
      # A crash may occur between a verified deployment and its ownership write.
      intent=$(jq -r --arg name "$name" '.appEffects[$name].commit // ""' "$record")
      [[ -n "$intent" && "$intent" == "$actual_commit" ]] || fail conflict 'Existing application requires explicit adoption' 4
    fi
    if [[ "$action" == remove || "$selected" != true ]]; then
      [[ "$action" != remove || "$selected" != true ]] || fail conflict 'Persist unselected desired state before removal' 4
      if [[ "$actual" != null ]]; then
        [[ "$previous" != null ]] || fail conflict 'Refusing to remove an unmanaged application' 4
        [[ $(jq -er .commit <<<"$previous") == "$actual_commit" ]] || fail conflict 'Owned application was modified outside Folio' 4
        jq '.installationStarted=true' "$record" | folio-atomic-write "$record"
        checkpoint removing
        flatpak uninstall --user --noninteractive --assumeyes "$ref"
      fi
      rm -f "$owned"
      continue
    fi
    if [[ "$action" == adopt ]]; then
      [[ "$actual" != null && $(jq -r .remote <<<"$actual") == flathub ]] || fail conflict 'Adoption requires an installed official-Flathub application' 4
      commit=$actual_commit
      if [[ $(jq -r '."policy"' <<<"$desired") == pinned ]]; then
        [[ $(jq -er '."commit"' <<<"$desired") == "$commit" ]] || fail conflict 'Installed commit does not match the pinned desired commit' 4
      fi
      plan=$(jq -cn --arg ref "$ref" --arg commit "$commit" --slurpfile actual "$work/actual.json" \
        '{ref:$ref,commit:$commit,operations:[$actual[0][] | select(.ref==$ref or (.ref|startswith("runtime/"))) | . + {subpaths:[]}]}')
    else
      commit=$(jq -r '."commit" // ""' <<<"$desired")
      if [[ $(jq -r '."policy"' <<<"$desired") != pinned ]]; then
        if [[ "$action" != update && "$previous" != null ]]; then commit=$(jq -er .commit <<<"$previous")
        elif [[ "$offline" == true ]]; then
          [[ -f "$app_state/prepared/$name-latest.json" ]] || fail unavailable 'No retained complete preparation exists for offline installation' 3
          commit=$(jq -er .commit "$app_state/prepared/$name-latest.json")
        else commit=$(flatpak remote-info --user --show-commit flathub "$ref"); fi
      fi
      [[ "$commit" =~ ^[0-9a-f]{64}$ ]] || fail invalid 'Invalid resolved application commit' 2
      plan_path=$app_state/prepared/$name-$commit.json
      if [[ "$action" == rollback ]]; then
        revision=$(jq -er .request.revision "$record")
        [[ "$revision" =~ ^a-[a-f0-9]{32}$ && -f "$app_state/revisions/$revision.json" ]] || fail unavailable 'Application rollback revision is unavailable' 3
        plan=$(jq -ce --arg name "$name" '.applications[$name].plan' "$app_state/revisions/$revision.json") || fail unavailable 'Rollback has no retained application plan' 3
        commit=$(jq -er .commit <<<"$plan")
      elif [[ "$offline" == true || ( "$action" != update && "$action" != prepare && -f "$plan_path" ) ]]; then
        [[ -f "$plan_path" ]] || fail unavailable 'Complete prepared application content is unavailable' 3
        plan=$(jq -c . "$plan_path")
      else
        checkpoint preparing
        folio-applications-transaction prepare "$ref" "$commit" online >"$work/prepared.json" || fail unavailable 'Application content preparation failed' 3
        plan=$(jq -ce '.data | select(.operations|type=="array")' "$work/prepared.json")
        # A no-op transaction can omit already installed dependencies. Keep its
        # previous complete plan when all content is already the same revision.
        if [[ $(jq '.operations|length' <<<"$plan") == 0 && -f "$plan_path" ]]; then plan=$(jq -c . "$plan_path"); fi
        printf '%s\n' "$plan" | folio-atomic-write "$plan_path"
        printf '%s\n' "$plan" | folio-atomic-write "$app_state/prepared/$name-latest.json"
      fi
      [[ $(jq -er .ref <<<"$plan") == "$ref" && $(jq -er .commit <<<"$plan") == "$commit" ]] || fail conflict 'Prepared plan does not match the requested application' 4
      [[ "$action" != prepare ]] || continue
      cached_refs >"$work/cache.json"
      # Verify every retained ref and commit before touching any deployment.
      jq -e --slurpfile cache "$work/cache.json" '.operations | length>0 and all(.[]; . as $op | any($cache[0][]; .ref==$op.ref and .commit==$op.commit))' <<<"$plan" >/dev/null ||
        fail unavailable 'Prepared app, runtime or extension content is unavailable or changed' 3
      # Never change an already deployed shared runtime as an incidental app
      # effect. Reuse that exact current commit, or reject a historical rollback.
      while IFS= read -r runtime; do
        runtime_ref=$(jq -er .ref <<<"$runtime")
        runtime_commit=$(jq -er .commit <<<"$runtime")
        planned_commit=$(jq -r --arg ref "$runtime_ref" '.operations[] | select(.ref==$ref) | .commit' <<<"$plan")
        [[ -n "$planned_commit" && "$planned_commit" != "$runtime_commit" ]] || continue
        [[ "$action" != rollback ]] || fail unavailable 'Rollback would change a shared runtime; retained revision is unavailable' 3
        plan=$(jq --arg ref "$runtime_ref" --arg commit "$runtime_commit" '.operations |= map(if .ref==$ref then .commit=$commit else . end)' <<<"$plan")
      done < <(jq -c '.[] | select(.ref|startswith("runtime/"))' "$work/actual.json")
      printf '%s\n' "$plan" >"$work/deploy.json"
      if jq -e --arg name "$name" '.appEffects[$name] != null' "$record" >/dev/null; then
        jq -e --arg name "$name" --argjson plan "$plan" '.appEffects[$name].plan==$plan' "$record" >/dev/null || fail conflict 'Prepared effects changed since the interrupted task' 4
      else
        jq --arg name "$name" --arg commit "$commit" --argjson plan "$plan" '.appEffects[$name]={commit:$commit,plan:$plan} | .installationStarted=true' "$record" | folio-atomic-write "$record"
      fi
      checkpoint deploying
      folio-applications-transaction deploy "$ref" "$commit" offline "$work/deploy.json" >"$work/deployed.json" || fail conflict 'Local deployment did not match the prepared plan' 4
      inventory >"$work/actual.json"
      [[ $(jq -er --arg ref "$ref" '.[] | select(.ref==$ref) | .commit' "$work/actual.json") == "$commit" ]] || fail failure 'Actual application commit differs after deployment'
    fi
    jq -cnS --arg ref "$ref" --arg commit "$commit" --arg name "$name" --arg digest "$configuration_digest" \
      --argjson plan "$plan" '{format:1,name:$name,ref:$ref,commit:$commit,plan:$plan,configurationDigest:$digest,configurationState:"configuration-pending"}' |
      folio-atomic-write "$owned"
    checkpoint permissions
    if [[ "$name" == zen || "$name" == obs ]]; then
    jq '.installationStarted=true' "$record" | folio-atomic-write "$record"
    permission_args=()
    for permission in network audio wayland x11 downloads videos; do
      enabled=$(jq -r --arg name "$permission" '.permissions[$name] // false' <<<"$desired")
      case "$permission:$enabled" in
        network:true) permission_args+=(--share=network) ;;
        network:false) permission_args+=(--unshare=network) ;;
        audio:true) permission_args+=(--socket=pulseaudio) ;;
        audio:false) permission_args+=(--nosocket=pulseaudio) ;;
        wayland:true) permission_args+=(--socket=wayland) ;;
        wayland:false) permission_args+=(--nosocket=wayland) ;;
        x11:true) permission_args+=(--socket=x11 --socket=fallback-x11) ;;
        x11:false) permission_args+=(--nosocket=x11 --nosocket=fallback-x11) ;;
        downloads:true) permission_args+=(--filesystem=xdg-download) ;;
        downloads:false) permission_args+=(--nofilesystem=xdg-download) ;;
        videos:true) permission_args+=(--filesystem=xdg-videos) ;;
        videos:false) permission_args+=(--nofilesystem=xdg-videos) ;;
      esac
    done
    flatpak override --user "${permission_args[@]}" "$id"
    fi
    flatpak info --user --show-permissions "$ref" >"$work/permissions.txt"
    jq --rawfile permissions "$work/permissions.txt" '.actualPermissions=$permissions' "$owned" | folio-atomic-write "$owned"
    jq '.filesStarted=true' "$record" | folio-atomic-write "$record"
    checkpoint configuring
    flatpak ps --columns=instance,application >"$work/instances.tsv"
    jq -Rn --arg id "$id" '[inputs | split("\t") | select(.[1]==$id) | .[0]]' <"$work/instances.tsv" >"$work/instances.json"
    deploy_files "$name" "$generation" || fail conflict 'Managed configuration has unexpected edits or unsafe paths; explicitly resolve or adopt files' 4
    if [[ "$configuration_state" == restart-required && $(jq length "$work/instances.json") == 0 ]]; then configuration_state=applied; fi
    jq --arg state "$configuration_state" --slurpfile instances "$work/instances.json" \
      '.configurationState=$state | .restartInstances=$instances[0]' "$owned" | folio-atomic-write "$owned"
    jq --arg name "$name" --slurpfile owned "$owned" '.applications[$name]=$owned[0]' "$record" | folio-atomic-write "$record"
  done < <(jq -c '."folio-environment:environment".modules[] | select(.name=="applications") | ."folio-applications:applications" as $settings | $settings.app[]? | select(($settings.native[.name] // false)==false)' "$work/configuration.json")
fi
inventory >"$work/after.json"
jq --slurpfile after "$work/after.json" --arg now "$(date -u +%FT%TZ)" \
  '.after=$after[0] | .phase="succeeded" | .resultStatus="success" | .error=null | .recoveryRequired=false | .updatedAt=$now' "$record" |
  folio-atomic-write "$record"
if [[ "$action" != prepare && "$action" != init && "$action" != refresh ]]; then
  jq '{format:1,id,configurationDigest,generation,applications,before,after}' "$record" | folio-atomic-write "$app_state/revisions/$task_id.json"
fi
finished=true
