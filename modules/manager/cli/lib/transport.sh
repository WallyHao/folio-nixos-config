load_configuration() {
  if ! folio-repository "$FOLIO_SCOPE" cfg --export --module folio-environment --format json --defaults report-all \
      >"$work/configuration.json" 2>"$work/error"; then
    cat "$work/error" >&2
    finish unavailable null 'Desired configuration is unavailable'
  fi
  # Current schema defaults are already emitted by sysrepo. Canonicalize the
  # schema-known lists using the same representation as the manager normalizer.
  jq -cS -f @normalizeFilter@ "$work/configuration.json" >"$work/normalized.json"
  configuration_digest=$(sha256sum <"$work/normalized.json")
  configuration_digest=${configuration_digest%% *}
}
commit_configuration() {
  jq -cn --arg digest "$configuration_digest" --rawfile configuration "$work/draft.json" \
    -f @requestFilter@ >"$work/rpc.json"
  if ! timeout --kill-after=2 32 folio-repository "$FOLIO_SCOPE" cfg \
      --rpc="$work/rpc.json" --format json --timeout 30 >"$work/result.json" 2>"$work/error"; then
    cat "$work/error" >&2
    if [[ $(cat "$work/error") == *'no matching subscribers'* ]]; then
      finish unavailable null 'Manager subscriber is unavailable'
    fi
    finish failure null 'Configuration RPC failed'
  fi
  result=$(jq -ce '."folio-environment:configuration-commit"' "$work/result.json") ||
    finish failure null 'Invalid manager reply'
  status=$(jq -er .status <<<"$result") || finish failure null 'Missing manager status'
  error=$(jq -r '.error // ""' <<<"$result")
  if [[ ${FOLIO_COMMAND:-} == modules && "$status" == invalid && "$error" == 'Unknown module or unsupported scope' ]]; then
    error='The running manager catalogue does not recognize this module. First deploy this source with the current module selection, then enable the module and deploy again.'
  fi
  digest=$(jq -r '.digest // ""' <<<"$result")
  if [[ "$status" == success && "$FOLIO_JSON" == false ]]; then
    printf '%s\n' 'Desired configuration saved. Run folio plan, then build and apply the reviewed plan.' >&2
  fi
  finish "$status" "$(jq -cn --arg digest "$digest" 'if $digest=="" then null else {digest:$digest} end')" "$error"
}
