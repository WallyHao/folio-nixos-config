# The test driver signals this supervisor, so explicitly reap both descendants.
# xvfb-run's waiting shell can otherwise leave QEMU holding the driver's pipes.
set -euo pipefail
export PATH=@coreutils@/bin
directory=$(mktemp -d)
xvfb_pid=
qemu_pid=
cleanup() {
  trap - EXIT TERM INT
  for child in "$qemu_pid" "$xvfb_pid"; do
    if [[ -n "$child" ]]; then kill "$child" 2>/dev/null || true; fi
  done
  for child in "$qemu_pid" "$xvfb_pid"; do
    if [[ -n "$child" ]]; then wait "$child" 2>/dev/null || true; fi
  done
  rm -rf "$directory"
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
@xvfb@ -displayfd 3 -screen 0 1280x800x24 -nolisten tcp -ac 3>"$directory/display" &
xvfb_pid=$!
for (( attempt=0; attempt<100; attempt++ )); do
  [[ ! -s "$directory/display" ]] || break
  kill -0 "$xvfb_pid"
  sleep 0.05
done
[[ -s "$directory/display" ]]
export DISPLAY=:$(cat "$directory/display")
@qemu@ "$@" -display sdl,gl=on &
qemu_pid=$!
code=0
wait "$qemu_pid" || code=$?
exit "$code"
