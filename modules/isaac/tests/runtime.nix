{ pkgs }:
let python = pkgs.python312.withPackages (p: [ p.packaging ]);
in pkgs.runCommand "isaac-runtime-check" {
  nativeBuildInputs = [ python ];
  PYTHON = "${python}/bin/python3.12";
  ISAAC_CLI = "${../cli/isaac.py}";
  ISAAC_DEPENDENCY_CHECK = "${../runtime/validation/dependencies.py}";
} ''
  python3.12 ${./runtime.py} > $out
  python3.12 ${./dependencies.py} >> $out
''
