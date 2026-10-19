: "${HOME:?}"
[[ "$HOME" == /* && $(id -u) != 0 ]] || exit 3
config_root=${XDG_CONFIG_HOME:-$HOME/.config}
data_root=${XDG_DATA_HOME:-$HOME/.local/share}
[[ "$config_root" == "$HOME/"* && "$data_root" == "$HOME/"* ]] || exit 3
seed_file() {
  local source=$1 destination=$2 directory component relative temporary
  directory=${destination%/*}
  relative=${directory#"$HOME/"}
  component=$HOME
  # Do not follow symlinks into an unrelated writable profile or directory.
  local -a components
  IFS=/ read -r -a components <<<"$relative"
  for relative in "${components[@]}"; do
    [[ -n "$relative" && "$relative" != . && "$relative" != .. ]] || return 3
    component=$component/$relative
    [[ ! -L "$component" ]] || return 0
    if [[ ! -e "$component" ]]; then mkdir -m 0700 "$component"; fi
    [[ -d "$component" && -O "$component" ]] || return 3
  done
  [[ ! -e "$destination" && ! -L "$destination" ]] || return 0
  temporary=$(mktemp "$directory/.folio-input.XXXXXX")
  cp -- "$source" "$temporary"
  chmod 0600 "$temporary"
  # A hard-link publication is atomic and never replaces a concurrently created
  # personal file. The final file is regular, not a sandbox-inaccessible symlink.
  ln -- "$temporary" "$destination" 2>/dev/null || [[ -e "$destination" || -L "$destination" ]]
  rm -f -- "$temporary"
}
seed_file @profile@ "$config_root/fcitx5/profile"
seed_file @rimeDefaults@ "$data_root/fcitx5/rime/default.custom.yaml"
