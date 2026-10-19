{ pkgs, legacyCli, wifi, devices, repository }:
let
  python = pkgs.python3.withPackages (p: [ p.textual ]);
in pkgs.stdenvNoCC.mkDerivation {
  pname = "folio-panel";
  version = "0.1.0";
  src = ../cli;
  nativeBuildInputs = [ pkgs.makeWrapper ];
  dontBuild = true;
  installPhase = ''
    mkdir -p $out/lib $out/bin
    cp -R folio_panel $out/lib/
    cat >$out/lib/folio_panel/paths.py <<'PY'
    LEGACY = "${legacyCli}/bin/folio"
    WIFI = "${wifi}/bin/folio-network-wifi"
    DEVICES = "${devices}/bin/folio-devices-panel"
    REPOSITORY = "${repository}/bin/folio-repository"
    PY
    makeWrapper ${python}/bin/python3 $out/bin/folio \
      --add-flags '-m folio_panel' --set PYTHONPATH "$out/lib"
  '';
  meta.mainProgram = "folio";
}
