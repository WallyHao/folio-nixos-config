# Pi writes settings in place, so a link into a writable Folio checkout preserves
# native /settings and package management. All other application state stays here.
umask 077
config=${FOLIO_PI_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/folio/pi}
if [[ ! -e "$config" && ! -L "$config" && -z ${FOLIO_PI_CONFIG_DIR:-} ]]; then
  config=$FOLIO_PI_BUNDLED_CONFIG
fi
[[ -d "$config" ]] || { echo "Pi configuration directory does not exist: $config" >&2; exit 1; }
config=$(realpath -e -- "$config")
export PI_CODING_AGENT_DIR=${PI_CODING_AGENT_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/folio/pi}
PI_CODING_AGENT_DIR=$(realpath -m -- "$PI_CODING_AGENT_DIR")
case "$PI_CODING_AGENT_DIR/" in
  "$config/"*) echo 'Pi runtime state must be outside its configuration directory' >&2; exit 1 ;;
esac
mkdir -p -- "$PI_CODING_AGENT_DIR"
chmod 700 -- "$PI_CODING_AGENT_DIR"

# Serialize link maintenance, not agent sessions. Refuse to overwrite personal
# files or unrelated links, including when the user supplied a native agent dir.
exec {lock_fd}>"$PI_CODING_AGENT_DIR/.folio-config.lock"
flock "$lock_fd"
previous=
if [[ -f "$PI_CODING_AGENT_DIR/.folio-config-source" ]]; then
  previous=$(cat -- "$PI_CODING_AGENT_DIR/.folio-config-source")
fi
resources=(settings.json models.json mcp.json keybindings.json
  AGENTS.override.md AGENTS.md AGENTS.MD CLAUDE.md CLAUDE.MD SYSTEM.md APPEND_SYSTEM.md
  extensions skills prompts themes packages)
for name in "${resources[@]}"; do
  target=$PI_CODING_AGENT_DIR/$name
  if [[ -L "$target" ]]; then
    existing=$(readlink -- "$target")
    if [[ "$existing" != "$config/$name" && ( -z "$previous" || "$existing" != "$previous/$name" ) ]]; then
      echo "Refusing to replace an unrelated Pi configuration link: $target" >&2; exit 1
    fi
  elif [[ -e "$target" ]]; then
    echo "Refusing to replace existing Pi configuration: $target" >&2; exit 1
  fi
done
for name in "${resources[@]}"; do
  ln -sfn -- "$config/$name" "$PI_CODING_AGENT_DIR/$name"
done
printf '%s\n' "$config" >"$PI_CODING_AGENT_DIR/.folio-config-source"
flock -u "$lock_fd"
exec {lock_fd}>&-
exec "$FOLIO_PI_PACKAGE/bin/pi" "$@"
