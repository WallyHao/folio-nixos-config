if ! lock_configuration; then
  reply conflict 'Configuration is busy'; exit 0
fi
if ! recover_configuration; then
  reply failure 'Configuration recovery is required'; exit 0
fi
request='."folio-environment:configuration-commit"'
jq -er "$request.\"configuration-json\"" "$work/request.json" >"$work/draft.json"
expected=$(jq -er "$request.\"expected-digest\"" "$work/request.json")
if ! folio-normalize "$models" "$work/draft.json" >"$work/after.json"; then
  reply invalid 'Configuration does not satisfy the installed YANG model'; exit 0
fi
current_configuration >"$work/before.json"
before_digest=$(digest_file "$work/before.json")
if [[ "$expected" != "$before_digest" ]]; then
  reply conflict 'Desired configuration changed; reload the draft' "$before_digest"; exit 0
fi
# Preferences cannot redefine the provisioned environment/account identity.
if ! jq -en --slurpfile before "$work/before.json" --slurpfile after "$work/after.json" \
    'def identity: ."folio-environment:environment" | [.name,.platform,.scope,.account];
     ($before[0] | identity) == ($after[0] | identity)' >/dev/null; then
  reply invalid 'Provisioned identity is not editable'; exit 0
fi
if ! jq -e --arg scope "$scope" --slurpfile catalogue "$FOLIO_BOOTSTRAP/catalogue.json" \
    'all(."folio-environment:environment".modules[];
      .name as $name | ($catalogue[0][$name].scopes // [] | index($scope)) != null)' "$work/after.json" >/dev/null; then
  reply invalid 'Unknown module or unsupported scope'; exit 0
fi
after_digest=$(digest_file "$work/after.json")
journal=$state/configuration/transaction.json
jq -cnS --slurpfile before "$work/before.json" --slurpfile after "$work/after.json" \
  --arg beforeDigest "$before_digest" --arg afterDigest "$after_digest" \
  '{format:1,phase:"prepared",before:$before[0],after:$after[0],beforeDigest:$beforeDigest,afterDigest:$afterDigest}' |
  folio-atomic-write "$journal"
if ! folio-repository "$scope" cfg --import="$work/after.json" --datastore running --module folio-environment --format json; then
  reply failure 'Running datastore update failed; journal recovery is required'; exit 0
fi
jq '.phase="accepted"' "$journal" | folio-atomic-write "$journal"
if ! folio-repository "$scope" cfg --copy-from running --datastore startup --module folio-environment; then
  reply failure 'Configuration accepted but startup persistence failed; recovery is required'; exit 0
fi
jq '.phase="saved"' "$journal" | folio-atomic-write "$journal"
reply success '' "$after_digest"
