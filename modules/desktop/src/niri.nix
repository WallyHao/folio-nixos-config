{ }:
let
  defaultTheme.colors = import ../../appearance/lib { };
  defaultColors = builtins.mapAttrs (_: key: defaultTheme.colors.palettes.dark.${key}) {
    background = "bg0"; surface = "bg1"; foreground = "fg"; accent = defaultTheme.colors.roles.accent; border = "grey0";
  };

  defaultLayout = { gaps = 16; top = -4; bottom = -4; left = -4; right = -4; borderWidth = 3; cornerRadius = 12; };
  normalizeLayout = layout:
    if !builtins.isAttrs layout then throw "folio-desktop: layout must be an attribute set"
    else if builtins.any (key: !(builtins.hasAttr key defaultLayout)) (builtins.attrNames layout)
      then throw "folio-desktop: unsupported layout setting"
    else if !builtins.all builtins.isInt (builtins.attrValues layout)
      then throw "folio-desktop: layout values must be integers"
    else let result = defaultLayout // layout; in
      if result.gaps < 0 || result.borderWidth < 0 || result.cornerRadius < 0
      then throw "folio-desktop: gaps, borderWidth and cornerRadius must be nonnegative"
      else result;

  renderConfig = { colors, foot, polkitAgent, layout ? { }, launcher ? null, clipboardPicker ? null,
    fileManager ? null, browser ? null, animationFile ? null, animationPicker ? null, controlCenter ? null, windowSwitcher ? null, shortcutHelp ? null, screenshotFull ? null, screenshotRegion ? null, modifier ? "Mod", deviceControl ? null, panelCommand ? null, sessionCommand ? "niri-session-confirm" }:
    let
      geometry = normalizeLayout layout;
      workspaceBinds = builtins.concatStringsSep "\n" (builtins.genList (index:
        let workspace = index + 1; key = if workspace == 10 then "0" else toString workspace;
        in ''
          ${modifier}+${key} hotkey-overlay-title="Focus workspace ${toString workspace}" { focus-workspace ${toString workspace}; }
          ${modifier}+Shift+${key} hotkey-overlay-title="Move window to workspace ${toString workspace}" { move-window-to-workspace ${toString workspace}; }
        '') 10);
    in ''
    ${if polkitAgent == null then "" else ''spawn-at-startup "${polkitAgent}"''}

    input {
        keyboard {
            xkb {
                layout "us"
            }
        }
        touchpad {
            natural-scroll
        }
    }

    layout {
        gaps ${toString geometry.gaps}
        struts {
            top ${toString geometry.top}
            bottom ${toString geometry.bottom}
            left ${toString geometry.left}
            right ${toString geometry.right}
        }
        center-focused-column "never"
        default-column-width { proportion 0.5; }
        preset-column-widths {
            proportion 0.5
            proportion 0.75
            proportion 1.0
        }
        focus-ring {
            on
            width ${toString geometry.borderWidth}
            active-color "${colors.accent}"
            inactive-color "#00000000"
            urgent-color "#00000000"
        }
        border {
            off
            width ${toString geometry.borderWidth}
            active-color "${colors.accent}"
            inactive-color "${colors.border}"
            urgent-color "${colors.urgent or colors.accent}"
        }
        background-color "${colors.background}"
    }

    prefer-no-csd

    screenshot-path "~/Pictures/Screenshots/Screenshot_%Y-%m-%d_%H-%M-%S.png"

    window-rule {
        geometry-corner-radius ${toString geometry.cornerRadius}
        clip-to-geometry true
    }

    ${if shortcutHelp == null then "" else ''
    window-rule {
        match app-id=r#"^org\.folio\.Shortcuts$"#
        open-floating true
        default-column-width { proportion 0.48; }
    }
    ''}

    overview {
        backdrop-color "${colors.background}"
    }

    hotkey-overlay { skip-at-startup; }

    binds {
        ${if deviceControl == null then "" else ''
        XF86AudioRaiseVolume allow-when-locked=true { spawn "${deviceControl}" "devices" "volume" "+5"; }
        XF86AudioLowerVolume allow-when-locked=true { spawn "${deviceControl}" "devices" "volume" "-5"; }
        XF86AudioMute allow-when-locked=true { spawn "${deviceControl}" "devices" "mute"; }
        XF86MonBrightnessUp allow-when-locked=true { spawn "${deviceControl}" "devices" "brightness" "+5"; }
        XF86MonBrightnessDown allow-when-locked=true { spawn "${deviceControl}" "devices" "brightness" "-5"; }
        ''}
        ${if launcher == null then "" else ''${modifier}+D hotkey-overlay-title="Open application and window launcher" { spawn "${launcher}"; }''}
        ${if clipboardPicker == null then "" else ''${modifier}+V hotkey-overlay-title="Open clipboard history" { spawn "${clipboardPicker}"; }''}
        ${if animationPicker == null then "" else ''${modifier}+A repeat=false hotkey-overlay-title="Choose window animations" { spawn "${animationPicker}"; }''}
        ${if controlCenter == null then "" else ''${modifier}+C repeat=false hotkey-overlay-title="Open device controls" { spawn "${controlCenter}"; }''}
        ${if panelCommand == null then "" else ''${modifier}+P repeat=false hotkey-overlay-title="Open Folio panel" { spawn "${panelCommand}" "panel"; }''}
        ${modifier}+Return hotkey-overlay-title="Open terminal" { spawn "${foot}"; }
        ${if fileManager == null then "" else ''${modifier}+Y hotkey-overlay-title="Open Yazi" { spawn "${foot}" "-e" "${fileManager}"; }''}
        ${if browser == null then "" else ''${modifier}+W hotkey-overlay-title="Open browser" { spawn "${browser}"; }''}
        ${modifier}+Q hotkey-overlay-title="Close window" { close-window; }
        ${modifier}+Tab repeat=false hotkey-overlay-title="${if windowSwitcher == null then "Show workspace overview" else "Switch windows"}" { ${if windowSwitcher == null then "toggle-overview;" else ''spawn "${windowSwitcher}";''} }
        ${if windowSwitcher == null then "" else ''${modifier}+Shift+Tab repeat=false hotkey-overlay-title="Switch windows in reverse" { spawn "${windowSwitcher}" "--reverse"; }''}
        ${modifier}+Shift+Slash repeat=false hotkey-overlay-title="Show all keyboard shortcuts" { ${if shortcutHelp == null then "show-hotkey-overlay;" else ''spawn "${shortcutHelp}";''} }
        ${modifier}+F repeat=false hotkey-overlay-title="Toggle half/full workspace width" { maximize-column; }
        ${modifier}+G repeat=false hotkey-overlay-title="Toggle workspace centering" { center-column; }
        ${modifier}+S repeat=false hotkey-overlay-title="Capture full screen" { ${if screenshotFull == null then "screenshot-screen show-pointer=false;" else ''spawn "${screenshotFull}";''} }
        ${modifier}+Shift+S repeat=false hotkey-overlay-title="Capture screen region" { ${if screenshotRegion == null then "screenshot show-pointer=false;" else ''spawn "${screenshotRegion}";''} }
        ${modifier}+Left hotkey-overlay-title="Focus column left" { focus-column-left; }
        ${modifier}+Right hotkey-overlay-title="Focus column right" { focus-column-right; }
        ${modifier}+Up hotkey-overlay-title="Focus window above" { focus-window-up; }
        ${modifier}+Down hotkey-overlay-title="Focus window below" { focus-window-down; }
        ${modifier}+Shift+Left hotkey-overlay-title="Move column left" { move-column-left; }
        ${modifier}+Shift+Right hotkey-overlay-title="Move column right" { move-column-right; }
        ${workspaceBinds}
        ${modifier}+Shift+E repeat=false hotkey-overlay-title="Exit Niri (confirm)" { quit; }
        ${modifier}+Shift+R repeat=false hotkey-overlay-title="Reboot (confirm)" { spawn "${sessionCommand}" "reboot"; }
        ${modifier}+Shift+T repeat=false hotkey-overlay-title="Power off (confirm)" { spawn "${sessionCommand}" "poweroff"; }
    }
    ${if animationFile == null then "" else ''include "${animationFile}" optional=true''}
  '';

  themeColors = theme:
    let
      appearance = theme.colors.appearance or "dark";
      paletteName = if builtins.elem appearance [ "dark" "light" ] then appearance else "dark";
      palette = theme.colors.palettes.${paletteName};
      roles = theme.colors.roles;
      roleColor = role: palette.${roles.${role}};
    in {
      background = roleColor "background";
      surface = roleColor "surface";
      foreground = roleColor "foreground";
      accent = roleColor "accent";
      border = roleColor "border";
      urgent = palette.red or (roleColor "accent");
    };

  validColor = value: builtins.isString value && builtins.match "#[0-9a-fA-F]{6}" value != null;
