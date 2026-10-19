# Adapted from Sylphy Fcitx5 integration and Koru candidate geometry at
# 9cba023d90c4485b33a91e2d12724b6920580580. Personal input data is never imported.
{ pkgs, lib }:
context:
{ config, lib, ... }:
let
  settings = context.settings."folio-input:input" or { };
  seed = import ./package.nix { inherit pkgs; candidateCount = settings.candidate-count or 7; };
  colors = builtins.fromJSON (builtins.readFile ./colors.json);
  palette = colors.palettes.${context.globals.appearance};
  panelSvg = pkgs.writeText "folio-input-panel.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" width="80" height="80" viewBox="0 0 80 80">
      <rect x="3" y="3" width="74" height="74" rx="12" ry="12" fill="${palette.bg0}"/>
      <rect x="3" y="3" width="74" height="74" rx="12" ry="12" fill="none" stroke="${palette.yellow}" stroke-width="2"/>
    </svg>
  '';
  panel = pkgs.runCommand "folio-input-panel.png" { nativeBuildInputs = [ pkgs.librsvg ]; }
    "rsvg-convert -w 80 -h 80 ${panelSvg} -o $out";
in {
  assertions = [{
    assertion = !(settings.wayland-frontend or true) || config.gtk.enable;
    message = "Wayland input integration requires the appearance module's GTK settings";
  }];
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      systemd.enable = true;
      waylandFrontend = settings.wayland-frontend or true;
      addons = [ (pkgs.fcitx5-rime.override { rimeDataPkgs = [ pkgs.rime-data pkgs.rime-ice ]; }) ];
      sessionVariables = {
        XMODIFIERS = lib.mkDefault "@im=fcitx";
        SDL_IM_MODULE = lib.mkDefault "fcitx";
        GLFW_IM_MODULE = lib.mkDefault "ibus";
        QT_IM_MODULE = lib.mkDefault "fcitx";
      };
    };
  };
  home.activation.folioInputDefaults = lib.hm.dag.entryAfter [ "writeBoundary" ]
    (lib.optionalString (settings.seed-defaults or true) "run ${seed}/bin/folio-input-seed");
  xdg.configFile."autostart/org.fcitx.Fcitx5.desktop".text = "[Desktop Entry]\nType=Application\nName=Fcitx 5\nHidden=true\n";
  xdg.configFile."fcitx5/conf/keyboard.conf".text = ''
    EnableHintByDefault=False
    [Hint Trigger]
    0=
    [One Time Hint Trigger]
    0=
  '';
  xdg.configFile."fcitx5/conf/rime.conf".text = "SwitchInputMethodBehavior=CommitRawInput\n";
  xdg.configFile."fcitx5/conf/classicui.conf".text = ''
    Theme=folio
    Font=${context.globals.font-family} ${toString context.globals.font-size}
    Vertical Candidate List=False
    PreferTextIcon=${if settings.prefer-text-icon or false then "True" else "False"}
  '';
  xdg.dataFile."fcitx5/themes/folio/panel.png".source = panel;
  xdg.dataFile."fcitx5/themes/folio/theme.conf".text = ''
    [Metadata]
    Name=Folio Everforest
    Version=1
    Description=Fern candidate panel
    [InputPanel]
    NormalColor=${palette.fg}
    HighlightCandidateColor=${palette.yellow}
    HighlightColor=${palette.yellow}
    HighlightBackgroundColor=#00000000
    FullWidthHighlight=False
    [InputPanel/Background]
    Image=panel.png
    Color=#00000000
    BorderColor=#ffffff00
    BorderWidth=0
    [InputPanel/Background/Margin]
    Left=18
    Right=18
    Top=18
    Bottom=18
    [InputPanel/Highlight]
    Image=
    Color=#00000000
    BorderColor=#ffffff00
    BorderWidth=0
    [InputPanel/ContentMargin]
    Left=8
    Right=8
    Top=6
    Bottom=6
    [InputPanel/TextMargin]
    Left=6
    Right=6
    Top=4
    Bottom=4
    [InputPanel/PrevPage]
    Image=
    [InputPanel/NextPage]
    Image=
    [InputPanel/ShadowMargin]
    Left=0
    Right=0
    Top=0
    Bottom=0
  '';
}
