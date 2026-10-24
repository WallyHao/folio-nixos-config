{ pkgs, lib }:
context:
let
  enabled = context.settings.native.imv or true;
  colors = context.theme;
  palette = colors.palettes.${context.globals.appearance};
  imageTypes = [
    "image/png"
    "image/jpeg"
    "image/gif"
    "image/webp"
    "image/avif"
    "image/tiff"
    "image/bmp"
    "image/svg+xml"
    "image/heif"
    "image/heic"
  ];
in
{
  programs.imv = {
    enable = enabled;
    settings.options = {
      background = lib.removePrefix "#" palette.bg0;
      overlay_font = "${context.globals.font-family}:${toString context.globals.font-size}";
      scaling_mode = "full";
    };
  };
  xdg.mimeApps = lib.mkIf enabled {
    enable = true;
    defaultApplications = lib.genAttrs imageTypes (_: [ "imv.desktop" ]);
  };
}
