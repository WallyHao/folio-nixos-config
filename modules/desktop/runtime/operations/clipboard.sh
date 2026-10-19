[[ -n ${WAYLAND_DISPLAY:-} ]] || { echo 'Clipboard selection requires an active Wayland session' >&2; exit 3; }
selection=$(cliphist list | fuzzel --dmenu --prompt='Clipboard> ') || exit 0
[[ -n "$selection" ]] || exit 0
printf '%s\n' "$selection" | cliphist decode | wl-copy
