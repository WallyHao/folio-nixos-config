#!/usr/bin/env bash
set -euo pipefail

# Run from the development shell. A user/mount namespace provides root identity
# and private /var/lib and /run mounts without touching the host's Folio state.
if [[ ${1:-} != --inside ]]; then
  bootstrap=$(realpath -e -- "${1:?Bootstrap directory is required}")
  exec unshare --user --map-root-user --mount bash "$0" --inside "$bootstrap"
fi
bootstrap=$2
mount --make-rprivate /
mount -t tmpfs -o mode=0755 tmpfs /var/lib
mount -t tmpfs -o mode=0755 tmpfs /run
[[ $(id -u) == 0 ]]
export HOME=/var/lib/test-home XDG_STATE_HOME=/var/lib/test-state XDG_RUNTIME_DIR=/run/test-user
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
folio-repository system init "$bootstrap/models/system" "$bootstrap/system.json"
folio-repository user init "$bootstrap/models/user" "$bootstrap/user.json"
folio-repository system cfg --export --module folio-environment --format json --defaults report-all |
  jq -e '."folio-environment:environment".scope == "system" and
    ."folio-environment:environment".users[0].name == "folio"'
folio-repository user cfg --export --module folio-environment --format json --defaults report-all |
  jq -e '."folio-environment:environment".scope == "user" and
    ."folio-environment:environment".account == "folio"'
test -d /run/folio/sysrepo
test -d "$XDG_RUNTIME_DIR/folio/sysrepo"
test -n "$(find /run/folio/sysrepo -name 'folio_system*' -print -quit)"
test -n "$(find "$XDG_RUNTIME_DIR/folio/sysrepo" -name 'folio_user_0*' -print -quit)"
echo 'Root identity and separate system/user paths and SHM prefixes passed in a private namespace'
