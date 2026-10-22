{ pkgs }:
pkgs.runCommand "folio-agents-color-tests" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  FOLIO_CODEX_COLORS=${../src/codex/colors.py} python3 ${./test_colors.py}
  touch $out
''
