set -Eeuo pipefail
umask 077
state=/var/lib/folio-migration
old_home=/home/sylphy
new_home=/home/folio
session_stopped=false
identity_started=false
boot_started=false

die() { echo "Migration stopped: $*" >&2; return 1; }
root_only() { [[ $(id -u) == 0 ]] || die 'Run this action with sudo from a local terminal'; }
pin() {
  local path=$1 name=$2
  [[ -e "$path" ]] || return 0
  # A preparation failure can leave valid roots before a journal is queued.
  # Retain those roots and use a distinct name for an updated tool/system.
  if [[ -L "$state/roots/$name" ]]; then
    [[ $(readlink -f "$state/roots/$name") != $(realpath -e "$path") ]] || return 0
    name="$name-$(basename "$path")"
    if [[ -L "$state/roots/$name" ]]; then
      [[ $(readlink -f "$state/roots/$name") == $(realpath -e "$path") ]]
      return
    fi
  fi
  nix-store --add-root "$state/roots/$name" --indirect --realise "$path" >/dev/null
}
backup_accounts() {
  local entry
  for entry in passwd shadow group; do
    [[ -f "/etc/$entry" ]] || die "Required account file is missing: $entry"
    cp -a "/etc/$entry" "$state/account-backup/"
  done
  # NixOS does not require a gshadow file. Record its absence explicitly.
  if [[ -f /etc/gshadow ]]; then
    cp -a /etc/gshadow "$state/account-backup/"
  else
    touch "$state/account-backup/gshadow.absent"
  fi
}
preflight() {
  root_only
  [[ $(getent passwd sylphy | cut -d: -f3,6) == "1000:$old_home" ]] || die 'Unexpected source account';
  ! getent passwd folio >/dev/null || die 'Destination account already exists';
  [[ -d "$old_home" && ! -L "$old_home" ]] || die 'Unexpected source home layout';
  if [[ -e "$new_home" || -L "$new_home" ]]; then
    [[ ${1:-} == retry && -L "$new_home" && $(readlink "$new_home") == "$old_home" && $(stat -c %u "$new_home") == 0 ]] || die 'Unexpected destination home layout'
  fi
  [[ $(findmnt -n -o FSTYPE --target /home) == btrfs ]] || die 'Expected Btrfs home filesystem';
  btrfs subvolume show /home >/dev/null
  [[ -s /var/lib/sylphy-mihomo/config.json && -s /var/lib/sylphy-mihomo-private/provider.yaml ]] || die 'Existing proxy policy/provider is unavailable';
  [[ ! -e /var/lib/folio-mihomo ]] || die 'Destination proxy state already exists';
  [[ -f "$system/folio-system.json" && -x "$system/bin/switch-to-configuration" ]] || die 'Invalid system closure';
  local bootstrap
  bootstrap=$(jq -er .bootstrap "$system/folio-system.json")
  jq -e '.name == "laptop-migration"' "$bootstrap/target.json" >/dev/null || die 'Wrong system target';
  [[ $(findmnt -n -o UUID --target /) == 4e59b522-0ecc-4bc7-b6d0-edc4531e4a00 ]] || die 'Root UUID differs from inspected target';
  [[ $(findmnt -n -o UUID --target /boot) == 767D-8E97 ]] || die 'EFI UUID differs from inspected target';
  jq -e '.tun.enable == true' /var/lib/sylphy-mihomo/config.json >/dev/null || die 'Unexpected current proxy mode';
}
restore_identity() {
  if getent passwd folio >/dev/null && ! getent passwd sylphy >/dev/null; then
    usermod --login sylphy --home "$old_home" folio
  fi
  if [[ -L "$old_home" && $(readlink "$old_home") == "$new_home" ]]; then rm "$old_home"; fi
  if [[ -d "$new_home" && ! -L "$new_home" && ! -e "$old_home" ]]; then
    mv "$new_home" "$old_home"
  fi
  if [[ -d "$old_home" && ! -e "$new_home" && ! -L "$new_home" ]]; then
    ln -s "$old_home" "$new_home"
  fi
  if [[ -f /var/lib/systemd/linger/folio ]]; then
    mv /var/lib/systemd/linger/folio /var/lib/systemd/linger/sylphy
  fi
}
rename_identity() {
  usermod --login folio --home "$new_home" sylphy
  mv "$old_home" "$new_home"
  ln -s "$new_home" "$old_home"
  for parent in /nix/var/nix/profiles/per-user /nix/var/nix/gcroots/per-user; do
    if [[ -d "$parent/sylphy" && ! -L "$parent/sylphy" ]]; then
      [[ ! -e "$parent/folio" && ! -L "$parent/folio" ]]
      mv "$parent/sylphy" "$parent/folio"
      ln -s "$parent/folio" "$parent/sylphy"
    fi
  done
  # Do not start the user manager until the new system boots: application state
  # must remain quiescent until snapshot/byte/link comparisons have completed.
  # users.users.folio.linger recreates the flag during the next boot activation.
}
restore_context() {
  root_only
  [[ -d "$state/legacy-etc" ]] || die 'Legacy context backup is missing'
  install -d -m 0755 /etc/sylphy
  # /etc/static changes with the system generation. Legacy module clients still
  # need these public descriptors; restore bytes rather than obsolete links.
  cp -a --remove-destination "$state/legacy-etc/." /etc/sylphy/
  if [[ -f /etc/sylphy/users.json ]] && getent passwd folio >/dev/null; then
    jq 'if .username == "sylphy" then .username = "folio" | .homeDirectory = "/home/folio" else . end' \
      /etc/sylphy/users.json >/etc/sylphy/users.json.new
    chmod 644 /etc/sylphy/users.json.new
    mv /etc/sylphy/users.json.new /etc/sylphy/users.json
  fi
}
restore_boot() {
  local previous
  previous=$(cat "$state/old-system")
  nix-env --profile /nix/var/nix/profiles/system --set "$previous"
  NIXOS_INSTALL_BOOTLOADER=1 "$previous/bin/switch-to-configuration" boot
}
stop_login_sessions() {
  local user=${1:-sylphy} candidate session tty
  # Stop the old installation's real login entry points, including tty1
  # autologin. The new Folio system's greeter may not exist on the old host.
  {
    printf '%s\n' display-manager.service greetd.service getty@tty1.service
    for session in $(loginctl show-user "$user" -p Sessions --value); do
      tty=$(loginctl show-session "$session" -p TTY --value)
      if [[ $tty =~ ^tty[0-9]+$ ]]; then
        printf 'getty@%s.service\n' "$tty"
      elif [[ $tty =~ ^(tty(S|AMA)[0-9]+|hvc[0-9]+|xvc[0-9]+)$ ]]; then
        printf 'serial-getty@%s.service\n' "$tty"
      fi
    done
  } | while IFS= read -r candidate; do
    if [[ $(systemctl show "$candidate" -p LoadState --value) == loaded ]] && systemctl is-active --quiet "$candidate"; then
      systemctl show "$candidate" -p Id --value
    fi
  done | LC_ALL=C sort -u >"$state/login-units"
  session_stopped=true
  while IFS= read -r candidate; do
    echo "Stopping legacy login service: $candidate"
    systemctl stop "$candidate"
  done <"$state/login-units"
  loginctl disable-linger "$user"
  loginctl terminate-user "$user" || true
  systemctl stop user@1000.service
  for _attempt in $(seq 1 30); do
    if ! pgrep -u 1000 >/dev/null; then break; fi
    sleep 1
  done
  ! pgrep -u 1000 >/dev/null || die 'User processes remain; refusing to move live application databases'
}
restart_login_services() {
  local unit
  if [[ -f "$state/login-units" ]]; then
    while IFS= read -r unit; do systemctl start "$unit"; done <"$state/login-units"
  fi
}
discard_rollback_alias() {
  if [[ -L "$new_home" ]]; then
    [[ $(readlink "$new_home") == "$old_home" && $(stat -c %u "$new_home") == 0 ]] || die 'Unexpected rollback alias'
    rm "$new_home"
  fi
}
failed() {
  local code=$?
  trap - ERR
  set +e
  echo 'Cutover failed; recovering only the stages that started' >&2
  if "$identity_started"; then restore_identity; fi
  if "$boot_started"; then restore_boot; fi
  printf '%s\n' failed >"$state/phase"
  if "$session_stopped"; then restart_login_services; fi
  exit "$code"
}
queue_worker() {
  echo 'Cutover starts in 20 seconds and closes the desktop. The previous generation and rollback tool are pinned.'
  echo "Journal: journalctl -u folio-account-migration; state: $state"
  echo 'First login: folio, using the existing password. Then run folio-migrate-account finish.'
  systemd-run --unit=folio-account-migration --collect --property=Type=exec --property=UMask=0077 \
    "$(realpath -e "$0")" cutover "$system"
  sleep 2
  if ! systemctl is-active --quiet folio-account-migration.service; then
    journalctl -u folio-account-migration.service -n 20 --no-pager >&2
    die 'Worker exited during initial validation; cutover was not started'
  fi
  echo 'Worker is active; the journal reports when preflight and the countdown begin.'
}

