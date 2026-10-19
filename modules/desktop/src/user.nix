# Selected Sylphy geometry, shortcuts and bar adapted at
# 9cba023d90c4485b33a91e2d12724b6920580580. Excluded shell components are not loaded.
{ pkgs, lib, packages }:
context:
{ config, lib, ... }:
let
  settings = context.settings."folio-desktop:desktop" or { };
  theme.colors = (builtins.fromJSON (builtins.readFile ./colors.json)) // { appearance = context.globals.appearance; };
  palette = theme.colors.palettes.${theme.colors.appearance};
  renderer = import ./niri.nix { };
  launcher = import ./fuzzel.nix { };
  bar = settings.bar or true;
in {
  assertions = [{
    assertion = context.capabilities.desktop-provisioned or false;
    message = "Desktop requires the system-provisioned Niri session and portals";
  }];
  home.packages = [ pkgs.niri pkgs.foot pkgs.xwayland-satellite packages.session ]
    ++ lib.optionals (settings.launcher or true) [ pkgs.fuzzel ]
    ++ lib.optionals (settings.clipboard or true) [ packages.clipboard ];
  home.sessionVariables = { MOZ_ENABLE_WAYLAND = "1"; NIXOS_OZONE_WL = "1"; };
  xdg.configFile."niri/config.kdl".text = renderer.renderConfig {
    colors = renderer.themeColors theme;
    foot = "${pkgs.foot}/bin/foot";
    polkitAgent = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
    launcher = if settings.launcher or true then "${pkgs.fuzzel}/bin/fuzzel" else null;
    clipboardPicker = if settings.clipboard or true then "${packages.clipboard}/bin/folio-clipboard-pick" else null;
    sessionCommand = "${packages.session}/bin/folio-session-confirm";
    modifier = "Super";
    deviceControl = if builtins.elem "devices" context.enabledModules then "${pkgs.folio.cli}/bin/folio" else null;
    layout = {
      gaps = settings.gaps or 8;
      top = if bar then -32 else -4;
      bottom = -4; left = -4; right = -4;
      borderWidth = settings.border-width or 3;
      cornerRadius = settings.corner-radius or 12;
    };
  } + lib.optionalString config.home.pointerCursor.enable ''
    cursor {
      xcursor-theme "${config.home.pointerCursor.name}"
      xcursor-size ${toString config.home.pointerCursor.size}
    }
  '';
  xdg.configFile."fuzzel/fuzzel.ini" = lib.mkIf (settings.launcher or true) {
    text = launcher.renderConfig { inherit lib theme; font = "${context.globals.font-family}:size=${toString context.globals.font-size}"; };
  };
  services.mako = lib.mkIf (settings.notifications or true) {
    enable = true;
    settings = {
      font = "${context.globals.font-family} ${toString context.globals.font-size}";
      background-color = palette.bg0;
      text-color = palette.fg;
      border-color = palette.grey0;
      border-radius = 0;
      border-size = 1;
      max-history = 0;
      default-timeout = 5000;
      anchor = "top-right";
      actions = true;
    };
  };
  programs.waybar = lib.mkIf bar {
    enable = true;
    systemd.enable = true;
    settings.main = {
      layer = "top"; position = "top"; height = 36; exclusive = true; spacing = 20;
      modules-left = [ "niri/workspaces" ];
      modules-right = (lib.optional config.i18n.inputMethod.enable "custom/input-language") ++ [ "clock#date" "clock#time" ];
      "custom/input-language" = lib.mkIf config.i18n.inputMethod.enable {
        exec = "${pkgs.folio.inputLanguage}/bin/folio-input-language";
        return-type = "json";
        restart-interval = 2;
        tooltip = false;
      };
      "niri/workspaces" = { format = "●"; disable-click = true; };
      "clock#date" = { format = "{:%m-%d}"; tooltip = false; };
      "clock#time" = { format = "{:%H:%M}"; tooltip = false; };
    };
    style = ''
      * { border: none; border-radius: 0; font-family: "${context.globals.font-family}"; font-size: 18px; font-weight: 700; min-height: 0; }
      window#waybar { background: transparent; color: ${palette.fg}; }
      #workspaces { margin-left: 24px; }
      #workspaces button { padding: 0 4px; margin: 0; background: transparent; color: ${palette.grey0}; font-size: 9px; }
      #workspaces button.active { color: ${palette.green}; font-size: 14px; }
      #custom-input-language { color: ${palette.green}; }
      #custom-input-language.english { color: ${palette.blue}; }
      #custom-input-language.unavailable { color: ${palette.grey0}; }
      #clock.time { margin-right: 24px; }
    '';
  };
  services.cliphist = lib.mkIf (settings.clipboard or true) {
    enable = true;
    allowImages = true;
    extraOptions = [ "-max-dedupe-search" "10" "-max-items" "500" ];
    systemdTargets = [ "graphical-session.target" ];
  };
  services.wl-clip-persist = lib.mkIf (settings.clipboard or true) {
    enable = true;
    clipboardType = "regular";
    systemdTargets = [ "graphical-session.target" ];
  };
  xdg.userDirs = { enable = true; createDirectories = true; };
  home.activation.folioScreenshots = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run install -d -m 0700 ${lib.escapeShellArg "${config.xdg.userDirs.pictures}/Screenshots"}
  '';
}
