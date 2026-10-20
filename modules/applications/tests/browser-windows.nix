{ pkgs, browser }:
let
  # GeckoDriver rejects Zen's branded --version banner before launching it.
  # Translate only that probe; run the unmodified production browser otherwise.
  testBrowser = pkgs.writeShellScript "zen-webdriver" ''
    if [ "''${1:-}" = --version ]; then
      echo 'Mozilla Firefox ${browser.unwrapped.firefoxVersion}'
      exit 0
    fi
    exec ${browser}/bin/zen-beta "$@"
  '';
in pkgs.runCommand "folio-browser-windows" {
  nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.selenium ])) pkgs.geckodriver pkgs.xvfb-run ];
  BROWSER = testBrowser;
  GECKODRIVER = "${pkgs.geckodriver}/bin/geckodriver";
  MOZ_DISABLE_CONTENT_SANDBOX = "1";
  MOZ_ENABLE_WAYLAND = "0";
  FONTCONFIG_FILE = pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts ]; };
} ''
  export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/home/.config"
  export XDG_RUNTIME_DIR="$TMPDIR/runtime"
  mkdir -m 700 -p "$HOME" "$XDG_RUNTIME_DIR" "$out"
  xvfb-run -a python ${./browser-windows.py} "$out"
''
