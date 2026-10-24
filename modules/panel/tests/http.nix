{ pkgs, package }:
pkgs.runCommand "folio-panel-interaction-tests"
  {
    nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.pytest ])) ];
  }
  ''
    export PYTHONPATH=${package}/lib
    export HOME=$TMPDIR/home
    mkdir -p "$HOME"
    python -m pytest -q ${./test_panel.py} --basetemp=$TMPDIR/pytest
    mkdir $out
    ${package}/bin/folio --version >$out/version.txt
  ''
