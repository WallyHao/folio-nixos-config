{ pkgs, package }:
pkgs.runCommand "folio-panel-browser-tests" {
  nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.playwright p.pytest ])) ];
  PLAYWRIGHT_BROWSERS_PATH = pkgs.playwright-driver.browsers.override { withFirefox = false; withWebkit = false; };
  PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
  FONTCONFIG_FILE = pkgs.makeFontsConf { fontDirectories = [ pkgs.maple-mono.NF-CN ]; };
} ''
  export PYTHONPATH=${package}/lib:${./.}
  export HOME=$TMPDIR/home XDG_CONFIG_HOME=$TMPDIR/config
  mkdir -p "$HOME" "$out"
  python ${./browser.py} "$out"
''
