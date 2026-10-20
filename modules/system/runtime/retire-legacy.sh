set -Eeuo pipefail
umask 077
backup=
journal_ready=false
die() {
  echo "Legacy retirement stopped: $*" >&2
  if "$journal_ready"; then failed 1; fi
  exit 1
}
[[ $(id -u) == 0 ]] || die 'Run with sudo; credentials and system state require root'
exec 9>/run/lock/folio-retire-legacy.lock
flock -n 9 || die 'Another retirement is running'

new_provider=/var/lib/folio-mihomo-private/provider.yaml
step="preflight"
failed() {
  local code=$1
  printf '%s\n' interrupted >"$backup/phase"
  printf '%s\n' "$step" >"$backup/failed-step"
  echo "Retirement stopped at $step (exit $code). Inspect $backup; retain remaining legacy prerequisites." >&2
}
finalize() {
  step="verify-active-deployment"
  jq -e '.status=="success"' "$backup/apply.json" >/dev/null
  folio --json --system status >"$backup/status-after.json"
  jq -e '.status=="success" and .data.health=="healthy"' "$backup/status-after.json" >/dev/null
  plan=$(jq -er 'select(.status=="success") | .data.planId' "$backup/plan.json")
  jq -e --arg plan "$plan" --arg artifact "$(readlink -f /run/current-system)" \
    '.data.applied.planId==$plan and .data.applied.artifact==$artifact' "$backup/status-after.json" >/dev/null
  folio --system config export "$backup/configuration-current.json" >/dev/null
  jq -e --slurpfile expected "$backup/configuration-after.json" '.==$expected[0]' \
    "$backup/configuration-current.json" >/dev/null
  systemctl is-active --quiet folio-mihomo.service || die 'Proxy did not recover; retain legacy prerequisites'
  step="verify-loaded-credentials"
  busctl --json=short get-property org.freedesktop.systemd1 \
    /org/freedesktop/systemd1/unit/folio_2dmihomo_2eservice \
    org.freedesktop.systemd1.Service LoadCredential >"$backup/loaded-credentials.json"
  jq -e --arg path "$new_provider" \
    '.type=="a(ss)" and any(.data[]; .==["provider.yaml",$path])' "$backup/loaded-credentials.json" >/dev/null
  step="update-transient-hostname"
  [[ $(cat /etc/hostname) == folio ]] || die 'The active static hostname is not Folio'
  if [[ $(hostname) != folio ]]; then
    hostnamectl --transient set-hostname folio
  fi
  [[ $(hostname) == folio ]] || die 'Transient hostname update failed'
  [[ ! -e /run/current-system/sw/bin/folio-migrate-account ]] || die 'The system still installs the account migration adapter'
  printf '%s\n' applied >"$backup/phase"

  # Archive obsolete files only after the new configuration is healthy. Preserve
  # archives and migration journals for explicit recovery of older generations.
  step="archive-legacy-files"
  for path in /etc/sylphy /var/lib/sylphy-mihomo /var/lib/sylphy-mihomo-private; do
    [[ ! -e $path && ! -L $path ]] || mv -- "$path" "$backup/${path##*/}"
  done
  if [[ -L /run/sylphy-mihomo && $(readlink /run/sylphy-mihomo) == /run/folio-mihomo ]]; then
    unlink /run/sylphy-mihomo
  fi
  printf '%s\n' complete >"$backup/phase"
  echo "Legacy system files archived at $backup"
  echo 'Before rolling back to a legacy generation, restore its prerequisite files with restore-files BACKUP.'
}

case "${1:-}" in
  resume)
    backup=$(realpath -e -- "${2:?Backup directory required}")
    [[ $backup == /var/lib/folio/backups/legacy-* && -f "$backup/status-before.json" ]] || die 'Unexpected backup'
    journal_ready=true
    trap 'failed "$?"' ERR
    finalize
    exit 0
    ;;
  restore-files)
    backup=$(realpath -e -- "${2:?Backup directory required}")
    [[ $backup == /var/lib/folio/backups/legacy-* && -f "$backup/status-before.json" ]] || die 'Unexpected backup'
    # Restore prerequisites before rolling back to a retained old generation.
    # Keep the archive and the currently active Folio credentials intact.
    for path in /etc/sylphy /var/lib/sylphy-mihomo /var/lib/sylphy-mihomo-private; do
      name=${path##*/}
      [[ ! -e "$backup/$name" ]] || {
        [[ ! -e $path && ! -L $path ]] || die "Restore destination already exists: $path"
        cp -a -- "$backup/$name" "$path"
      }
    done
    echo 'Legacy prerequisite files restored. Use the recorded old revision for an explicit system rollback.'
    exit 0
    ;;
  apply) ;;
  *) die 'Usage: folio-retire-legacy apply STORE_SOURCE | resume BACKUP | restore-files BACKUP' ;;
