{
  pkgs,
  bootstrap,
  tools,
  normalizer,
  sysrepo,
  prepareInput,
}:
pkgs.runCommand "folio-foundation"
  {
    nativeBuildInputs = [
      tools
      normalizer
      sysrepo
      prepareInput
      pkgs.libyang
      pkgs.jq
      pkgs.util-linux
    ];
  }
  ''
    export HOME=$TMPDIR/home XDG_RUNTIME_DIR=$TMPDIR/run XDG_STATE_HOME=$TMPDIR/state
    mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
    bash ${./foundation.sh} ${bootstrap}
    touch $out
  ''
