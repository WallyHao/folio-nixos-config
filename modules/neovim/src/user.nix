{ lib, package }:
context: {
  home.packages = [ package ];
  home.sessionVariables = lib.mkIf (context.settings.default-editor or true) {
    EDITOR = "${package}/bin/nvim";
    VISUAL = "${package}/bin/nvim";
  };
  # Existing graphical sessions retain the former editor in their environment.
  # Refresh new Zsh processes even when HM's one-time session import was inherited.
  programs.zsh.envExtra = lib.mkIf (context.settings.default-editor or true) (
    lib.mkAfter ''
      export EDITOR=${lib.escapeShellArg "${package}/bin/nvim"}
      export VISUAL=${lib.escapeShellArg "${package}/bin/nvim"}
    ''
  );
  xdg.configFile."folio/neovim/settings.json".text = builtins.toJSON {
    palette = context.theme.palette;
    accent = context.theme.semantic.accent;
    appearance = context.globals.appearance;
    notesDirectory = context.settings.notes-directory or "~/Documents/documents";
  };
}
