mkdir -p "$state/deployments/plans" "$state/deployments/tasks" \
  "$state/deployments/builds" "$state/deployments/roots"
profile=${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager
plan=
task_reply() {
  jq -cn --arg id "$1" --slurpfile task "$state/deployments/tasks/$1.json" \
    '{status:"success","task-id":$id,data:{"folio-deployment:result":{timeoutSeconds:$task[0].timeoutSeconds}}}'
}
start_task() {
  local id=$1 record=$state/deployments/tasks/$1.json worker timeout_seconds
  worker=$(jq -er .worker "$record")
  timeout_seconds=$(jq -er .timeoutSeconds "$record")
  [[ "$worker" =~ ^/nix/store/[a-z0-9]{32}-[^/]+/bin/folio-manager-worker$ && -x "$worker" ]] || return 1
  if systemctl --user is-active --quiet "folio-task-$id.service"; then return 0; fi
  systemd-run --user --collect --quiet --unit="folio-task-$id" --service-type=exec \
    --property="RuntimeMaxSec=$((timeout_seconds + 60))" --property=TimeoutStopSec=10 \
    --setenv="HOME=$HOME" --setenv="USER=$(id -un)" \
    --setenv="XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}" \
    --setenv="XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" --setenv="FOLIO_BOOTSTRAP=$FOLIO_BOOTSTRAP" \
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
      validating|building|activating|verifying)
        if ! systemctl --user is-active --quiet "folio-task-$id.service"; then
          exec 6>"$state/deployments/tasks/$id.lock"
          if flock -n 6; then
            jq '.phase="interrupted" | .resultStatus="unavailable" |
              .error="Worker disappeared; inspect actual effects before recovery"' "$record" |
              folio-atomic-write "$record"
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
plan_current() {
  current_configuration >"$work/current.json"
  [[ $(digest_file "$work/current.json") == "$(jq -er .configurationDigest "$plan")" ]] || return 1
  jq -cS . "$FOLIO_BOOTSTRAP/system-descriptor.json" >"$work/descriptor.json"
  [[ $(digest_file "$work/descriptor.json") == "$(jq -er .descriptorDigest "$plan")" ]] || return 1
  [[ $(readlink -e "$profile" || true) == "$(jq -r .beforeProfile "$plan")" ]] || return 1
}
