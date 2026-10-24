{
  pkgs,
  bootstrap,
  repository,
  maintenance,
}:
let
  lib = pkgs.lib;
  oldModels = import ./previous-theme-models.nix { inherit pkgs; };
  old = pkgs.runCommand "folio-before-shared-theme-bootstrap" { nativeBuildInputs = [ pkgs.jq ]; } ''
    mkdir $out
    cp -RL ${bootstrap}/. $out/
    chmod -R u+w $out
    ${lib.concatMapStringsSep "\n" (model: ''
      for scope in user system; do
        if [[ -f "$out/models/$scope/${model.name}" ]]; then
          cp ${model.path} "$out/models/$scope/${model.name}"
        fi
      done
    '') oldModels}
    jq '."folio-environment:environment" |= (
      .preferences.scheme="everforest" | .preferences.appearance="dark" |
      .modules |= map(if .name=="appearance" then ."folio-appearance:appearance".appearance="light" else . end))' \
      $out/user.json >user.json
    mv user.json $out/user.json
  '';
  closure = pkgs.closureInfo {
    rootPaths = [
      old
      bootstrap
    ];
  };
in
pkgs.runCommand "folio-shared-theme-migration"
  {
    nativeBuildInputs = [
      repository
      maintenance
      pkgs.jq
      pkgs.util-linux
      pkgs.nix
    ];
  }
  ''
    export HOME=$TMPDIR/home XDG_STATE_HOME=$TMPDIR/state XDG_RUNTIME_DIR=$TMPDIR/run
    export NIX_REMOTE=local NIX_STATE_DIR=$TMPDIR/nix-state NIX_LOG_DIR=$TMPDIR/nix-log
    export NIX_CONFIG='substituters ='
    mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
    nix-store --load-db <${closure}/registration
    jq --arg account "$(id -un)" '."folio-environment:environment".account=$account' ${old}/user.json >defaults.json
    folio-repository user init ${old}/models/user defaults.json
    folio-repository-maintain user snapshot theme ${old} ${old} >snapshot.json
    folio-repository-maintain user prepare theme ${bootstrap} >prepared.json
    jq -e '.status=="success"' prepared.json
    # Binding fixture refuses activation; this check only swaps isolated repositories.
    mkdir artifact
    printf '#!/bin/sh\nexit 99\n' >artifact/activate
    chmod 0700 artifact/activate
    digest=$(sha256sum <"$XDG_STATE_HOME/folio/backups/repositories/theme/new-running.json")
    jq -cnS --arg account "$(id -un)" --arg home "$HOME" --arg bootstrap "${bootstrap}" --arg digest "''${digest%% *}" \
      '{format:1,scope:"user",account:$account,home:$home,bootstrap:$bootstrap,configurationDigest:$digest}' >artifact/folio-home.json
    artifact=$(nix-store --add artifact)
    folio-repository-maintain user bind theme "$artifact" >bound.json
    folio-repository-maintain user install theme >installed.json
    folio-repository-maintain user finalize theme >finalized.json
    folio-repository user cfg --export --datastore startup --module folio-environment --format json |
      jq -e '."folio-environment:environment" |
        (.preferences | has("scheme") | not) and (.preferences | has("appearance") | not) and
        all(.modules[] | select(.name=="appearance"); ."folio-appearance:appearance" | has("appearance") | not)'
    folio-repository user init ${bootstrap}/models/user ${bootstrap}/user.json
    # A retained rollback restores the exact old schema and local preference.
    folio-repository-maintain user restore theme >restored.json
    folio-repository-maintain user finalize theme >restored-final.json
    folio-repository user cfg --export --datastore startup --module folio-environment --format json |
      jq -e '."folio-environment:environment" | .preferences.appearance=="dark" and
        any(.modules[]; .name=="appearance" and ."folio-appearance:appearance".appearance=="light")'
    folio-repository user init ${old}/models/user ${old}/user.json
    mkdir $out
    cp snapshot.json prepared.json installed.json restored.json $out/
  ''
