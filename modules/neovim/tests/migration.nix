{
  pkgs,
  bootstrap,
  repository,
  maintenance,
  history,
}:
let
  old = pkgs.runCommand "folio-before-neovim-bootstrap" { nativeBuildInputs = [ pkgs.jq ]; } ''
    mkdir $out
    cp -RL ${bootstrap}/. $out/
    chmod -R u+w $out
    rm $out/models/user/folio-neovim.yang
    cp ${history}/2026-10-27/folio-emacs.yang $out/models/user/
    jq '."folio-environment:environment".modules |= map(
      if .name=="neovim" then .name="emacs" |
        ."folio-emacs:emacs"={"notes-directory":"~/Documents/Personal notes","default-editor":false}
      else . end)' $out/user.json >user.json
    mv user.json $out/user.json
    jq --arg hash "$(sha256sum <$out/models/user/folio-emacs.yang | cut -d' ' -f1)" \
      '.models.user |= map(if .name=="folio-neovim.yang" then .name="folio-emacs.yang" | .sha256=$hash else . end)' \
      $out/identities.json >identities.json
    mv identities.json $out/identities.json
  '';
  closure = pkgs.closureInfo {
    rootPaths = [
      old
      bootstrap
    ];
  };
  changed = pkgs.runCommand "folio-invalid-editor-revision" { } ''
    mkdir $out
    cp -RL ${bootstrap}/. $out/
    chmod -R u+w $out
    substituteInPlace $out/models/user/folio-neovim.yang \
      --replace-fail 'Neovim preferences;' 'Changed Neovim preferences;'
  '';
in
pkgs.runCommand "folio-neovim-migration"
  {
    nativeBuildInputs = [
      repository
      maintenance
      pkgs.jq
      pkgs.nix
      pkgs.util-linux
    ];
  }
  ''
    export HOME=$TMPDIR/home XDG_STATE_HOME=$TMPDIR/state XDG_RUNTIME_DIR=$TMPDIR/run
    export NIX_REMOTE=local NIX_STATE_DIR=$TMPDIR/nix-state NIX_LOG_DIR=$TMPDIR/nix-log
    export NIX_CONFIG='substituters ='
    mkdir -p "$HOME/Documents/Personal notes" "$HOME/.local/state/folio/emacs" "$XDG_RUNTIME_DIR"
    printf 'personal note\n' >"$HOME/Documents/Personal notes/keep.org"
    printf 'personal editor state\n' >"$HOME/.local/state/folio/emacs/keep"
    nix-store --load-db <${closure}/registration
    jq --arg account "$(id -un)" '."folio-environment:environment".account=$account' ${old}/user.json >defaults.json
    folio-repository user init ${old}/models/user defaults.json
    folio-repository-maintain user snapshot editor ${old} ${old} >snapshot.json
    # The installed model and the replacement share a revision date. This is an
    # explicit model replacement, never permission to mutate one model in place.
    folio-repository-maintain user prepare editor ${bootstrap} >prepared.json
    backup="$XDG_STATE_HOME/folio/backups/repositories/editor"
    jq -e '."folio-environment:environment".modules |
      all(.[]; .name!="emacs" and (has("folio-emacs:emacs")|not)) and
      any(.[]; .name=="neovim" and .enabled==true and
        ."folio-neovim:neovim"."notes-directory"=="~/Documents/Personal notes" and
        ."folio-neovim:neovim"."default-editor"==false)' "$backup/new-running.json"
    for document in running startup; do
      jq -cS '."folio-environment:environment".modules |= map(select(.name!="emacs"))' "$backup/$document.json" >before.json
      jq -cS '."folio-environment:environment".modules |= map(select(.name!="neovim"))' "$backup/new-$document.json" >after.json
      cmp before.json after.json
    done
    # Disabled selections and false booleans must survive the JSON transform.
    jq '."folio-environment:environment".modules |= map(if .name=="emacs" then .enabled=false else . end)' defaults.json |
      jq -ceS -f ${../src/migrate.jq} | jq -e '."folio-environment:environment".modules |
        any(.[]; .name=="neovim" and .enabled==false and ."folio-neovim:neovim"."default-editor"==false)'
    jq '."folio-environment:environment".modules += [{name:"neovim",enabled:true}]' defaults.json >collision.json
    if jq -ceS -f ${../src/migrate.jq} collision.json; then echo 'Duplicate editor selections were accepted' >&2; exit 1; fi
    # Bind a non-activating metadata fixture, then test actual repository swap
    # and restore. No host profile or Home Manager activation is touched.
    mkdir artifact
    printf '#!/bin/sh\nexit 99\n' >artifact/activate
    chmod 0700 artifact/activate
    digest=$(sha256sum <"$backup/new-running.json"); digest=''${digest%% *}
    jq -cnS --arg account "$(id -un)" --arg home "$HOME" --arg bootstrap "${bootstrap}" --arg digest "$digest" \
      '{format:1,scope:"user",account:$account,home:$home,bootstrap:$bootstrap,configurationDigest:$digest}' >artifact/folio-home.json
    artifact=$(nix-store --add artifact)
    folio-repository-maintain user bind editor "$artifact" >bound.json
    folio-repository-maintain user install editor >installed.json
    folio-repository-maintain user finalize editor >finalized.json
    folio-repository user init ${bootstrap}/models/user ${bootstrap}/user.json
    folio-repository user cfg --export --datastore startup --module folio-environment --format json |
      jq -e '."folio-environment:environment".modules | any(.[]; .name=="neovim") and all(.[]; .name!="emacs")'
    # Same-date replacement must not weaken same-model hash/revision checks.
    folio-repository-maintain user snapshot invalid-editor ${bootstrap} ${bootstrap} >invalid-snapshot.json
    code=0
    folio-repository-maintain user prepare invalid-editor ${changed} >invalid-prepare.json || code=$?
    test "$code" = 2
    jq -e '.status=="invalid" and .error=="A model changed without a new YANG revision"' invalid-prepare.json
    folio-repository-maintain user restore editor >restored.json
    folio-repository-maintain user finalize editor >restored-final.json
    folio-repository user init ${old}/models/user defaults.json
    folio-repository user cfg --export --datastore startup --module folio-environment --format json |
      jq -e '."folio-environment:environment".modules | any(.[]; .name=="emacs" and ."folio-emacs:emacs"."default-editor"==false)'
    grep -x 'personal note' "$HOME/Documents/Personal notes/keep.org"
    grep -x 'personal editor state' "$HOME/.local/state/folio/emacs/keep"
    mkdir $out
    cp snapshot.json prepared.json installed.json restored.json $out/
  ''
