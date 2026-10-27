set shell := ["bash", "-eu", "-o", "pipefail", "-c"]
set positional-arguments

# Show available deployment commands.
default:
    @just --list

# Initialize this machine from /etc/nixos (see: just init --help).
init *args:
    @bash scripts/deploy.sh init "$@"

# Build the local system and user environment without activating them.
build:
    @bash scripts/deploy.sh build

# Install the local system for the next boot; reboot, then run just home.
deploy:
    @bash scripts/deploy.sh boot

# Activate the local system immediately (may end the current desktop session).
switch:
    @bash scripts/deploy.sh switch

# Build and apply the user environment through the Folio deployment manager.
home:
    @bash scripts/deploy.sh home

# Review subsequent system and user changes using the installed Folio manager.
plan:
    @bash scripts/deploy.sh plan
