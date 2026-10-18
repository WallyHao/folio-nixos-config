if (( $# != 2 )); then
  echo 'Usage: folio-prepare-input CONFIGURATION.json BOOTSTRAP_DIRECTORY' >&2
  exit 2
fi
configuration=$(realpath -e -- "$1")
bootstrap=$(realpath -e -- "$2")
scope=$(jq -er '."folio-environment:environment".scope' "$configuration")
case "$scope" in
  system|user) ;;
  *) echo 'Configuration must specify system or user scope' >&2; exit 2 ;;
esac
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
folio-normalize "$bootstrap/models/$scope" "$configuration" >"$work/configuration.json"
jq -cS . "$bootstrap/system-descriptor.json" >"$work/descriptor.json"
configuration_digest=$(sha256sum <"$work/configuration.json")
descriptor_digest=$(sha256sum <"$work/descriptor.json")
jq -cnS --arg scope "$scope" \
  --arg configurationDigest "${configuration_digest%% *}" \
  --arg descriptorDigest "${descriptor_digest%% *}" \
  --slurpfile configuration "$work/configuration.json" \
  --slurpfile descriptor "$work/descriptor.json" \
  --slurpfile identities "$bootstrap/identities.json" \
  '{ format: 1, scope: $scope, configuration: $configuration[0],
     configurationDigest: $configurationDigest, systemDescriptor: $descriptor[0],
     descriptorDigest: $descriptorDigest, models: $identities[0].models[$scope],
     tools: $identities[0].tools,
     resolvedPreferences: (
       ($configuration[0]."folio-environment:environment".preferences // {}) as $preferences |
       ($descriptor[0].preferences + $preferences) as $values |
       {values:$values, origins:($values | with_entries(.key as $key |
         .value=(if $scope=="system" then "system-configuration"
           elif $preferences|has($key) then "user-configuration" else "system-default" end)))}) }'
