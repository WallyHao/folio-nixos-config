#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C
export NIX_CONFIG="${NIX_CONFIG:-}
experimental-features = nix-command flakes"
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
local_dir=$root/modules/manager/configuration/targets/local

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || fail "Missing command: $1. Enter the bootstrap shell described in README.md."; }

usage() {
  cat <<'HELP'
Usage: just init [--config-dir DIRECTORY] [--hostname NAME]

Run as the normal desktop user on the installed x86_64 NixOS machine.
Copies Nix files from /etc/nixos and preserves the installed hardware,
boot loader, state version, accounts and passwords. No disks are formatted.
Existing local configuration is never overwritten.

Options:
  --config-dir DIRECTORY  Installed configuration directory (default: /etc/nixos)
  --hostname NAME         Folio environment/host name (default: current hostname)
  --help                 Show this help

Next: review the generated files, run just build, then just deploy.
Reboot into the new system and run just home as the same user.
HELP
}

initialize() {
  local config_dir=/etc/nixos hostname username uid user_home login_shell timezone locale entry relative stage
  hostname=$(cat /proc/sys/kernel/hostname)
  while (( $# )); do
    case "$1" in
      --help|-h) usage; return ;;
      --config-dir|--hostname)
        (( $# >= 2 )) || fail "Missing value for $1. See just init --help."
        if [[ "$1" == --config-dir ]]; then config_dir=$2; else hostname=$2; fi
        shift 2 ;;
      *) fail "Unknown option: $1. See just init --help." ;;
    esac
  done
  [[ $(id -u) != 0 ]] || fail 'Run just init as the normal desktop user, without sudo.'
  [[ $(uname -m) == x86_64 && -f /etc/NIXOS ]] || fail 'This workflow requires an installed x86_64 NixOS system.'
  need jq
  need getent
  [[ ! -e "$local_dir" && ! -e "$root/folio-target.json" ]] || fail 'Local configuration or a target manifest already exists. Edit it in place; init will not overwrite it.'
  [[ "$hostname" =~ ^[a-z][a-z0-9-]{0,63}$ ]] || fail 'Host names must start with a lowercase letter and contain at most 64 lowercase letters, digits or hyphens. Use --hostname NAME.'
  username=$(id -un)
  [[ "$username" =~ ^[a-z][a-z0-9-]{0,63}$ ]] || fail 'Folio account names must start with a lowercase letter and contain only lowercase letters, digits or hyphens.'
  uid=$(id -u)
  entry=$(getent passwd "$username") || fail 'The current account is not present in the account database.'
  IFS=: read -r _ _ _ _ _ user_home login_shell <<<"$entry"
  [[ "$user_home" == "$HOME" ]] || fail 'HOME differs from the account database. Run from a regular login session.'
  case "$login_shell" in
    */zsh) login_shell=zsh ;;
    */bash) login_shell=bash ;;
    *) fail 'The deployment account must currently use Bash or Zsh.' ;;
  esac
  timezone=$(readlink -f /etc/localtime)
  timezone=${timezone#*/zoneinfo/}
  [[ "$timezone" =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ ]] || fail 'Cannot determine the installed timezone from /etc/localtime.'
  locale=$(sed -n 's/^LANG=//p' /etc/locale.conf | tr -d "\"'")
  case "$locale" in
    en_US.UTF-8|en_GB.UTF-8|zh_CN.UTF-8) ;;
    *) fail 'Folio currently supports en_US.UTF-8, en_GB.UTF-8 and zh_CN.UTF-8. Set a supported system locale before initializing.' ;;
  esac
  config_dir=$(realpath -e -- "$config_dir") || fail 'Configuration directory does not exist.'
  [[ -r "$config_dir/configuration.nix" && -r "$config_dir/hardware-configuration.nix" ]] || fail 'The configuration directory must contain readable configuration.nix and hardware-configuration.nix files.'

  mkdir -p -- "$(dirname -- "$local_dir")"
  stage=$(mktemp -d "${local_dir}.init.XXXXXX")
  trap 'rm -rf -- "$stage"' EXIT
  mkdir "$stage/installation"
  # Snapshot Nix modules only; private keys and other non-Nix files stay outside.
  find -L "$config_dir" -type f -name '*.nix' -print0 >"$stage/files"
  while IFS= read -r -d '' entry; do
    relative=${entry#"$config_dir/"}
    mkdir -p -- "$stage/installation/$(dirname -- "$relative")"
    install -m 0644 -- "$entry" "$stage/installation/$relative"
  done <"$stage/files"
  rm "$stage/files"
  jq -n --arg hostname "$hostname" --arg username "$username" --argjson uid "$uid" \
    --arg home "$user_home" --arg shell "$login_shell" --arg timezone "$timezone" --arg locale "$locale" \
    '{hostname:$hostname,username:$username,uid:$uid,home:$home,shell:$shell,timezone:$timezone,locale:$locale}' >"$stage/host.json"
  cat >"$stage/host.nix" <<'NIX'
# Additional machine settings. The installed hardware and boot loader are
# imported from installation/configuration.nix. Review that snapshot as well.
{ ... }:
{
  # Add laptop power management, GPU drivers or other hardware options here.
  # Never copy another machine's disk UUIDs or NVIDIA PRIME bus IDs.
}
NIX
  mv -- "$stage" "$local_dir"
  trap - EXIT
  printf '{"name":"local"}\n' >"$root/folio-target.json"
  printf '%s\n' \
    "Initialized local deployment for $username on $hostname." \
    "Review: $local_dir/host.json, host.nix and installation/*.nix" \
    'Keep system.stateVersion, disk definitions and boot-loader settings from this installation.' \
    'Move any embedded secrets to runtime files before building.' \
    'Only Nix files were copied. Supply any other imported files explicitly.' \
    'Isaac and the author-specific hardware/proxy settings are excluded.' \
    'Next: just build, just deploy, reboot, then just home.'
}

