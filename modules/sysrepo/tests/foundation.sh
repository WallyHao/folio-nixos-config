set -euo pipefail
bootstrap=$1
models=$bootstrap/models/user
folio-normalize "$models" "$bootstrap/user.json" > normalized.json
jq '."folio-environment:environment".modules |= reverse' "$bootstrap/user.json" > reordered.json
folio-normalize "$models" reordered.json > normalized-reordered.json
cmp normalized.json normalized-reordered.json
folio-prepare-input "$bootstrap/user.json" "$bootstrap" > input.json
folio-prepare-input reordered.json "$bootstrap" > reordered-input.json
cmp input.json reordered-input.json
jq -e '.format == 1 and .scope == "user" and (.models | length == 3)
  and (.configurationDigest | length == 64) and (.descriptorDigest | length == 64)
  and .tools.libyang == "3.13.6" and .tools.sysrepo == "3.7.11"' input.json
jq '."folio-environment:environment".preferences."font-size" = 0' "$bootstrap/user.json" > invalid.json
if folio-normalize "$models" invalid.json; then
  echo 'Invalid modeled font size was accepted' >&2; exit 1
fi

folio-repository user init "$models" "$bootstrap/user.json"
folio-repository user cfg --export --module folio-environment --format json --defaults report-all > initial.json
folio-normalize "$models" initial.json > actual.json
cmp normalized.json actual.json

# Maintenance edits are deliberately outside the future supported commit API.
jq '."folio-environment:environment".preferences."font-size" = 18' initial.json > changed.json
folio-repository user cfg --import=changed.json --module folio-environment --format json
folio-repository user cfg --copy-from running --datastore startup --module folio-environment
folio-repository user init "$models" "$bootstrap/user.json"
folio-repository user cfg --export --module folio-environment --format json --defaults report-all |
  jq -e '."folio-environment:environment".preferences."font-size" == 18'

# Recover the boundary after atomic schema/data installation but before marker.
rm "$XDG_STATE_HOME/folio/initialized"
folio-repository user init "$models" "$bootstrap/user.json"
folio-repository user cfg --export --datastore startup --module folio-environment --format json --defaults report-all |
  jq -e '."folio-environment:environment".preferences."font-size" == 18'

# A second account-shaped instance uses distinct persistent/runtime directories.
first_state=$XDG_STATE_HOME
first_runtime=$XDG_RUNTIME_DIR
export XDG_STATE_HOME=$TMPDIR/second-state XDG_RUNTIME_DIR=$TMPDIR/second-run
mkdir -p "$XDG_RUNTIME_DIR"
folio-repository user init "$models" "$bootstrap/user.json"
folio-repository user cfg --export --module folio-environment --format json --defaults report-all |
  jq -e '."folio-environment:environment".preferences."font-size" == 16'
export XDG_STATE_HOME=$first_state XDG_RUNTIME_DIR=$first_runtime
folio-repository user cfg --export --module folio-environment --format json --defaults report-all |
  jq -e '."folio-environment:environment".preferences."font-size" == 18'

# Validate the system closure separately without requiring host root state.
folio-normalize "$bootstrap/models/system" "$bootstrap/system.json" > system-normalized.json
echo 'Real repositories: isolated state, schema/default validation and restart preservation passed'
