# Selected Sylphy geometry, shortcuts and bar adapted at
# 9cba023d90c4485b33a91e2d12724b6920580580. Excluded shell components are not loaded.
{ pkgs, lib, packages }:
context:
{ config, lib, ... }:
let
  settings = context.settings."folio-desktop:desktop" or { };
  theme.colors = context.theme or (import ../../appearance/lib { preferences = context.globals; });
  palette = theme.colors.palettes.${theme.colors.appearance};
  renderer = import ./niri.nix { };
  launcher = import ./fuzzel.nix { };
  browserCommand = if config.xdg.desktopEntries ? zen-beta then "zen-beta"
    else if builtins.elem "applications" context.enabledModules then toString (pkgs.writeShellScript "folio-browser" ''
      exec ${pkgs.flatpak}/bin/flatpak run app.zen_browser.zen
    '') else null;
  bar = settings.bar or true;
  borderWidth = settings.border-width or 3;
  shortcutTheme = pkgs.writeText "folio-shortcuts-theme.json" (builtins.toJSON (
    renderer.themeColors theme // {
      muted = palette.grey1;
      font = context.globals.font-family;
      size = context.globals.font-size;
    }
  ));
  shortcutPython = pkgs.python3.withPackages (p: [ p.pygobject3 ]);
  shortcutHelp = pkgs.stdenvNoCC.mkDerivation {
    name = "folio-shortcuts";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.gobject-introspection pkgs.wrapGAppsHook3 ];
    buildInputs = [ pkgs.gtk3 ];
    installPhase = ''
      install -Dm755 ${pkgs.writeShellScript "folio-shortcuts" ''
        exec ${shortcutPython}/bin/python3 ${../runtime/operations/shortcuts.py} ${shortcutTheme}
      ''} $out/bin/folio-shortcuts
    '';
  };
in {
  assertions = [{
    assertion = context.capabilities.desktop-provisioned or false;
    message = "Desktop requires the system-provisioned Niri session and portals";
  }];
  home.packages = [ packages.niri pkgs.foot pkgs.xwayland-satellite packages.session ]
    ++ lib.optionals (settings.launcher or true) [ pkgs.fuzzel ]
    ++ lib.optionals (settings.clipboard or true) [ packages.clipboard ];
  home.sessionVariables = { MOZ_ENABLE_WAYLAND = "1"; NIXOS_OZONE_WL = "1"; };
  # Keep the session unit present across legacy Home Manager adoption. Removing
  # its user-level file makes sd-switch stop the running compositor even though
  # the same service remains available from NixOS.
  xdg.configFile."systemd/user/niri.service".source = pkgs.runCommand "folio-niri-session-unit" { } ''
    cat ${packages.niri}/lib/systemd/user/niri.service >$out
    printf '\n[Unit]\nX-SwitchMethod=keep-old\n' >>$out
  '';
  xdg.configFile."niri/config.kdl".text = renderer.renderConfig {
    colors = renderer.themeColors theme;
    foot = "${pkgs.foot}/bin/foot";
    polkitAgent = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
    launcher = if settings.launcher or true then "${pkgs.fuzzel}/bin/fuzzel" else null;
    clipboardPicker = if settings.clipboard or true then "${packages.clipboard}/bin/folio-clipboard-pick" else null;
    sessionCommand = "${packages.session}/bin/folio-session-confirm";
    panelCommand = "${pkgs.folio.frontend}/bin/folio";
    shortcutHelp = "${shortcutHelp}/bin/folio-shortcuts";
    modifier = "Super";
    fileManager = if config.programs.yazi.enable or false then "yazi" else null;
    browser = browserCommand;
    deviceControl = if builtins.elem "devices" context.enabledModules then "${pkgs.folio.cli}/bin/folio" else null;
    layout = {
      # Fold the existing 8px outer inset into the common gap: windows now
      # have the same spacing between them as at the left and right edges.
      gaps = (settings.gaps or 16) + 8;
      # Waybar already reserves its exclusive height; retain the normal edge
      # inset rather than subtracting the bar from the compositor work area.
      top = -12;
      bottom = 0;
      left = 0;
      right = 0;
      inherit borderWidth;
      cornerRadius = settings.corner-radius or 12;
    };
  } + lib.optionalString config.home.pointerCursor.enable ''
    cursor {
      xcursor-theme "${config.home.pointerCursor.name}"
      xcursor-size ${toString config.home.pointerCursor.size}
    }
  '';
  xdg.configFile."fuzzel/fuzzel.ini" = lib.mkIf (settings.launcher or true) {
    text = launcher.renderConfig {
      inherit lib theme borderWidth;
      font = "${context.globals.font-family}:size=${toString context.globals.font-size}";
    };
  };
  services.mako = lib.mkIf (settings.notifications or true) {
    enable = true;
    settings = {
      font = "${context.globals.font-family} ${toString context.globals.font-size}";
      background-color = theme.colors.semantic.background;
      text-color = theme.colors.semantic.foreground;
      border-color = theme.colors.semantic.border;
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
      #workspaces button.active { color: ${theme.colors.semantic.accent}; font-size: 14px; }
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
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    # The home directory disables unused XDG locations without allowing
    # applications to fall back to recreating their conventional folders.
    desktop = config.home.homeDirectory;
    music = config.home.homeDirectory;
    publicShare = config.home.homeDirectory;
    templates = config.home.homeDirectory;
    videos = config.home.homeDirectory;
    projects = "${config.home.homeDirectory}/Workspace";
  };
  home.activation.folioScreenshots = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run install -d -m 0700 ${lib.escapeShellArg "${config.xdg.userDirs.pictures}/Screenshots"}
  '';
}
