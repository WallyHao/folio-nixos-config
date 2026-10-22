if ! lock_configuration; then reply conflict 'Configuration is busy'; exit 0; fi
recover_configuration
mode=$(jq -r '."folio-deployment:plan".mode // "create"' "$work/request.json")
if [[ "$mode" == confirm || "$mode" == cancel ]]; then
  draft_id=$(jq -er '."folio-deployment:plan"."draft-id"' "$work/request.json")
  [[ "$draft_id" =~ ^[a-f0-9]{64}$ ]] || { reply invalid 'Invalid draft ID'; exit 0; }
  plan=$state/deployments/drafts/$draft_id.json
  [[ -f "$plan" ]] || { reply invalid 'Unknown planning draft'; exit 0; }
  [[ $(digest_file "$plan") == "$draft_id" ]] || { reply conflict 'Draft digest mismatch'; exit 0; }
  if [[ "$mode" == cancel ]]; then
    rm -f "$plan" "$state/deployments/roots/draft-$draft_id"
    reply success; exit 0
  fi
  if ! plan_current review; then reply conflict 'Reviewed configuration or profile changed; run folio plan again'; exit 0; fi
  jq --slurpfile request "$work/request.json" \
    '.comment=($request[0]."folio-deployment:plan".comment // "") | .retained=true' "$plan" >"$work/plan.json"
  plan_id=$(digest_file "$work/plan.json")
  snapshot=$(jq -er .source "$plan")
  mkdir -p "$state/deployments/plans"
  nix-store --realise "$snapshot" --add-root "$state/deployments/roots/plan-$plan_id" --indirect >/dev/null
  folio-atomic-write "$state/deployments/plans/$plan_id.json" <"$work/plan.json"
  rm -f "$plan" "$state/deployments/roots/draft-$draft_id"
  jq -cn --arg id "$plan_id" --slurpfile plan "$work/plan.json" \
    '{status:"success","plan-id":$id,data:{"folio-deployment:result":$plan[0]}}'
  exit 0
fi
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
    --exclude='*.raw' --exclude='*.qcow2' --exclude=__pycache__ --exclude='*.pyc' \
    -cf "$work/source.tar" "${entries[@]}"; then
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
# Store-backed and read-only source trees retain directory modes in the archive.
# Only the private copy needs write access for cleanup and the frozen input.
chmod -R u+w "$work/source"
# Hardware selection belongs to the installed immutable bootstrap. Retain it
# even when a user supplies an ordinary checkout without a target manifest.
if [[ -f "$FOLIO_BOOTSTRAP/target.json" ]]; then
  if [[ -f "$source_path/folio-target.json" ]] && ! jq -e --slurpfile installed "$FOLIO_BOOTSTRAP/target.json" \
      '. == $installed[0]' "$source_path/folio-target.json" >/dev/null; then
    reply invalid 'Source hardware target differs from the installed target'; exit 0
  fi
  cp "$FOLIO_BOOTSTRAP/target.json" "$work/source/folio-target.json"
fi
jq -cS . "$descriptor_path" >"$work/before-descriptor.json"
input_descriptor=$descriptor_path
if [[ $(jq -r '."folio-deployment:plan"."descriptor-json" // ""' "$work/request.json") != '' ]]; then
  [[ "$scope" == user ]] || { reply invalid 'Only user plans accept a target system descriptor'; exit 0; }
  jq -er '."folio-deployment:plan"."descriptor-json"' "$work/request.json" | jq -ceS . >"$work/target-descriptor.json"
  input_descriptor=$work/target-descriptor.json
fi
folio-prepare-input "$work/configuration.json" "$FOLIO_BOOTSTRAP" "$input_descriptor" >"$work/source/folio-input.json"
if [[ "$scope" == user ]]; then
  descriptor_home=$(jq -er --arg account "$account" '.systemDescriptor.users[] | select(.name==$account) | .home' \
    "$work/source/folio-input.json")
  if [[ "$descriptor_home" != "$HOME" ]]; then reply invalid 'HOME differs from the provisioned system descriptor'; exit 0; fi
fi
snapshot=$(nix store add-path --name folio-input "$work/source")
input_hash=$(nix hash path --type sha256 "$snapshot")
input_digest=$(nix hash convert --hash-algo sha256 --to base16 "$input_hash")
# A real evaluation checks catalogue/scopes, prerequisites and adapter constraints.
if nix_as_builder eval --no-update-lock-file --json "path:$snapshot#lib.folio.identities" >"$work/source-identities.json"; then
  if ! jq -e --arg scope "$scope" --slurpfile installed "$FOLIO_BOOTSTRAP/identities.json" \
      '.models[$scope] == $installed[0].models[$scope] and .tools == $installed[0].tools' \
      "$work/source-identities.json" >/dev/null; then
    reply invalid "Source models or tools differ from the installed $scope repository; run the paired folio-manager-maintain $scope upgrade before planning (README: Model upgrades)"
    exit 0
  fi
