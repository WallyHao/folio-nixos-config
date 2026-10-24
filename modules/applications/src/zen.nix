{ pkgs }:
let
  # Keep the reviewed upstream browser pin shared by native delivery and checks.
  upstream = builtins.fetchTree {
    type = "github";
    owner = "0xc000022070";
    repo = "zen-browser-flake";
    rev = "a12d482485d877cc066516ea256b435b209a1a8c";
    narHash = "sha256-C9BpLH4dNggam12nz/Fx/M0Vlbw8WcT/cpOc37DPQAA=";
  };
  packages = import (upstream.outPath + "/default.nix") { inherit pkgs; };
  oneTab = pkgs.fetchurl {
    url = "https://addons.mozilla.org/firefox/downloads/file/5063619/one_tab_per_window-0.2.1.xpi";
    sha256 = "c3d698a8cabd82b8b18b4317835534d6d75da4e3a7de2306da057aeea44f0aa1";
  };
  # Gecko reads policies beside the actual executable, not the outer wrapper.
  unwrapped =
    (packages.beta-unwrapped.override {
      policies = {
        ExtensionSettings."onetab@nonexistenturl.net" = {
          installation_mode = "normal_installed";
          install_url = "file://${oneTab}";
          updates_disabled = true;
          private_browsing = true;
          default_area = "navbar";
        };
        Preferences = {
          "browser.link.open_newwindow" = {
            Value = 2;
            Status = "locked";
          };
          "browser.link.open_newwindow.override.external" = {
            Value = 2;
            Status = "locked";
          };
          "zen.window-sync.enabled" = {
            Value = false;
            Status = "locked";
          };
          "zen.window-sync.prefer-unsynced-windows" = {
            Value = true;
            Status = "locked";
          };
        };
      };
    }).overrideAttrs
      (old: {
        postInstall = (old.postInstall or "") + ''
          app="$out/lib/zen-bin-${old.version}"
          install -Dm644 ${./zen-windowing.cfg} "$app/folio-windowing.cfg"
          mkdir -p "$app/defaults/pref"
          chmod u+w "$app/defaults/pref"
          cat > "$app/defaults/pref/folio-windowing.js" <<'EOF'
          pref("general.config.filename", "folio-windowing.cfg");
          pref("general.config.obscure_value", 0);
          pref("general.config.sandbox_enabled", false);
          EOF
        '';
      });
  wrapZen = import (upstream.outPath + "/wrap-zen.nix") pkgs.wrapFirefox;
in
wrapZen unwrapped { icon = "zen-browser"; }
