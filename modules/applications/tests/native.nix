{ pkgs, inputs, source, bootstrap, prepareInput }:
let
  frozen = pkgs.runCommand "folio-native-applications-source" {
    nativeBuildInputs = [ pkgs.jq prepareInput ];
  } ''
    mkdir $out
    cp -R ${source}/. $out/
    chmod -R u+w $out
    jq '."folio-environment:environment".modules |= map(
      if .name=="applications" then
        ."folio-applications:applications".app |= map(.selected=false) |
        ."folio-applications:applications".native={zen:true,obs:true,"zen-profile":"fixture"}
      elif .name=="agents" then ."folio-agents:agents".pi.enabled=true
      else . end)' ${bootstrap}/user.json >configuration.json
    folio-prepare-input configuration.json ${bootstrap} >$out/folio-input.json
  '';
  generation = (import ../../manager/src/outputs.nix {
    inputs = inputs // { self.outPath = frozen; };
  }).homeConfigurations.folio.activationPackage;
in pkgs.runCommand "folio-native-applications" {
  nativeBuildInputs = [ pkgs.jq pkgs.gnugrep ];
} ''
  export HOME=$TMPDIR/home XDG_CONFIG_HOME=$TMPDIR/home/.config
  export QT_QPA_PLATFORM=offscreen
  mkdir -p "$XDG_CONFIG_HOME"
  test -x ${generation}/home-path/bin/zen-beta
  test -x ${generation}/home-path/bin/obs
  test -x ${generation}/home-path/bin/pi
  test -x ${generation}/home-path/bin/zathura
  test -x ${generation}/home-path/bin/yazi
  test -x ${generation}/home-path/bin/imv
  # imv 5.0.1 prints its version successfully but exits with status 1.
  ${generation}/home-path/bin/imv -v >imv-version || test "$?" -eq 1
  grep -Fx 'Version: ${pkgs.imv.version}' imv-version
  ${generation}/home-path/bin/zathura --version >zathura-version
  ${generation}/home-path/bin/yazi --version >yazi-version
  grep -Fx 'application/pdf=org.pwmt.zathura.desktop' ${generation}/home-files/.config/mimeapps.list
  grep -F 'selection-clipboard' ${generation}/home-files/.config/zathura/zathurarc
  grep -Fx 'image/png=imv.desktop' ${generation}/home-files/.config/mimeapps.list
  grep -Fx 'image/jpeg=imv.desktop' ${generation}/home-files/.config/mimeapps.list
  grep -F 'background=272e33' ${generation}/home-files/.config/imv/config
  test -f ${generation}/home-path/share/applications/imv.desktop
  ${generation}/home-path/bin/zen-beta --version >zen-version
  ${generation}/home-path/bin/obs --version >obs-version
  ${generation}/home-path/bin/pi --version >pi-version
  jq -e '.nativeApplications | length==4 and all(.[]; .executable|startswith("/nix/store/"))' ${generation}/folio-applications.json
  browser=$(jq -er '.nativeApplications[] | select(.name=="zen") | .executable' ${generation}/folio-applications.json)
  grep -F '/home/folio/.config/zen/fixture' "$browser"
  grep -F "$browser" ${generation}/home-path/share/applications/zen-beta.desktop
  profileFiles=${generation}/home-files/.config/zen/fixture
  grep -F 'toolkit.legacyUserProfileCustomizations.stylesheets' "$profileFiles/user.js"
  grep -F 'folio/ui.css' "$profileFiles/chrome/userChrome.css"
  grep -F 'folio/content.css' "$profileFiles/chrome/userContent.css"
  test -s "$profileFiles/chrome/folio/ui.css"
  test -s "$profileFiles/chrome/folio/content.css"
  test ! -e "$profileFiles/prefs.js"
  test ! -e "$profileFiles/cookies.sqlite"
  test ! -e "$profileFiles/places.sqlite"
  test ! -e "$HOME/.config/zen/fixture"
  mkdir $out
  cp zen-version obs-version pi-version zathura-version yazi-version imv-version $out/
''
