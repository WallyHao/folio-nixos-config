{ pkgs, pi, bootstrap }:
pkgs.runCommand "folio-agents-runtime" {
  nativeBuildInputs = [ pkgs.jq pkgs.coreutils pkgs.bash ];
} ''
  export HOME=$TMPDIR/home XDG_STATE_HOME=$TMPDIR/state XDG_CONFIG_HOME=$TMPDIR/config
  mkdir -p "$HOME" "$out"
  ${pi}/bin/pi --version | tee "$out/version.txt" | grep -Fx '${pi.version}'
  timeout --kill-after=2 30 ${pi}/bin/pi --offline --help >"$out/help.txt"
  bash ${./pi.sh} ${pi} ${./fixture.ts}
  codexMigration=$(jq -r '.[] | select(.module=="folio-codex") | .transform' ${bootstrap}/migrations.json)
  piMigration=$(jq -r '.[] | select(.module=="folio-agents" and .from=="2026-10-22") | .transform' ${bootstrap}/migrations.json)
  gitMigration=$(jq -r '.[] | select(.module=="folio-git") | .transform' ${bootstrap}/migrations.json)
  printf '%s\n' '{"folio-environment:environment":{"modules":[{"name":"codex","enabled":false},{"name":"git","enabled":false},{"name":"terminal","enabled":true}]}}' |
    "$codexMigration" | "$piMigration" | "$gitMigration" |
    jq -e '."folio-environment:environment".modules |
      any(.[]; .name=="agents" and .enabled==false and ."folio-agents:agents".pi.enabled==false) and
      any(.[]; .name=="terminal" and ."folio-terminal:terminal".git.enabled==false)'
  for enabled in true false; do
    jq -cn --argjson enabled "$enabled" '{"folio-environment:environment":{modules:[{
      name:"agents",enabled:$enabled,"folio-agents:agents":{
        codex:{enabled:false,theme:false},dsh:{enabled:$enabled}}}]}}' |
      "$piMigration" | jq -e --argjson enabled "$enabled" '
        ."folio-environment:environment".modules[0] |
        .enabled==$enabled and (."folio-agents:agents" |
        .pi.enabled==$enabled and .codex.enabled==false and .codex.theme==false and (has("dsh")|not))'
  done
  printf '%s\n' '{"folio-environment:environment":{"modules":[{"name":"agents","enabled":true}]}}' |
    "$piMigration" | jq -e '."folio-environment:environment".modules[0] | has("folio-agents:agents")|not'
  if printf '%s\n' '{"folio-environment:environment":{"modules":[{"name":"agents","folio-agents:agents":{"dsh":{},"pi":{}}}]}}' |
    "$piMigration" >/dev/null 2>&1; then exit 1; fi
  printf '%s\n' '{"folio-environment:environment":{"modules":[{"name":"git","enabled":true}]}}' |
    "$gitMigration" | jq -e '."folio-environment:environment".modules[0] |
      .name=="terminal" and .enabled and ."folio-terminal:terminal".git.enabled and
      ."folio-terminal:terminal".shell.enabled==false and ."folio-terminal:terminal".tools.fzf==false'
  if printf '%s\n' '{"folio-environment:environment":{"modules":[{"name":"codex"},{"name":"agents"}]}}' |
    "$codexMigration" >/dev/null 2>&1; then exit 1; fi
  if printf '%s\n' '{"folio-environment:environment":{"modules":[{"name":"git","enabled":true},{"name":"terminal","enabled":false}]}}' |
    "$gitMigration" >/dev/null 2>&1; then exit 1; fi
''
