{ pkgs, package }:
pkgs.runCommand "folio-applications-store-tests"
  {
    nativeBuildInputs = [
      (pkgs.python3.withPackages (p: [ p.pytest ]))
      pkgs.bash
      pkgs.jq
    ];
  }
  ''
    export PYTHONPATH=${package}/lib
    python -m pytest -q ${./test_store.py} --basetemp=$TMPDIR/pytest
    python -m pytest -q ${../.}/tests/test_preparation.py --basetemp=$TMPDIR/preparation
    touch $out
  ''
