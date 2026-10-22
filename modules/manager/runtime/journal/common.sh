mkdir -p "$state/deployments/plans" "$state/deployments/tasks" \
  "$state/deployments/builds" "$state/deployments/roots"
profile=${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager
if [[ "$scope" == system ]]; then profile=/nix/var/nix/profiles/system; fi
plan=
manager_option=--user
[[ "$scope" != system ]] || manager_option=--system
selected_profile() {
  if [[ "$scope" == system && ! -L "$profile" ]]; then readlink -e /run/current-system
  else readlink -e "$profile" || true; fi
}
task_reply() {
  jq -cn --arg id "$1" --slurpfile task "$state/deployments/tasks/$1.json" \
    '{status:"success","task-id":$id,data:{"folio-deployment:result":{timeoutSeconds:$task[0].timeoutSeconds}}}'
}
start_task() {
  local id=$1 record=$state/deployments/tasks/$1.json worker timeout_seconds
  worker=$(jq -er .worker "$record")
  timeout_seconds=$(jq -er .timeoutSeconds "$record")
  [[ "$worker" =~ ^/nix/store/[a-z0-9]{32}-[^/]+/bin/folio-manager-worker$ && -x "$worker" ]] || return 1
  if systemctl "$manager_option" is-active --quiet "folio-task-$id.service"; then return 0; fi
  systemd-run "$manager_option" --collect --quiet --unit="folio-task-$id" --service-type=exec \
    --property="RuntimeMaxSec=$((timeout_seconds + 60))" --property=TimeoutStopSec=10 \
    --setenv="HOME=$HOME" --setenv="USER=$(id -un)" \
    --setenv="XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}" \
    --setenv="XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run}" --setenv="FOLIO_BOOTSTRAP=$FOLIO_BOOTSTRAP" --setenv="FOLIO_SCOPE=$scope" \
    "$worker" "$id"
}
recover_tasks() {
  local record id phase
  shopt -s nullglob
  for record in "$state/deployments/tasks/"*.json; do
    id=$(jq -er .id "$record")
    phase=$(jq -er .phase "$record")
    case "$phase" in
      queued) start_task "$id" || return 1 ;;
      validating|building|activating|verifying|failed|interrupted)
        if [[ "$phase" == failed || "$phase" == interrupted ]] &&
            ! jq -e 'if has("recoveryRequired") then .recoveryRequired else .afterProfile != null end' "$record" >/dev/null; then continue; fi
        if ! systemctl "$manager_option" is-active --quiet "folio-task-$id.service"; then
          exec 6>"$state/deployments/tasks/$id.lock"
          if flock -n 6; then
            reconcile_interrupted_task "$record"
          fi
          exec 6>&-
        fi ;;
    esac
  done
}
managed_files_match() {
  local generation=$1 expected relative
  [[ -d "$generation/home-files" ]] || return 1
  while IFS= read -r -d '' expected; do
    relative=${expected#"$generation/home-files/"}
    if [[ $(readlink -e "$HOME/$relative" || true) != "$(readlink -e "$expected")" ]]; then
      echo "Managed file differs: $relative" >&2
      return 1
    fi
  done < <(find -L "$generation/home-files" -type f -print0)
}
applied_artifact_matches() {
  local artifact=$1
  [[ $(selected_profile) == "$artifact" ]] || return 1
  artifact_effects_match "$artifact"
}
artifact_effects_match() {
  local artifact=$1
  if [[ "$scope" == user ]]; then managed_files_match "$artifact"
  else
    [[ $(readlink -e /run/current-system) == "$artifact" ]] &&
      [[ $(readlink -e /etc/localtime) == "$(readlink -e "$artifact/etc/localtime")" ]]
  fi
}
plan_current() {
  current_configuration >"$work/current.json"
  [[ $(digest_file "$work/current.json") == "$(jq -er .configurationDigest "$plan")" ]] || return 1
  jq -cS . "$descriptor_path" >"$work/descriptor.json"
  local descriptor_field=descriptorDigest
  [[ ${1:-} != review ]] || descriptor_field=beforeDescriptorDigest
  [[ $(digest_file "$work/descriptor.json") == "$(jq -er --arg field "$descriptor_field" '.[$field] // .descriptorDigest' "$plan")" ]] || return 1
  [[ $(selected_profile) == "$(jq -r .beforeProfile "$plan")" ]] || return 1
}