require_local() {
  need jq
  need nix
  [[ -r "$local_dir/host.json" && -r "$root/folio-target.json" ]] || fail 'Run just init on this machine first.'
  jq -e '.name == "local"' "$root/folio-target.json" >/dev/null || fail 'This workflow only deploys the local target.'
  [[ $(id -u) == "$(jq -er .uid "$local_dir/host.json")" && $(id -un) == "$(jq -er .username "$local_dir/host.json")" && "$HOME" == "$(jq -er .home "$local_dir/host.json")" ]] || fail 'Run as the account that initialized this local target, without sudo.'
}

action=${1:-help}
if (( $# )); then shift; fi
if [[ "$action" == init ]]; then initialize "$@"; exit; fi
if [[ "$action" == help || "$action" == --help ]]; then usage; exit; fi
(( $# == 0 )) || fail "Unexpected arguments for $action."
case "$action" in build|boot|switch|home|plan) ;; *) fail "Unknown action: $action." ;; esac
require_local
cd -- "$root"
case "$action" in
  build)
    printf '%s\n' 'Building the local system and user environment without activation...'
    nix build --no-link --no-update-lock-file \
      "path:$root#nixosConfigurations.local.config.system.build.toplevel" \
      "path:$root#homeConfigurations.folio.activationPackage"
    ;;
  boot|switch)
    need sudo
    need nixos-rebuild
    printf 'Installing the local system (%s)...\n' "$action"
    sudo env NIX_CONFIG="$NIX_CONFIG" nixos-rebuild "$action" --flake "path:$root#local" --no-update-lock-file
    if [[ "$action" == boot ]]; then
      printf '%s\n' 'System installed for the next boot. Reboot, log in as your normal user, re-enter the bootstrap shell if needed, and run just home.'
    else
      printf '%s\n' 'System activated. Log out and back in to refresh group membership, then run just home.'
    fi
    ;;
  home)
    need folio
    [[ -r /run/folio/public/system-descriptor.json ]] || fail 'Boot into the deployed system before running just home.'
    jq -e --slurpfile host "$local_dir/host.json" \
      '.environment == $host[0].hostname and any(.users[]; .name == $host[0].username and .uid == $host[0].uid and .home == $host[0].home)' \
      /run/folio/public/system-descriptor.json >/dev/null || fail 'The running system descriptor does not match this local target.'
    printf '%s\n' 'Planning the user deployment...'
    plan=$(folio --json --user plan --source "$root")
    plan_id=$(jq -er '.data.planId' <<<"$plan")
    printf 'Building and applying user plan %s...\n' "$plan_id"
    folio --user build "$plan_id"
    folio --user apply "$plan_id"
    printf '%s\n' 'User environment deployed. Log out and back in to start the configured desktop session.'
    ;;
  plan)
    need folio
    exec folio plan --source "$root"
    ;;
esac