fi
if ! nix_as_builder eval --no-update-lock-file --json "path:$snapshot#$target" \
    --apply 'd: { derivation=d.drvPath; artifact=d.outPath; }' >"$work/artifact.json"; then
  reply invalid 'Frozen configuration failed evaluation'; exit 0
fi
before_profile=$(selected_profile)
prior=null
if [[ -f "$state/deployments/current.json" ]]; then prior=$(jq -c . "$state/deployments/current.json"); fi
prior_source=$(jq -r '.source // ""' <<<"$prior")
target_artifact=$(jq -er '.artifact | select(test("^/nix/store/[a-z0-9]{32}-[^/]+$"))' "$work/artifact.json")
python3 @review@ "$snapshot" "$prior_source" "$target_artifact" "$before_profile" >"$work/review.json"
if [[ "$prior" == null ]]; then
  jq '.changed=true | .firstDeployment=true' "$work/review.json" >"$work/review-next.json"
  mv "$work/review-next.json" "$work/review.json"
elif [[ -n "$before_profile" ]] && ! applied_artifact_matches "$before_profile"; then
  jq '.changed=true | .drift=true' "$work/review.json" >"$work/review-next.json"
  mv "$work/review-next.json" "$work/review.json"
fi
if [[ "$scope" == system ]]; then
  target_descriptor=$(nix_as_builder build --no-update-lock-file --no-link --print-out-paths \
    "path:$snapshot#nixosConfigurations.portable.config.system.build.folioDescriptor")
  jq --slurpfile descriptor "$target_descriptor" '.targetDescriptor=$descriptor[0]' "$work/review.json" >"$work/review-next.json"
  mv "$work/review-next.json" "$work/review.json"
fi
timeout_seconds=$(jq -er '."folio-deployment:plan"."timeout-seconds" // 1800' "$work/request.json")
jq -cnS --arg scope "$scope" --arg source "$snapshot" --arg inputDigest "$input_digest" --arg owner "$account" \
  --arg beforeProfile "$before_profile" --argjson prior "$prior" --argjson timeoutSeconds "$timeout_seconds" \
  --slurpfile input "$snapshot/folio-input.json" --slurpfile review "$work/review.json" \
  --slurpfile request "$work/request.json" --arg now "$(date -u +%FT%TZ)" \
  --arg beforeDescriptorDigest "$(digest_file "$work/before-descriptor.json")" \
  '{format:1,scope:$scope,environment:$input[0].configuration."folio-environment:environment".name,
    source:$source,inputDigest:$inputDigest,owner:$owner,configurationDigest:$input[0].configurationDigest,
    descriptorDigest:$input[0].descriptorDigest,beforeDescriptorDigest:$beforeDescriptorDigest,beforeProfile:$beforeProfile,
    priorDeployment:$prior,timeoutSeconds:$timeoutSeconds,review:$review[0],
    comment:($request[0]."folio-deployment:plan".comment // ""),createdAt:$now}' >"$work/plan.json"
if [[ "$mode" == preview ]]; then
  jq --arg token "$(cat /proc/sys/kernel/random/uuid)" '.reviewToken=$token' "$work/plan.json" >"$work/plan-next.json"
  mv "$work/plan-next.json" "$work/plan.json"
fi
plan_id=$(digest_file "$work/plan.json")
mkdir -p "$state/deployments/plans" "$state/deployments/roots"
if [[ "$mode" == preview ]]; then
  mkdir -p "$state/deployments/drafts"
  nix-store --realise "$snapshot" --add-root "$state/deployments/roots/draft-$plan_id" --indirect >/dev/null
  folio-atomic-write "$state/deployments/drafts/$plan_id.json" <"$work/plan.json"
  jq -cn --arg id "$plan_id" --slurpfile plan "$work/plan.json" \
    '{status:"success","plan-id":$id,data:{"folio-deployment:result":$plan[0]}}'
  exit 0
fi
nix-store --realise "$snapshot" --add-root "$state/deployments/roots/plan-$plan_id" --indirect >/dev/null
if [[ ! -f "$state/deployments/plans/$plan_id.json" ]]; then
  folio-atomic-write "$state/deployments/plans/$plan_id.json" <"$work/plan.json"
fi
jq -cn --arg id "$plan_id" --slurpfile plan "$work/plan.json" \
  '{status:"success","plan-id":$id,data:{"folio-deployment:result":$plan[0]}}'
