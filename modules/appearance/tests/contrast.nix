{ pkgs }:
pkgs.runCommand "folio-everforest-contrast" {
  nativeBuildInputs = [ pkgs.python3 ];
} ''
  mkdir $out
  python3 ${./contrast.py} ${../lib/everforest.json} >$out/ratios.json
''
