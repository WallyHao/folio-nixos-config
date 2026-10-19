case "${1:-}" in reboot|poweroff) ;; *) echo 'Expected reboot or poweroff' >&2; exit 2 ;; esac
zenity --question --title='Session action' --text="Confirm $1?" || exit 0
exec folio --system system "$1"
