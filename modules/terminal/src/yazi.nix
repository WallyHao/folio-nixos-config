{ pkgs, lib }:
context:
let
  settings = context.settings;
  colors = context.theme;
  palette = colors.palettes.${context.globals.appearance};
  baseTheme = (pkgs.formats.toml { }).generate "folio-yazi-base-theme.toml" (
    import ./yazi-theme.nix { inherit palette; }
  );
  iconTheme =
    pkgs.runCommand "folio-yazi-theme"
      {
        nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.tomli-w ])) ];
      }
      ''
        python3 ${./yazi-icons.py} \
          ${pkgs.yazi-unwrapped.srcs.code_src}/yazi-config/preset/theme-dark.toml \
          ${baseTheme} ${lib.escapeShellArg colors.semantic.accent} "$out"
      '';
in
{
  xdg.configFile."yazi/theme.toml" = lib.mkIf (settings.tools.yazi or true) { source = iconTheme; };
  programs.yazi = {
    enable = settings.tools.yazi or true;
    shellWrapperName = "y";
    enableZshIntegration = settings.shell.enabled or true;
    enableBashIntegration = false;
    enableFishIntegration = false;
    enableNushellIntegration = false;
    extraPackages = [ pkgs.xdg-utils ];
    settings = {
      mgr = {
        sort_by = "natural";
        sort_dir_first = true;
        show_hidden = false;
        show_symlink = true;
      };
      # Use the default editor and desktop MIME associations rather than
      # depending directly on the Emacs or applications modules.
      opener.edit = [
        {
          run = "$EDITOR %s";
          block = true;
          desc = "Edit";
        }
      ];
      opener.open = [
        {
          run = "${pkgs.xdg-utils}/bin/xdg-open %s1";
          orphan = true;
          desc = "Open";
        }
      ];
      open.prepend_rules = [
        {
          url = "*.md";
          use = "edit";
        }
        {
          mime = "application/pdf";
          use = "open";
        }
        {
          mime = "image/*";
          use = "open";
        }
      ];
    };
  };
}
