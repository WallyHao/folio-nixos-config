{ pkgs, lib }:
context:
let
  settings = context.settings."folio-terminal:terminal" or { };
  colors = builtins.fromJSON (builtins.readFile ./colors.json);
  palette = colors.palettes.${context.globals.appearance};
in {
  programs.yazi = {
    enable = settings.tools.yazi or true;
    shellWrapperName = "y";
    enableZshIntegration = settings.shell.enabled or true;
    enableBashIntegration = false;
    enableFishIntegration = false;
    enableNushellIntegration = false;
    extraPackages = [ pkgs.xdg-utils ];
    theme = import ./yazi-theme.nix { inherit palette; };
    settings = {
      mgr = {
        sort_by = "natural";
        sort_dir_first = true;
        show_hidden = false;
        show_symlink = true;
      };
      # Use the default editor and desktop MIME associations rather than
      # depending directly on the Emacs or applications modules.
      opener.edit = [{ run = "$EDITOR %s"; block = true; desc = "Edit"; }];
      opener.open = [{ run = "${pkgs.xdg-utils}/bin/xdg-open %s1"; orphan = true; desc = "Open"; }];
      open.prepend_rules = [
        { url = "*.md"; use = "edit"; }
        { mime = "application/pdf"; use = "open"; }
        { mime = "image/*"; use = "open"; }
      ];
    };
  };
}