esac

source=$(realpath -e -- "${2:?Immutable source required}")
[[ $source == /nix/store/* && -f "$source/flake.nix" ]] || die 'An immutable Nix store source is required'
jq -e '.name=="folio"' "$source/folio-target.json" >/dev/null
[[ $(getent passwd folio | cut -d: -f3,6) == 1000:/home/folio ]] || die 'Unexpected local account'
! getent passwd sylphy >/dev/null || die 'Finish account migration first'
[[ ! -e /home/sylphy && ! -L /home/sylphy ]] || die 'Finish legacy home retirement first'
systemctl is-active --quiet folio-manager.service folio-mihomo.service || die 'System consumers must be healthy'
backup=$(mktemp -d /var/lib/folio/backups/legacy-XXXXXXXX)
chmod 0700 "$backup"
printf '%s\n' preparing >"$backup/phase"
printf '%s\n' "$source" >"$backup/source"
readlink -f /run/current-system >"$backup/old-system"
folio --json --system status >"$backup/status-before.json"
jq -e '.status=="success" and .data.health=="healthy"' "$backup/status-before.json" >/dev/null
folio --system config export "$backup/configuration-before.json" >/dev/null
journal_ready=true
trap 'failed "$?"' ERR

# Copy credentials before changing a service reference; never print private bytes.
old_provider=/var/lib/sylphy-mihomo-private/provider.yaml
step="prepare-credentials"
[[ -f $old_provider && ! -L $old_provider ]] || die 'Expected legacy provider is unavailable'
[[ -d /var/lib/sylphy-mihomo-private && ! -L /var/lib/sylphy-mihomo-private ]] || die 'Unexpected credential directory'
[[ ! -L /var/lib/folio-mihomo-private ]] || die 'Credential destination must not be a symlink'
install -d -m 0700 -o root -g root /var/lib/folio-mihomo-private
if [[ -e $new_provider || -L $new_provider ]]; then
  if [[ ! -f $new_provider || -L $new_provider ]] || ! cmp -s "$old_provider" "$new_provider"; then
    die 'Existing Folio credential differs'
  fi
else
  install -m 0600 -o root -g root "$old_provider" "$new_provider"
fi
chown root:root "$new_provider"
chmod 0600 "$new_provider"
jq -e 'any(."folio-environment:environment".modules[];
  .name=="network" and (."folio-network:network".proxy."provider-file" |
    .=="/var/lib/sylphy-mihomo-private/provider.yaml" or .=="/var/lib/folio-mihomo-private/provider.yaml"))' \
  "$backup/configuration-before.json" >/dev/null
jq '(."folio-environment:environment".modules[] | select(.name=="network") |
  ."folio-network:network".proxy."provider-file")="/var/lib/folio-mihomo-private/provider.yaml"' \
  "$backup/configuration-before.json" >"$backup/configuration-after.json"

# Retain the working private rule set, node selection cache and service state.
# The existing policy already points to the Folio runtime credential endpoint.
[[ -f /var/lib/folio-mihomo/config.json && ! -L /var/lib/folio-mihomo/config.json ]] || die 'Private proxy policy is unavailable'
if grep -qE '/(var/lib|run)/(sylphy-mihomo|credentials/sylphy-mihomo)' /var/lib/folio-mihomo/config.json; then
  die 'Private proxy policy still contains legacy paths; inspect it locally before retirement'
fi
cp -a /var/lib/folio-mihomo/config.json "$backup/proxy-policy.json"
step="save-configuration"
folio --json --system config import "$backup/configuration-after.json" >"$backup/import.json"
jq -e '.status=="success"' "$backup/import.json" >/dev/null
printf '%s\n' configured >"$backup/phase"
step="plan-system"
folio --json --system plan --source "$source" >"$backup/plan.json"
plan=$(jq -er 'select(.status=="success") | .data.planId' "$backup/plan.json")
step="build-system"
folio --json --system build "$plan" >"$backup/build.json"
jq -e '.status=="success"' "$backup/build.json" >/dev/null
printf '%s\n' built >"$backup/phase"
step="apply-system"
folio --json --system apply "$plan" >"$backup/apply.json"
jq -e '.status=="success"' "$backup/apply.json" >/dev/null
finalize