action=${1:-status}
case "$action" in
  launch)
    system=$(realpath -e -- "${2:?System closure is required}")
    preflight
    [[ ! -e "$state/phase" ]] || die 'A migration journal already exists; inspect it before retrying'
    install -d -m 0700 "$state" "$state/roots" "$state/account-backup"
    readlink -f /run/current-system >"$state/old-system"
    printf '%s\n' "$system" >"$state/new-system"
    pin "$(cat "$state/old-system")" old-system
    pin "$system" new-system
    pin "$(dirname "$(dirname "$(realpath -e "$0")")")" migration-tool
    backup_accounts
    cp -aL /etc/sylphy "$state/legacy-etc"
    cp -a /etc/NetworkManager/system-connections "$state/network-connections"
    tar -C /boot -cpf "$state/boot-backup.tar" .
    printf '%s\n' queued >"$state/phase"
    queue_worker
    ;;
  resume)
    system=$(realpath -e -- "${2:?System closure is required}")
    preflight retry
    case $(cat "$state/phase") in
      queued|failed) ;;
      *) die 'Only an unmodified preparation can be resumed' ;;
    esac
    [[ $(cat "$state/old-system") == $(readlink -f /run/current-system) ]] || die 'Running system changed since preparation'
    [[ ! -e "$state/home-snapshot" && ! -e /home/.folio-migration-backups/sylphy-before-folio ]] || die 'A snapshot already exists; inspect the interrupted migration instead'
    case $(systemctl show folio-account-migration.service -p ActiveState --value) in
      inactive|failed) ;;
      *) die 'Migration service is still running' ;;
    esac
    [[ -s "$state/boot-backup.tar" && -d "$state/legacy-etc" && -s "$state/account-backup/shadow" ]] || die 'Preparation backups are incomplete'
    discard_rollback_alias
    pin "$system" new-system
    pin "$(dirname "$(dirname "$(realpath -e "$0")")")" migration-tool
    printf '%s\n' "$system" >"$state/new-system"
    printf '%s\n' queued >"$state/phase"
    systemctl reset-failed folio-account-migration.service || true
    queue_worker
    ;;
  cutover)
    root_only
    system=$(realpath -e -- "${2:?System closure is required}")
    [[ $(cat "$state/phase") == queued ]] || die 'Cutover was not prepared'
    preflight
    trap failed ERR
    echo 'Worker preflight passed; waiting 20 seconds before closing the desktop.'
    sleep 20
    # Existing state is snapshotted only after all UID 1000 writers have stopped.
    stop_login_sessions sylphy
    install -d -m 0700 /home/.folio-migration-backups
    snapshot=/home/.folio-migration-backups/sylphy-before-folio
    [[ ! -e "$snapshot" ]] || die 'Snapshot destination already exists'
    sync
    btrfs subvolume snapshot -r /home "$snapshot"
    printf '%s\n' "$snapshot" >"$state/home-snapshot"
    find "$old_home" -xtype l -printf '%P\n' | LC_ALL=C sort >"$state/broken-before"
    # Pin every extant store root referenced by the legacy home, including old
    # Home Manager generations. The store itself must never be edited.
    find "$old_home" -type l -printf '%l\n' | awk -F/ '$2=="nix" && $3=="store" {print "/nix/store/" $4}' | \
      LC_ALL=C sort -u >"$state/home-store-paths"
    number=0
    while IFS= read -r path; do
      number=$((number + 1))
      pin "$path" "home-$number"
    done <"$state/home-store-paths"
    # Preserve the working provider, selection cache and routing privately.
    # No private bytes enter source, a derivation, command arguments or logs.
    cp -a /var/lib/sylphy-mihomo /var/lib/folio-mihomo
    jq 'walk(if type == "string" then
      gsub("/run/credentials/sylphy-mihomo.service/"; "/run/credentials/folio-mihomo.service/")
      | gsub("/var/lib/sylphy-mihomo/"; "/var/lib/folio-mihomo/") else . end)
      | .tun.device = "folio-mihomo"
      | ."external-controller-unix" = "/run/folio-mihomo/controller.sock"' \
      /var/lib/sylphy-mihomo/config.json >"/var/lib/folio-mihomo/config.json"
    chmod 0600 /var/lib/folio-mihomo/config.json
    # Let StateDirectory assign the new service identity recursively at boot.
    chown root:root /var/lib/folio-mihomo
    printf '%s\n' backed-up >"$state/phase"
    identity_started=true
    rename_identity
    [[ $(getent passwd folio | cut -d: -f3,6) == "1000:$new_home" ]]
    ! getent passwd sylphy >/dev/null
    find "$new_home" -xtype l -printf '%P\n' | LC_ALL=C sort >"$state/broken-after"
    comm -13 "$state/broken-before" "$state/broken-after" >"$state/new-broken-links"
    [[ ! -s "$state/new-broken-links" ]]
    # Verify preserved files against the quiesced snapshot without reading any
    # credential content into output. This move changes paths, never file bytes.
    for entry in .config/zen .local/share/keyrings .codex-account2 .ssh .gnupg; do
      if [[ -e "$snapshot/sylphy/$entry" ]]; then
        diff -qr --no-dereference "$snapshot/sylphy/$entry" "$new_home/$entry" >"$state/preserved-check" 2>&1
      fi
    done
    boot_started=true
    nix-env --profile /nix/var/nix/profiles/system --set "$system"
    NIXOS_INSTALL_BOOTLOADER=1 "$system/bin/switch-to-configuration" boot
    printf '%s\n' ready-to-boot >"$state/phase"
    sync
    trap - ERR
    systemctl reboot
    ;;
  rollback)
    root_only
    [[ -s "$state/old-system" ]] || die 'No previous system journal'
    echo 'Rollback closes the Folio session; files and the current password are retained.'
    systemd-run --unit=folio-account-rollback --property=Type=exec --property=UMask=0077 \
      "$(realpath -e "$0")" rollback-worker
    ;;
  rollback-worker)
    root_only
    sleep 10
    stop_login_sessions folio
    restore_identity
    restore_boot
    printf '%s\n' rolled-back >"$state/phase"
    sync
    systemctl reboot
    ;;
  finish)
    [[ $(id -un) == folio && $(id -u) == 1000 ]] || die 'Finish as the migrated Folio user'
    [[ -t 0 && -t 1 ]] || die 'Use an interactive local terminal'
    echo 'Change the login password interactively. PAM also attempts to update the existing login keyring.'
    echo 'Keep the old keyring password available; never delete the keyring if an application asks to unlock it.'
    /run/wrappers/bin/passwd
    install -d -m 0700 "$HOME/.local/state/folio/migration"
    touch "$HOME/.local/state/folio/migration/password-changed"
    echo 'Password changed. Verify existing Zen logins, SSH/GPG, keyring and Codex accounts before adopting new Home Manager or Flatpak profiles.'
    ;;
  restore-context) restore_context ;;
  status)
    getent passwd sylphy folio || true
    if [[ -r "$state/phase" ]]; then cat "$state/phase"; fi
    echo 'Do not remove the legacy home alias or garbage-collection roots until application state has been verified.'
    ;;
  *) die 'Usage: folio-migrate-account launch SYSTEM | resume SYSTEM | status | finish | rollback' ;;
esac
