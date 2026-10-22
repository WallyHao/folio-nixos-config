{ pkgs, lib, package }:
context:
let
  settings = context.settings."folio-emacs:emacs" or { };
  colors = context.theme or (import ../../appearance/lib { preferences = context.globals; });
  palette = colors.palettes.${context.globals.appearance};
in {
  home.packages = [ package ];
  home.sessionVariables = lib.mkIf (settings.default-editor or true) { EDITOR = "emacs"; VISUAL = "emacs"; };
  xdg.configFile."folio/emacs/settings.el".text = ''
    ;;; settings.el --- Frozen user preferences -*- lexical-binding: t; -*-
    (setq org-roam-directory (expand-file-name ${builtins.toJSON (settings.notes-directory or "~/Documents/documents")}))
    (setq folio-emacs-colors '(${lib.concatMapStringsSep " " builtins.toJSON [
      palette.bg0 palette.bg1 palette.fg palette.grey1 palette.green
      palette.blue colors.semantic.accent palette.bg_visual palette.red
    ]}))
    (setq folio-emacs-font ${builtins.toJSON "${context.globals.font-family}-${toString context.globals.font-size}"})
  '';
}
