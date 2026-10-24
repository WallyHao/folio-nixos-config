{ pkgs }:
pkgs.runCommand "folio-network-proxy-tests"
  {
    nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.pytest ])) ];
  }
  ''
    export FOLIO_PROXY_SOURCE=${../runtime/operations/proxy.py}
    python -m pytest -q ${./test_proxy.py} --basetemp=$TMPDIR/pytest
    touch $out
  ''
