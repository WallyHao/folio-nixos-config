{ pkgs, lib }:
context:
let
  enabled = context.settings."folio-applications:applications".native.zathura or true;
in {
  programs.zathura = {
    enable = enabled;
    options = {
      selection-clipboard = "clipboard";
      adjust-open = "best-fit";
      scroll-step = 50;
      # Preserve the document's original colors, including diagrams and photos.
      recolor = false;
      font = "${context.globals.font-family} ${toString context.globals.font-size}";
    };
  };
  xdg.mimeApps = lib.mkIf enabled {
    enable = true;
    defaultApplications."application/pdf" = [ "org.pwmt.zathura.desktop" ];
  };
}
