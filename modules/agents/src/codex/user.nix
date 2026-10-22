{ pkgs, lib, package }:
context:
let
  settings = context.settings.codex or { };
  theme.colors = (builtins.fromJSON (builtins.readFile ./colors.json)) // { appearance = context.globals.appearance; };
  themedPackage = import ./package.nix {
    inherit pkgs;
    palette = theme.colors.palettes.${context.globals.appearance};
  };
  selectedPackage = if settings.theme or true then themedPackage else package;
  completion = pkgs.runCommand "folio-codex-zsh-completion" { } ''
    mkdir -p $out/share/zsh/site-functions
    ${selectedPackage}/bin/codex completion zsh >$out/share/zsh/site-functions/_codex
  '';
in {
  home.packages = [ selectedPackage ] ++ lib.optional (settings.shell-completion or true) completion;
  # Select the managed theme at launch without replacing Codex's mutable
  # config/auth/session files. The PTY wrapper also covers fixed TUI accents.
  home.file.".codex/themes/folio.tmTheme" = lib.mkIf (settings.theme or true) {
    text = import ./theme.nix { inherit theme; };
  };
}
