#!/usr/bin/env bash
set -euo pipefail
umask 077

die() { printf 'Keyring migration stopped: %s\n' "$*" >&2; exit 1; }

[[ $(id -un) == folio && $(id -u) == 1000 ]] || die 'Run as folio, without sudo.'
[[ -t 0 && -t 1 ]] || die 'Run in an interactive desktop terminal.'
[[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || die 'No desktop session bus is available.'
if getent passwd sylphy >/dev/null; then
  die 'The legacy account still exists; inspect account migration before continuing.'
fi
command -v folio-keyring-password >/dev/null || die 'Run the packaged folio-migrate-keyring command.'
folio-keyring-password --check

keyrings="$HOME/.local/share/keyrings"
[[ -d "$keyrings" && -f "$keyrings/login.keyring" ]] || die 'The existing login keyring was not found.'
backup_root="$HOME/.local/state/folio/migration/keyring-backups"
mkdir -p -- "$backup_root"
chmod 700 -- "$backup_root"
backup=$(mktemp -d "$backup_root/before-password-change.XXXXXXXX")
cp -a -- "$keyrings/." "$backup/"
chmod 700 -- "$backup"
printf 'Existing encrypted keyring backed up to: %s\n' "$backup"
printf '%s\n' \
  'The sylphy account is absent. Compatibility links and existing credentials will be kept.' \
  'Enter the previous keyring password, then your current folio login password twice.' \
  'Input is hidden. No password is passed in command arguments or written to disk.'

folio-keyring-password
printf '%s\n' \
  'Log out and log in again, then run gh auth status to check credential access.' \
  'Keep the backup and /home/sylphy compatibility link until applications are verified.'
