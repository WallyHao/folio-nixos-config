{ pkgs, legacyCli, wifi, devices, repository, storeBackend }:
let
  python = pkgs.python3;
in pkgs.stdenvNoCC.mkDerivation {
  pname = "folio-panel";
  version = "0.2.0";
  src = ../cli;
  nativeBuildInputs = [ pkgs.makeWrapper ];
  dontBuild = true;
  installPhase = ''
    mkdir -p $out/lib $out/bin
    cp -R folio_panel $out/lib/
    cp ${storeBackend}/lib/folio_store.py $out/lib/folio_store.py
    cat >$out/lib/folio_panel/paths.py <<'PY'
    LEGACY = "${legacyCli}/bin/folio"
    WIFI = "${wifi}/bin/folio-network-wifi"
    DEVICES = "${devices}/bin/folio-devices-panel"
    REPOSITORY = "${repository}/bin/folio-repository"
    FLATPAK = "${pkgs.flatpak}/bin/flatpak"
    OPENER = "${pkgs.xdg-utils}/bin/xdg-open"
    PY
    makeWrapper ${python}/bin/python3 $out/bin/folio \
      --add-flags '-m folio_panel' --set PYTHONPATH "$out/lib"
    mkdir -p $out/share/applications
    cat >$out/share/applications/folio-panel.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=Folio Panel
    Comment=Wi-Fi, proxy, applications, sound and display controls
    Exec=$out/bin/folio panel
    Icon=preferences-system
    Terminal=false
    Categories=Settings;
    EOF
  '';
  meta.mainProgram = "folio";
}
