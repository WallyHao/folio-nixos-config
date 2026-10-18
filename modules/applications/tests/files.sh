#!/usr/bin/env bash
set -euo pipefail
publisher=$1
test_root=$(mktemp -d /tmp/folio-application-files.XXXXXX)
trap 'echo "Retained regular-file evidence: $test_root" >&2' EXIT
home=$test_root/home
profile=$home/.var/app/app.zen_browser.zen/.zen/selected
mkdir -p "$profile/chrome" "$test_root/sources"
printf 'user_pref("folio.test", true);\n' >"$test_root/sources/user.js"
source_path=$(nix-store --add "$test_root/sources/user.js")
hash=$(sha256sum <"$source_path"); hash=${hash%% *}
relative=.var/app/app.zen_browser.zen/.zen/selected/user.js
printf 'application-owned preferences\n' >"$profile/prefs.js"
printf 'unmanaged customization\n' >"$profile/user.js"
before=$("$publisher" inspect "$home" "$relative" | jq -r .digest)
code=0
"$publisher" publish "$home" "$relative" "$source_path" replace "$before" initial new "$hash" >"$test_root/refused.json" || code=$?
[[ "$code" == 4 && $(cat "$profile/user.js") == 'unmanaged customization' ]]
"$publisher" publish "$home" "$relative" "$source_path" replace "$before" initial adopt "$hash" >"$test_root/adopted.json"
[[ -f "$profile/user.js" && ! -L "$profile/user.js" ]]
[[ $(cat "$profile/user.js.folio-backup-initial") == 'unmanaged customization' ]]
# Retry the already performed intent without creating another backup.
"$publisher" publish "$home" "$relative" "$source_path" replace "$before" initial adopt "$hash" | jq -e '.changed==false'
printf 'unexpected later edit\n' >"$profile/user.js"
code=0
"$publisher" publish "$home" "$relative" "$source_path" replace "$hash" later owned "$hash" >"$test_root/conflict.json" || code=$?
[[ "$code" == 4 && $(cat "$profile/user.js") == 'unexpected later edit' ]]
printf '/* Folio managed include. */\n@import url("folio/ui.css");\n' >"$test_root/sources/include.css"
include_source=$(nix-store --add "$test_root/sources/include.css")
include_hash=$(sha256sum <"$include_source"); include_hash=${include_hash%% *}
relative=.var/app/app.zen_browser.zen/.zen/selected/chrome/userChrome.css
printf 'body { color: red; }\n' >"$profile/chrome/userChrome.css"
before=$("$publisher" inspect "$home" "$relative" | jq -r .digest)
"$publisher" publish "$home" "$relative" "$include_source" include "$before" include adopt "$include_hash" >"$test_root/include.json"
"$publisher" publish "$home" "$relative" "$include_source" include "$before" include adopt "$include_hash" >"$test_root/retry.json"
[[ $(rg -c 'Folio managed include' "$profile/chrome/userChrome.css") == 1 ]]
rg -q 'body \{ color: red; \}' "$profile/chrome/userChrome.css"
[[ $(cat "$profile/prefs.js") == 'application-owned preferences' ]]
mv "$profile/user.js" "$profile/untouched"
ln -s "$profile/prefs.js" "$profile/user.js"
code=0
"$publisher" inspect "$home" .var/app/app.zen_browser.zen/.zen/selected/user.js >"$test_root/symlink.json" || code=$?
[[ "$code" == 4 && $(cat "$profile/prefs.js") == 'application-owned preferences' ]]
mv "$profile" "$test_root/escaped-profile"
ln -s "$test_root/escaped-profile" "$profile"
code=0
"$publisher" inspect "$home" "$relative" >"$test_root/parent.json" || code=$?
[[ "$code" == 4 ]]
