profile_ready() {
  local profile=$1 root=$HOME/.var/app/app.zen_browser.zen/.zen
  [[ "$profile" =~ ^[a-zA-Z0-9][a-zA-Z0-9._\ -]{0,127}$ && -d "$root/$profile" && ! -L "$root/$profile" && -f "$root/profiles.ini" && ! -L "$root/profiles.ini" ]] || return 1
  awk -F= -v wanted="$profile" '
    function finish() { if (profile && path==wanted && relative=="1") found=1 }
    /^\[/ { finish(); profile=($0 ~ /^\[Profile[0-9]+\]\r?$/); path=""; relative="" }
    $1=="Path" { path=$2; sub(/\r$/, "", path) }
    $1=="IsRelative" { relative=$2; sub(/\r$/, "", relative) }
    END { finish(); exit !found }' "$root/profiles.ini"
}
deploy_files() {
  local name=$1 generation=$2 entry profile relative source expected policy key owned before after temporary file prior_backup
  configuration_state=configuration-pending
  [[ -n "$generation" ]] || return 0
  entry=$(jq -ce --arg name "$name" '.applications[] | select(.name==$name)' "$generation/folio-applications.json") || return 0
  if [[ "$name" != zen ]]; then configuration_state=applied; return 0; fi
  profile=$(jq -r '.profile // ""' <<<"$entry")
  profile_ready "$profile" || return 0
  configuration_state=applied
  while IFS= read -r file; do
    relative=.var/app/app.zen_browser.zen/.zen/$profile/$(jq -er .destination <<<"$file")
    source=$(jq -er .source <<<"$file")
    [[ "$source" =~ ^/nix/store/[a-z0-9]{32}-[^/]+$ && -f "$source" && ! -L "$source" ]] || return 4
    expected=$(jq -er .sha256 <<<"$file")
    [[ $(hash_file "$source") == "$expected" ]] || return 4
    key=$(printf '%s' "$relative" | sha256sum); key=${key%% *}
    owned=$app_state/files/$key.json
    temporary=$work/file-$key.json
    folio-applications-files inspect "$HOME" "$relative" >"$temporary" || return 4
    before=$(jq -er .digest "$temporary")
    policy=new
    if jq -e --arg key "$key" '.fileEffects[$key] != null' "$record" >/dev/null; then
      before=$(jq -er --arg key "$key" '.fileEffects[$key].before' "$record")
      policy=$(jq -er --arg key "$key" '.fileEffects[$key].policy' "$record")
    elif [[ -f "$owned" ]]; then
      [[ $(jq -er .relative "$owned") == "$relative" && $(jq -er .digest "$owned") == "$before" ]] || return 4
      policy=owned
    elif [[ "$before" != absent ]]; then
      [[ $(jq -r .adoptFiles "$record") == true ]] || return 4
      policy=adopt
    fi
    # Persist preimages before publication. A resumed task reuses this exact
    # intent rather than treating its completed first write as unmanaged data.
    if ! jq -e --arg key "$key" '.fileEffects[$key] != null' "$record" >/dev/null; then
      jq --arg key "$key" --arg relative "$relative" --arg before "$before" --arg policy "$policy" \
        '.fileEffects[$key]={relative:$relative,before:$before,policy:$policy}' "$record" | folio-atomic-write "$record"
    fi
    folio-applications-files publish "$HOME" "$relative" "$source" "$(jq -er .mode <<<"$file")" \
      "$before" "$task_id" "$policy" "$expected" >"$temporary" || return 4
    after=$(jq -er .digest "$temporary")
    prior_backup=null
    [[ ! -f "$owned" ]] || prior_backup=$(jq -c '.backup // null' "$owned")
    if [[ "$policy" == adopt && "$prior_backup" == null ]]; then prior_backup=$(jq -cn --arg path "$relative.folio-backup-$task_id" '$path'); fi
    jq -cnS --arg relative "$relative" --arg digest "$after" --arg source "$source" --arg name "$name" \
      --arg configurationDigest "$configuration_digest" --argjson backup "$prior_backup" \
      '{format:1,application:$name,relative:$relative,digest:$digest,source:$source,configurationDigest:$configurationDigest,backup:$backup}' |
      folio-atomic-write "$owned"
    if jq -e '.changed==true' "$temporary" >/dev/null; then configuration_state=restart-required; fi
  done < <(jq -c '.files[]' <<<"$entry")
}
