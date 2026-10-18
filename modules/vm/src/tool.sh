umask 0077
action=${1:-}
shift || true
[[ $# -ge 1 ]] || { echo 'Usage: folio-vm-tool ACTION JOB_ID [ARGUMENTS]' >&2; exit 2; }
job_id=$1; shift
[[ "$job_id" =~ ^[a-z][a-z0-9-]{0,63}$ ]] || exit 2
vm_root=${XDG_STATE_HOME:-$HOME/.local/state}/folio/vm
job=$vm_root/jobs/$job_id
unit=folio-vm-$job_id
record=$job/job.json
mkdir -p "$vm_root/jobs"
mkdir -p "$vm_root/locks"
case "$action" in
  build-worker|run-worker) ;;
  *) exec 9>"$vm_root/locks/$job_id.lock"
     flock -w 5 9 || { echo 'VM job is busy' >&2; exit 4; } ;;
esac
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
result() {
  local status=$1 error=${2:-} code=0
  case "$status" in failure) code=1 ;; invalid) code=2 ;; unavailable) code=3 ;; conflict) code=4 ;; esac
  data=null
  [[ ! -f "$record" ]] || data=$(jq -c . "$record")
  jq -cn --arg status "$status" --argjson data "$data" --arg error "$error" --arg id "$job_id" \
    '{status:$status,data:$data,error:(if $error=="" then null else $error end),taskId:$id}'
  exit "$code"
}
save_phase() {
  jq --arg phase "$1" '.phase=$phase' "$record" | folio-atomic-write "$record"
}
active() { systemctl --user is-active --quiet "$unit.service"; }
case "$action" in
  build)
    [[ $# == 1 ]] || result invalid 'Build requires an immutable source directory'
    source_path=$(realpath -e -- "$1") || result invalid 'Missing source'
    [[ "$source_path" == /nix/store/* && -f "$source_path/flake.lock" ]] || result invalid 'Source must be an immutable Flake snapshot'
    if [[ -f "$record" ]]; then
      [[ $(jq -r .source "$record") == "$source_path" ]] || result conflict 'Job ID is bound to another source'
      result success
    fi
    mkdir "$job"
    nix-store --realise "$source_path" --add-root "$job/source-root" --indirect >/dev/null
    jq -cn --arg id "$job_id" --arg source "$source_path" '{id:$id,source:$source,phase:"queued"}' |
      folio-atomic-write "$record"
    systemd-run --user --quiet --collect --unit="folio-vm-build-$job_id" --service-type=exec \
      --property=RuntimeMaxSec=1860 --setenv="HOME=$HOME" --setenv="XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}" \
      --setenv="XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" @tool@ build-worker "$job_id"
    result success ;;
  build-worker)
    [[ -f "$record" ]] || result invalid 'Unknown job'
    save_phase building
    if timeout --kill-after=10 1800 nix build --no-update-lock-file --no-link --json \
        "path:$(jq -er .source "$record")#packages.x86_64-linux.vm-image" >"$work/build.json" 2>"$job/build.log"; then
      image=$(jq -er '.[0].outputs.out' "$work/build.json")
      [[ -f "$image/folio.qcow2" ]] || { save_phase failed; result failure 'Image output is missing'; }
      nix-store --realise "$image" --add-root "$job/image-root" --indirect >/dev/null
      jq --arg image "$image" '.phase="ready" | .image=$image' "$record" | folio-atomic-write "$record"
      result success
    fi
    save_phase failed; result failure 'VM build failed; inspect the retained build log' ;;
  start)
    [[ -f "$record" ]] || result invalid 'Unknown job'
    active && result success
    case "$(jq -r .phase "$record")" in ready|stopped|failed|interrupted) ;; *) result conflict 'VM job is not ready to start' ;; esac
    image=$(jq -er .image "$record") || result unavailable 'Build the image first'
    nix-store --realise "$image" --add-root "$job/image-root" --indirect >/dev/null
    [[ -r /dev/kvm && -w /dev/kvm ]] || result unavailable 'KVM access is unavailable'
    memory=${1:-2048}; cores=${2:-2}
    [[ "$memory" =~ ^[0-9]{3,4}$ && "$memory" -ge 512 && "$memory" -le 8192 && "$cores" =~ ^[1-8]$ ]] || result invalid 'Invalid memory or CPU count'
    [[ "$image" == /nix/store/* && -f "$image/folio.qcow2" ]] || result invalid 'Image must be an immutable recorded artifact'
    if [[ ! -f "$job/disk.qcow2" ]]; then
      qemu-img create -q -f qcow2 -F qcow2 -b "$image/folio.qcow2" "$job/disk.qcow2"
      cp @vars@ "$job/vars.fd"
      chmod u+w "$job/vars.fd"
    fi
    jq --argjson memory "$memory" --argjson cores "$cores" '.memoryMiB=$memory | .cores=$cores | .phase="starting"' "$record" |
      folio-atomic-write "$record"
    systemd-run --user --quiet --collect --unit="$unit" --service-type=exec \
      --setenv="HOME=$HOME" --setenv="XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}" \
      --setenv="XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" @tool@ run-worker "$job_id"
    for (( attempt=0; attempt<100; attempt++ )); do
      [[ ! -S "$job/qmp.sock" ]] || result success
      active || result failure 'QEMU exited; inspect serial.log and the user service journal'
      sleep 0.1
    done
    result unavailable 'QEMU monitor startup timed out' ;;
  run-worker)
    [[ -f "$record" ]] || result invalid 'Unknown job'
    rm -f "$job/qmp.sock"
    save_phase running
    code=0
    qemu-system-x86_64 -enable-kvm -machine q35 -cpu host \
      -m "$(jq -er .memoryMiB "$record")" -smp "$(jq -er .cores "$record")" \
      -drive if=pflash,format=raw,readonly=on,file=@code@ \
      -drive "if=pflash,format=raw,file=$job/vars.fd" \
      -drive "if=virtio,format=qcow2,file=$job/disk.qcow2" \
      -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
      -display none -monitor none -serial "file:$job/serial.log" \
      -qmp "unix:$job/qmp.sock,server=on,wait=off" || code=$?
    jq --argjson code "$code" '.exitCode=$code | .phase=(if $code==0 then "stopped" else "failed" end)' "$record" |
      folio-atomic-write "$record"
    result "$([[ "$code" == 0 ]] && echo success || echo failure)" ;;
  status)
    [[ -f "$record" ]] || result invalid 'Unknown job'
    if [[ $(jq -r .phase "$record") == running ]] && ! active; then save_phase interrupted; fi
    if [[ $(jq -r .phase "$record") == building ]] && ! systemctl --user is-active --quiet "folio-vm-build-$job_id.service"; then save_phase interrupted; fi
    result success ;;
  stop)
    [[ -f "$record" ]] || result invalid 'Unknown job'
    active || result success
    if ! printf '%s\n' '{"execute":"qmp_capabilities"}' '{"execute":"system_powerdown"}' |
        timeout 5 socat - "UNIX-CONNECT:$job/qmp.sock" >"$work/qmp.json"; then
      # QMP remains open after its reply, so timeout is normal; liveness below
      # determines the actual guest result rather than transport exit alone.
      :
    fi
    for (( attempt=0; attempt<60; attempt++ )); do
      active || result success
      sleep 0.5
    done
    result unavailable 'Guest has not stopped; its disk and logs are preserved' ;;
  cleanup)
    active && result conflict 'Stop the guest before cleanup'
    systemctl --user is-active --quiet "folio-vm-build-$job_id.service" && result conflict 'A build is still active'
    [[ -d "$job" && ! -L "$job" ]] || result invalid 'Unknown or redirected job'
    mkdir -p "$vm_root/logs"
    evidence=$vm_root/logs/$job_id-$(date -u +%Y%m%dT%H%M%SZ)
    mkdir "$evidence"
    for log in job.json build.log serial.log; do [[ ! -f "$job/$log" ]] || cp "$job/$log" "$evidence/"; done
    rm -rf "$job"
    result success ;;
  *) result invalid 'Unknown VM operation' ;;
esac
