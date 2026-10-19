set -Eeuo pipefail
umask 077
tool=$(dirname "$(dirname "$(readlink -f "$0")")")
state=/var/lib/folio-home-retirement
action=${1:-status}
die() { echo "Home retirement stopped: $*" >&2; return 1; }
preflight() {
  [[ $(id -u) == 0 ]] || die 'Use the local sudo launcher'
  [[ $(getent passwd folio | cut -d: -f3,6) == 1000:/home/folio ]] || die 'Unexpected account'
  ! getent passwd sylphy >/dev/null || die 'Legacy account still exists'
  [[ -d /home/folio && ! -L /home/folio && -L /home/sylphy && $(readlink /home/sylphy) == /home/folio ]] || die 'Unexpected home layout'
}
case "$action" in
  launch)
    preflight
    system=$(realpath -e "${2:?System closure required}")
    home=$(realpath -e "${3:?Home generation required}")
    [[ $system == /nix/store/* && $home == /nix/store/* ]] || die 'Immutable store outputs required'
    bootstrap=$(jq -er .bootstrap "$system/folio-system.json")
    jq -e '.name == "laptop-migration"' "$bootstrap/target.json" >/dev/null
    if grep -RIl -- '/home/sylphy' "$system/etc/tmpfiles.d" > /dev/null; then
      die 'System still recreates the legacy home alias'
    fi
    jq -e '.user == "folio" and .home == "/home/folio"' "$home/sylphy-home.json" >/dev/null
    [[ ! -e "$state/phase" ]] || die 'An earlier retirement exists; inspect its journal before retrying'
    install -d -m 700 "$state/roots"
    printf '%s\n' "$system" >"$state/new-system"
    printf '%s\n' "$home" >"$state/new-home"
    readlink -f /run/current-system >"$state/old-system"
    readlink -f /home/folio/.local/state/nix/profiles/home-manager >"$state/old-home"
    for item in new-system new-home old-system old-home; do
      nix-store --add-root "$state/roots/$item" --indirect --realise "$(cat "$state/$item")" >/dev/null
    done
    nix-store --add-root "$state/roots/tool" --indirect --realise "$tool" >/dev/null
    printf '%s\n' queued >"$state/phase"
    echo 'Home retirement starts in 20 seconds, closes the desktop and reboots. Save your work.'
    systemd-run --unit=folio-home-retirement --collect "$tool/bin/folio-retire-home" worker
    ;;
  worker)
    preflight
    # Reuse the already rehearsed login shutdown helper with a separate journal.
    # shellcheck disable=SC1090
    source <(sed '/^action=/,$d' @migration@/bin/folio-migrate-account)
    state=/var/lib/folio-home-retirement
    session_stopped=false
    boot_started=false
    recover() {
      code=$?
      trap - ERR
      set +e
      if [[ ! -e /home/sylphy && ! -L /home/sylphy ]]; then ln -s /home/folio /home/sylphy; fi
      if "$boot_started"; then
        previous=$(cat "$state/old-system")
        nix-env --profile /nix/var/nix/profiles/system --set "$previous"
        "$previous/bin/switch-to-configuration" boot
      fi
      echo failed >"$state/phase"
      if "$session_stopped"; then restart_login_services; fi
      exit "$code"
    }
    trap recover ERR
    sleep 20
    stop_login_sessions folio
    snapshot=/home/.folio-migration-backups/folio-before-home-retirement
    [[ ! -e "$snapshot" ]] || die 'Retirement snapshot already exists'
    btrfs subvolume snapshot -r /home "$snapshot"
    printf '%s\n' "$snapshot" >"$state/snapshot"
    echo updating >"$state/phase"
    runuser -u folio -- env HOME=/home/folio USER=folio LOGNAME=folio XDG_STATE_HOME=/home/folio/.local/state \
      @python@ @pathsHelper@
    runuser -u folio -- env HOME=/home/folio USER=folio LOGNAME=folio XDG_STATE_HOME=/home/folio/.local/state \
      "$(cat "$state/new-home")/activate" --migrate
    ! pgrep -u 1000 >/dev/null || die 'User processes restarted during activation; refusing to retire a live session'
    # Check actual generated home files, rather than package build success alone.
    if grep -RIl -- '/home/sylphy' "$(cat "$state/new-home")/home-files" >"$state/unresolved-home-files"; then
      die 'New Home Manager files still refer to the old home'
    fi
    boot_started=true
    system=$(cat "$state/new-system")
    nix-env --profile /nix/var/nix/profiles/system --set "$system"
    "$system/bin/switch-to-configuration" boot
    [[ -L /home/sylphy && $(readlink /home/sylphy) == /home/folio ]]
    unlink /home/sylphy
    echo ready-to-boot >"$state/phase"
    sync
    systemctl reboot
    ;;
  status)
    if [[ -r "$state/phase" ]]; then cat "$state/phase"; fi
    ls -ld /home/folio /home/sylphy 2>/dev/null || true
    ;;
  *) die 'Usage: folio-retire-home launch SYSTEM HOME | status' ;;
esac
