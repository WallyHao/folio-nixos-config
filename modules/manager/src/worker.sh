task_id=${1:?Task ID is required}
[[ "$task_id" =~ ^t-[a-f0-9]{32}$ ]] || exit 2
record=$state/deployments/tasks/$task_id.json
exec 8>"$state/deployments/tasks/$task_id.lock"
flock -n 8 || exit 0
[[ $(jq -er .phase "$record") == queued ]] || exit 0
operation_kind=$(jq -er .kind "$record")
plan_id=$(jq -er .planId "$record")
plan=$state/deployments/plans/$plan_id.json
snapshot=$(jq -er .source "$plan")
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
[[ "$snapshot" == /nix/store/* && -f "$snapshot/folio-input.json" ]]
account=$(jq -er .owner "$plan")
descriptor_home=$(jq -er --arg account "$account" '.systemDescriptor.users[] | select(.name==$account) | .home' "$snapshot/folio-input.json")
if [[ "$account" != "$(id -un)" || "$descriptor_home" != "$HOME" || ${DRY_RUN:-} || ${SKIP_SANITY_CHECKS:-} ]]; then
  failure_message='Worker identity/HOME or activation environment is invalid'; exit 1
fi
case "$operation_kind" in
  build)
    update_task building
    failure_message='Nix build failed or exceeded its recorded timeout'
    timeout --kill-after=10 "$timeout_seconds" nix build --no-update-lock-file --no-link --json \
      "path:$snapshot#homeConfigurations.folio.activationPackage" >"$work/build.json"
    artifact=$(jq -er '.[0].outputs.out' "$work/build.json")
    [[ "$artifact" == /nix/store/* && -x "$artifact/activate" && -f "$artifact/folio-home.json" ]]
    jq -e --arg account "$account" --arg home "$HOME" --slurpfile input "$snapshot/folio-input.json" \
      '.format==1 and .account==$account and .home==$home and .configurationDigest==$input[0].configurationDigest' \
      "$artifact/folio-home.json" >/dev/null
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
    [[ "$artifact" == /nix/store/* && -x "$artifact/activate" ]]
    before=$(readlink -e "$profile" || true)
    if [[ -n "$before" && ! -f "$state/deployments/current.json" ]]; then
      failure_status=conflict; failure_message='Existing Home Manager profile requires explicit migration'; exit 1
    fi
    if [[ -n "$before" ]]; then
      # Adapted from Sylphy profile authority: later unmanaged edits conflict,
      # while initial Home Manager adoption uses unique automatic backups.
      if ! managed_files_match "$before"; then
        failure_status=conflict; failure_message='A managed file was changed; see worker journal'; exit 1
      fi
    fi
    nix-store --realise "$artifact" --add-root "$state/deployments/roots/apply-$task_id" --indirect >/dev/null
    jq --arg before "$before" --arg after "$artifact" '.beforeProfile=$before | .afterProfile=$after' "$record" |
      folio-atomic-write "$record"
    update_task activating
    mkdir -p "$(dirname "$profile")"
    failure_message='Profile selection or Home Manager activation failed; recovery is required'
    nix-env --profile "$profile" --set "$artifact"
    export HOME_MANAGER_BACKUP_EXT=folio-backup-$task_id
    unset HOME_MANAGER_BACKUP_OVERWRITE DRY_RUN SKIP_SANITY_CHECKS
    timeout --kill-after=10 "$timeout_seconds" "$artifact/activate" --driver-version 1
    update_task verifying
    [[ $(readlink -e "$profile") == "$artifact" ]]
    managed_files_match "$artifact"
    foot_digest=null
    if [[ -f "$artifact/home-files/.config/foot/foot.ini" ]]; then
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
