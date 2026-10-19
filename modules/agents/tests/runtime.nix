{ pkgs, dsh, bootstrap }:
pkgs.runCommand "folio-agents-runtime" {
  nativeBuildInputs = [ pkgs.nodejs_24 pkgs.jq pkgs.coreutils ];
} ''
  export HOME=$TMPDIR/home DSH_HOME=$TMPDIR/dsh
  unset DEEPSEEK_API_KEY DEEPSEEK_BASE_URL
  mkdir -p "$HOME" "$out"
  ${dsh}/bin/dsh --version | tee "$out/version.txt" | grep -Fx 0.2.1-rc.2
  timeout --kill-after=2 30 ${dsh}/bin/dsh headless --help >"$out/headless-help.txt"
  timeout --kill-after=2 30 ${dsh}/bin/dsh plugin --profile headless --version >"$out/plugin-manager-version.txt"
  node ${./native.cjs} ${dsh}/lib/folio-dsh/node_modules ${pkgs.bash}/bin/bash
  codexMigration=$(jq -r '.[] | select(.module=="folio-codex") | .transform' ${bootstrap}/migrations.json)
  gitMigration=$(jq -r '.[] | select(.module=="folio-git") | .transform' ${bootstrap}/migrations.json)
  # Disabled selections survive the move and do not silently enable another tool.
  printf '%s\n' '{"folio-environment:environment":{"modules":[{"name":"codex","enabled":false},{"name":"git","enabled":false},{"name":"terminal","enabled":true}]}}' |
    "$codexMigration" | "$gitMigration" |
    jq -e '."folio-environment:environment".modules |
      any(.[]; .name=="agents" and .enabled==false) and
      any(.[]; .name=="terminal" and ."folio-terminal:terminal".git.enabled==false)'
  # Enabled Git without a terminal selection must not install unrelated utilities.
  printf '%s\n' '{"folio-environment:environment":{"modules":[{"name":"git","enabled":true}]}}' |
    "$gitMigration" | jq -e '."folio-environment:environment".modules[0] |
      .name=="terminal" and .enabled and ."folio-terminal:terminal".git.enabled and
      ."folio-terminal:terminal".shell.enabled==false and ."folio-terminal:terminal".tools.fzf==false'
  if printf '%s\n' '{"folio-environment:environment":{"modules":[{"name":"codex"},{"name":"agents"}]}}' |
    "$codexMigration" >/dev/null 2>&1; then exit 1; fi
  if printf '%s\n' '{"folio-environment:environment":{"modules":[{"name":"git","enabled":true},{"name":"terminal","enabled":false}]}}' |
    "$gitMigration" >/dev/null 2>&1; then exit 1; fi
''
