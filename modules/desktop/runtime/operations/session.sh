case "${1:-}" in reboot|poweroff) action=$1 ;; *) echo 'Expected reboot or poweroff' >&2; exit 2 ;; esac
choice=$(printf 'Yes\nNo\n' | fuzzel --dmenu --lines=2 --prompt="Confirm $action? ") || exit 0
test "$choice" = Yes || exit 0
exec folio --system system "$action"
