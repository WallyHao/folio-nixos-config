{ pkgs }:
pkgs.runCommand "folio-workspace-preparation-tests"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    export FOLIO_WORKSPACE_SOURCE=${../.}
    export FOLIO_NETWORK_PREPARE=${../../network/runtime/operations/prepare.py}
    export FOLIO_PROXY_SOURCE=${../../network/runtime/operations/proxy.py}
    export PYTHONDONTWRITEBYTECODE=1
    python ${./test_preparation.py}
    python ${./test_health.py}
    touch $out
  ''
