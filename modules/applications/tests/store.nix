{ pkgs, package }:
pkgs.runCommand "folio-applications-store-tests" {
  nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.pytest ])) ];
} ''
  export PYTHONPATH=${package}/lib
  python -m pytest -q ${./test_store.py} --basetemp=$TMPDIR/pytest
  touch $out
''
