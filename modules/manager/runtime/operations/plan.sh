if ! lock_configuration; then reply conflict 'Configuration is busy'; exit 0; fi
recover_configuration
current_configuration >"$work/configuration.json"
account=root
target=nixosConfigurations.portable.config.system.build.toplevel
if [[ "$scope" == user ]]; then
  account=$(jq -er '."folio-environment:environment".account' "$work/configuration.json")
  if [[ "$account" != "$(id -un)" ]]; then reply invalid 'User plans must run as the provisioned account'; exit 0; fi
  target=homeConfigurations.folio.activationPackage
fi
source_path=$(jq -er '."folio-deployment:plan".source' "$work/request.json")
if ! source_path=$(realpath -e -- "$source_path"); then reply invalid 'Source path is unavailable'; exit 0; fi
if [[ ! -f "$source_path/flake.nix" || ! -f "$source_path/flake.lock" || ! -d "$source_path/modules" ]]; then
  reply invalid 'Source must contain the root Flake/lock and modules'; exit 0
fi
mkdir "$work/source"
entries=(flake.nix flake.lock modules)
[[ ! -d "$source_path/assets" ]] || entries+=(assets)
# Capture bytes before validation; never evaluate the editable checkout. Fixed
# root entries exclude environment metadata, runtime state and output trees.
if ! tar -C "$source_path" --exclude=.git --exclude=.aws --exclude=.codex --exclude=.agents \
    --exclude=.ssh --exclude='.env*' --exclude=result --exclude='result-*' --exclude='*.log' \
    --exclude='*.raw' --exclude='*.qcow2' -cf "$work/source.tar" "${entries[@]}"; then
  reply conflict 'Source changed or could not be captured'; exit 0
fi
tar --no-same-owner -xf "$work/source.tar" -C "$work/source"
while IFS= read -r -d '' link; do
  link_target=$(realpath -e -- "$link") || { reply invalid 'Source contains a dangling symlink'; exit 0; }
  case "$link_target" in
    "$work/source/"*) ;;
    *) reply invalid 'Source contains an escaping symlink'; exit 0 ;;
  esac
done < <(find "$work/source" -type l -print0)
folio-prepare-input "$work/configuration.json" "$FOLIO_BOOTSTRAP" "$descriptor_path" >"$work/source/folio-input.json"
if [[ "$scope" == user ]]; then
  descriptor_home=$(jq -er --arg account "$account" '.systemDescriptor.users[] | select(.name==$account) | .home' \
    "$work/source/folio-input.json")
  if [[ "$descriptor_home" != "$HOME" ]]; then reply invalid 'HOME differs from the provisioned system descriptor'; exit 0; fi
fi
snapshot=$(nix store add-path --name folio-input "$work/source")
input_hash=$(nix hash path --type sha256 "$snapshot")
input_digest=$(nix hash convert --hash-algo sha256 --to base16 "$input_hash")
# A real evaluation checks catalogue/scopes, prerequisites and adapter constraints.
if ! nix_as_builder eval --no-update-lock-file --raw "path:$snapshot#$target.drvPath" >"$work/artifact.drv"; then
  reply invalid 'Frozen configuration failed evaluation'; exit 0
fi
before_profile=$(selected_profile)
prior=null
if [[ -f "$state/deployments/current.json" ]]; then prior=$(jq -c . "$state/deployments/current.json"); fi
timeout_seconds=$(jq -er '."folio-deployment:plan"."timeout-seconds" // 1800' "$work/request.json")
jq -cnS --arg scope "$scope" --arg source "$snapshot" --arg inputDigest "$input_digest" --arg owner "$account" \
  --arg beforeProfile "$before_profile" --argjson prior "$prior" --argjson timeoutSeconds "$timeout_seconds" \
  --slurpfile input "$snapshot/folio-input.json" \
  '{format:1,scope:$scope,environment:$input[0].configuration."folio-environment:environment".name,
    source:$source,inputDigest:$inputDigest,owner:$owner,configurationDigest:$input[0].configurationDigest,
    descriptorDigest:$input[0].descriptorDigest,beforeProfile:$beforeProfile,
    priorDeployment:$prior,timeoutSeconds:$timeoutSeconds}' >"$work/plan.json"
plan_id=$(digest_file "$work/plan.json")
mkdir -p "$state/deployments/plans" "$state/deployments/roots"
nix-store --realise "$snapshot" --add-root "$state/deployments/roots/plan-$plan_id" --indirect >/dev/null
if [[ ! -f "$state/deployments/plans/$plan_id.json" ]]; then
  folio-atomic-write "$state/deployments/plans/$plan_id.json" <"$work/plan.json"
fi
jq -cn --arg id "$plan_id" --slurpfile plan "$work/plan.json" \
  '{status:"success","plan-id":$id,data:{"folio-deployment:result":$plan[0]}}'