in
let
  normalizeSettings = settings:
    if !(builtins.isAttrs settings) then
      throw "folio-desktop: settings-invalid for niri: package settings must be an attribute set"
    else
      let
        unknown = builtins.filter (key: !(builtins.elem key [ "theme" "layout" "launcher" "clipboardPicker" "animationFile" "animationPicker" "controlCenter" "windowSwitcher" "shortcutHelp" "screenshotFull" "screenshotRegion" "modifier" "polkitAgent" ])) (builtins.attrNames settings);
        launcher = settings.launcher or null;
        clipboardPicker = settings.clipboardPicker or null;
        animationFile = settings.animationFile or null;
        animationPicker = settings.animationPicker or null;
        controlCenter = settings.controlCenter or null;
        windowSwitcher = settings.windowSwitcher or null;
        shortcutHelp = settings.shortcutHelp or null;
        screenshotFull = settings.screenshotFull or null;
        screenshotRegion = settings.screenshotRegion or null;
        modifier = settings.modifier or "Mod";
        theme = settings.theme or defaultTheme;
        themeShapeOk = builtins.isAttrs theme
          && theme ? colors
          && builtins.isAttrs theme.colors
          && theme.colors ? palettes
          && builtins.isAttrs theme.colors.palettes
          && theme.colors ? roles
          && builtins.isAttrs theme.colors.roles;
        attemptedColors = if themeShapeOk then
          builtins.tryEval (builtins.deepSeq (themeColors theme) (themeColors theme))
        else { success = false; value = { }; };
        colorCheck = if attemptedColors.success then
          builtins.tryEval
            (builtins.all validColor (builtins.attrValues attemptedColors.value))
        else { success = false; value = false; };
        colorsValid = colorCheck.success && colorCheck.value;
      in
      if unknown != [ ] then
        throw "folio-desktop: settings-invalid for niri: unsupported package settings ${builtins.concatStringsSep ", " unknown}; accepted keys: theme, layout, launcher, clipboardPicker, animationFile, animationPicker, controlCenter, windowSwitcher, shortcutHelp, screenshotFull, screenshotRegion, modifier, polkitAgent"
      else if !colorsValid then
        throw "folio-desktop: settings-invalid for niri: theme must resolve background, surface, foreground, accent and border to six-digit RGB colors"
      else if launcher != null && (!builtins.isString launcher || builtins.match "[A-Za-z0-9_./+-]+" launcher == null)
        then throw "folio-desktop: launcher must be a command name or absolute executable path"
      else if !(builtins.elem modifier [ "Mod" "Super" "Win" "Alt" ])
        then throw "folio-desktop: modifier must be Mod, Super, Win or Alt"
      else if clipboardPicker != null && (!builtins.isString clipboardPicker || builtins.match "[A-Za-z0-9_./+-]+" clipboardPicker == null)
        then throw "folio-desktop: clipboardPicker must be a command name or absolute executable path"
      else if animationFile != null && (!builtins.isString animationFile || builtins.match "/[A-Za-z0-9_./+-]+" animationFile == null)
        then throw "folio-desktop: animationFile must be an absolute path"
      else if animationPicker != null && (!builtins.isString animationPicker || builtins.match "[A-Za-z0-9_./+-]+" animationPicker == null)
        then throw "folio-desktop: animationPicker must be a command name or absolute executable path"
      else if !(builtins.all (command: command == null || (builtins.isString command && builtins.match "[A-Za-z0-9_./+-]+" command != null)) [ controlCenter windowSwitcher shortcutHelp screenshotFull screenshotRegion ])
        then throw "folio-desktop: controlCenter, windowSwitcher, shortcutHelp, screenshotFull and screenshotRegion must be command names or absolute executable paths"
      else if !builtins.isBool (settings.polkitAgent or true) then throw "folio-desktop: polkitAgent must be boolean"
      else { inherit theme launcher clipboardPicker animationFile animationPicker controlCenter windowSwitcher shortcutHelp screenshotFull screenshotRegion modifier; polkitAgent = settings.polkitAgent or true; colors = attemptedColors.value; layout = normalizeLayout (settings.layout or { }); };
in { inherit defaultColors defaultTheme renderConfig themeColors validColor normalizeSettings defaultLayout; }
