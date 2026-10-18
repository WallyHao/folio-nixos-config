task_id=${1:?Task ID is required}
[[ "$task_id" =~ ^t-[a-f0-9]{32}$ ]] || exit 2
record=$state/deployments/tasks/$task_id.json
exec 8>"$state/deployments/tasks/$task_id.lock"
flock -n 8 || exit 0
[[ $(jq -er .phase "$record") == queued ]] || exit 0
operation_kind=$(jq -er .kind "$record")
plan_id=$(jq -er .planId "$record")
plan=$state/deployments/plans/$plan_id.json
timeout_seconds=$(jq -er .timeoutSeconds "$record")
finished=false
failure_status=failure
failure_message='Worker interrupted before completion; inspect recorded effects'
update_task() {
  jq --arg phase "$1" --arg now "$(date -u +%FT%TZ)" '.phase=$phase | .updatedAt=$now' "$record" |
    folio-atomic-write "$record"
}
worker_exit() {
  local code=$?
  if ! "$finished"; then
    jq --arg message "$failure_message" --arg status "$failure_status" --arg now "$(date -u +%FT%TZ)" \
      '.phase="failed" | .resultStatus=$status | .error=$message | .updatedAt=$now' "$record" |
      folio-atomic-write "$record" || true
  fi
  rm -rf "$work"
  return "$code"
}
trap worker_exit EXIT
trap 'failure_message="Worker interrupted; recovery may be required"; exit 143' TERM INT HUP
update_task validating
[[ $(digest_file "$plan") == "$plan_id" ]]
snapshot=$(jq -er .source "$plan")
[[ "$snapshot" == /nix/store/* && -f "$snapshot/folio-input.json" ]]
account=$(jq -er .owner "$plan")
[[ $(jq -er .scope "$plan") == "$scope" && $(jq -er .scope "$snapshot/folio-input.json") == "$scope" ]]
target=nixosConfigurations.portable.config.system.build.toplevel
if [[ "$scope" == user ]]; then
  descriptor_home=$(jq -er --arg account "$account" '.systemDescriptor.users[] | select(.name==$account) | .home' "$snapshot/folio-input.json")
  [[ "$descriptor_home" == "$HOME" ]]
  target=homeConfigurations.folio.activationPackage
else
  [[ $(id -u) == 0 && "$account" == root ]]
fi
if [[ "$account" != "$(id -un)" || ${DRY_RUN:-} || ${SKIP_SANITY_CHECKS:-} ]]; then
  failure_message='Worker identity/HOME or activation environment is invalid'; exit 1
fi
case "$operation_kind" in
  build)
    update_task building
    failure_message='Nix build failed or exceeded its recorded timeout'
    export -f nix_as_builder
    export scope
    # shellcheck disable=SC2016
    timeout --kill-after=10 "$timeout_seconds" bash -c 'nix_as_builder build --no-update-lock-file --no-link --json "$1"' \
      _ "path:$snapshot#$target" >"$work/build.json"
    artifact=$(jq -er '.[0].outputs.out' "$work/build.json")
    [[ "$artifact" == /nix/store/* ]]
    if [[ "$scope" == user ]]; then
      [[ -x "$artifact/activate" && -f "$artifact/folio-home.json" ]]
      jq -e --arg account "$account" --arg home "$HOME" --slurpfile input "$snapshot/folio-input.json" \
        '.format==1 and .account==$account and .home==$home and .configurationDigest==$input[0].configurationDigest' \
        "$artifact/folio-home.json" >/dev/null
    else
      [[ -x "$artifact/bin/switch-to-configuration" && -f "$artifact/folio-system.json" ]]
      jq -e --slurpfile input "$snapshot/folio-input.json" '.format==1 and .scope=="system" and
        .environment==$input[0].configuration."folio-environment:environment".name and
        .configurationDigest==$input[0].configurationDigest' "$artifact/folio-system.json" >/dev/null
    fi
    nix-store --realise "$artifact" --add-root "$state/deployments/roots/build-$plan_id" --indirect >/dev/null
    jq -cnS --arg artifact "$artifact" --slurpfile plan "$plan" \
      '{format:1,artifact:$artifact,inputDigest:$plan[0].inputDigest,configurationDigest:$plan[0].configurationDigest}' |
      folio-atomic-write "$state/deployments/builds/$plan_id.json"
    jq --arg artifact "$artifact" '.artifact=$artifact' "$record" | folio-atomic-write "$record"
    ;;
  apply)
    lock_configuration
    recover_configuration
    if ! plan_current; then failure_status=conflict; failure_message='Plan became stale before activation'; exit 1; fi
    artifact=$(jq -er .artifact "$state/deployments/builds/$plan_id.json")
    [[ "$artifact" == /nix/store/* ]]
    before=$(selected_profile)
    if [[ "$scope" == user && -n "$before" && ! -f "$state/deployments/current.json" ]]; then
      failure_status=conflict; failure_message='Existing Home Manager profile requires explicit migration'; exit 1
    fi
    if [[ "$scope" == user && -n "$before" ]]; then
      # Adapted from Sylphy profile authority: later unmanaged edits conflict,
      # while initial Home Manager adoption uses unique automatic backups.
      if ! managed_files_match "$before"; then
        failure_status=conflict; failure_message='A managed file was changed; see worker journal'; exit 1
      fi
    fi
    nix-store --realise "$artifact" --add-root "$state/deployments/roots/apply-$task_id" --indirect >/dev/null
    if [[ -n "$before" ]]; then
      nix-store --realise "$before" --add-root "$state/deployments/roots/before-$task_id" --indirect >/dev/null
    fi
    jq --arg before "$before" --arg after "$artifact" '.beforeProfile=$before | .afterProfile=$after' "$record" |
      folio-atomic-write "$record"
    update_task activating
    mkdir -p "$(dirname "$profile")"
    failure_message='Profile selection or scoped activation failed; recovery is required'
    nix-env --profile "$profile" --set "$artifact"
    if [[ "$scope" == user ]]; then
      export HOME_MANAGER_BACKUP_EXT=folio-backup-$task_id
      unset HOME_MANAGER_BACKUP_OVERWRITE DRY_RUN SKIP_SANITY_CHECKS
      timeout --kill-after=10 "$timeout_seconds" "$artifact/activate" --driver-version 1
    else
      [[ -x "$artifact/bin/switch-to-configuration" ]]
      jq -e --slurpfile input "$snapshot/folio-input.json" '.scope=="system" and
        .configurationDigest==$input[0].configurationDigest' "$artifact/folio-system.json" >/dev/null
      timeout --kill-after=10 "$timeout_seconds" "$artifact/bin/switch-to-configuration" switch
    fi
    update_task verifying
    [[ $(selected_profile) == "$artifact" ]]
    if [[ "$scope" == user ]]; then managed_files_match "$artifact"
    else
      [[ $(readlink -e /run/current-system) == "$artifact" ]]
      [[ $(readlink -e /etc/localtime) == "$(readlink -e "$artifact/etc/localtime")" ]]
    fi
    foot_digest=null
    if [[ "$scope" == user && -f "$artifact/home-files/.config/foot/foot.ini" ]]; then
      foot_digest=$(jq -cn --arg value "$(digest_file "$HOME/.config/foot/foot.ini")" '$value')
    fi
    jq -cnS --arg artifact "$artifact" --arg planId "$plan_id" --arg taskId "$task_id" \
      --argjson footDigest "$foot_digest" --slurpfile plan "$plan" \
      '{format:1,artifact:$artifact,planId:$planId,taskId:$taskId,source:$plan[0].source,
        inputDigest:$plan[0].inputDigest,configurationDigest:$plan[0].configurationDigest,footDigest:$footDigest}' |
      folio-atomic-write "$state/deployments/current.json"
    ;;
  *) failure_message='Unknown recorded worker operation'; exit 2 ;;
esac
jq --arg now "$(date -u +%FT%TZ)" '.phase="succeeded" | .resultStatus="success" | .updatedAt=$now' "$record" |
  folio-atomic-write "$record"
finished=true
