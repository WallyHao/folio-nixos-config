{
  pkgs,
  runtime,
  cli,
  repository,
  bootstrap,
}:
pkgs.runCommand "folio-configuration-integration"
  {
    nativeBuildInputs = [
      runtime
      cli
      repository
      pkgs.jq
      pkgs.util-linux
    ];
  }
  ''
    export HOME=$TMPDIR/home XDG_STATE_HOME=$TMPDIR/state XDG_RUNTIME_DIR=$TMPDIR/run
    mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
    bash ${./configuration.sh} ${bootstrap}
    touch $out
  ''
