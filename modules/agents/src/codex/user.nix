{ pkgs, lib, package }:
context:
let
  settings = context.settings.codex or { };
  theme.colors = (builtins.fromJSON (builtins.readFile ./colors.json)) // { appearance = context.globals.appearance; };
  completion = pkgs.runCommand "folio-codex-zsh-completion" { } ''
    mkdir -p $out/share/zsh/site-functions
    ${package}/bin/codex completion zsh >$out/share/zsh/site-functions/_codex
  '';
in {
  home.packages = [ package ] ++ lib.optional (settings.shell-completion or true) completion;
  # Codex owns its mutable config/auth/session files. Install only a selectable
  # custom theme; /theme persists the user's choice through the supported UI.
  home.file.".codex/themes/folio.tmTheme" = lib.mkIf (settings.theme or true) {
    text = import ./theme.nix { inherit theme; };
  };
}
