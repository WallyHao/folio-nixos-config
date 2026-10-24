# Adapted from Sylphy shell selection/rendering at 9cba023d90c4485b33a91e2d12724b6920580580.
{ pkgs, lib }:
context:
let
  settings = context.settings;
  foot = settings.foot or { };
  shell = settings.shell or { };
  tools = settings.tools or { };
  git = settings.git or { };
  selected = name: tools.${name} or true;
  theme.colors = context.theme;
  palette = theme.colors.palettes.${theme.colors.appearance};
  footRenderer = import ./foot.nix { };
  zsh = import ./zsh.nix { };
  shellSettings = {
    inherit theme;
    promptStyle = shell.prompt or "powerlevel10k";
    autosuggestions = shell.autosuggestions or true;
    syntaxHighlighting = shell.syntax-highlighting or true;
  };
  chsrc = pkgs.chsrc.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ../cli/resources/chsrc-curl-failure.patch
      ../cli/resources/chsrc-english.patch
    ];
  });
  toolPackages = {
    inherit (pkgs)
      jq
      unzip
      unrar
      just
      ;
    inherit chsrc;
    typst = import ./typst.nix { inherit pkgs; };
  };
  colors = {
    bg = palette.bg0;
    "bg+" = palette.bg1;
    fg = palette.fg;
    "fg+" = palette.fg;
    hl = palette.green;
    "hl+" = palette.aqua;
    info = palette.green;
    prompt = palette.yellow;
    pointer = palette.yellow;
    marker = palette.yellow;
    spinner = palette.yellow;
    header = palette.grey1;
    border = palette.grey0;
  };
  colorFlags = lib.concatStringsSep "," (lib.mapAttrsToList (key: value: "${key}:${value}") colors);
in
{ config, ... }: {
  imports = [
    ((import ./yazi.nix { inherit pkgs lib; }) context)
  ]
  ++ lib.optional (git.enabled or true) ((import ./git.nix { inherit pkgs lib; }) context);
  home.packages =
    lib.optionals (foot.enabled or true) [
      pkgs.foot
      pkgs.maple-mono.NF-CN
    ]
    ++ lib.mapAttrsToList (_: value: value) (lib.filterAttrs (name: _: selected name) toolPackages);
  xdg.configFile."foot/foot.ini" = lib.mkIf (foot.enabled or true) {
    text = footRenderer.renderConfig {
      inherit lib theme;
      font = foot.font or "${context.globals.font-family}:size=${toString context.globals.font-size}";
      padding = foot.padding or "15x15";
      opacity = foot.opacity or "1";
    };
  };
  programs = {
    bat.enable = selected "bat";
    btop = {
      enable = selected "btop";
      settings = {
        color_theme = "folio";
        theme_background = true;
        truecolor = true;
      };
      themes.folio = import ./btop.nix { inherit lib palette; };
    };
    eza = {
      enable = selected "eza";
      enableZshIntegration = false;
    };
    fd.enable = selected "fd";
    ripgrep.enable = selected "ripgrep";
    zoxide = {
      enable = selected "zoxide";
      enableZshIntegration = shell.enabled or true;
    };
    fzf = {
      enable = selected "fzf";
      enableZshIntegration = shell.enabled or true;
      inherit colors;
      defaultOptions = [
        "--height=45%"
        "--layout=reverse"
        "--border=sharp"
        "--info=inline"
        "--prompt=> "
        "--pointer=>"
        "--marker=+"
      ];
      defaultCommand = lib.mkIf (selected "fd") "${pkgs.fd}/bin/fd --type f --hidden --follow --exclude .git";
      fileWidget.command = lib.mkIf (selected "fd") config.programs.fzf.defaultCommand;
      changeDirWidget.command = lib.mkIf (selected "fd") "${pkgs.fd}/bin/fd --type d --hidden --follow --exclude .git";
    };
    zsh = lib.mkIf (shell.enabled or true) {
      enable = true;
      dotDir = "${config.xdg.configHome}/zsh";
      # The reused renderer owns secure history/cache setup and completion order.
      enableCompletion = false;
      history = {
        path = "${config.xdg.stateHome}/folio/zsh/history";
        size = shell.history-size or 10000;
        save = shell.history-size or 10000;
      };
      initContent = lib.mkOrder 1500 (
        zsh.shellSetup {
          prompt = zsh.renderPrompt lib theme;
          historySize = shell.history-size or 10000;
          historySave = shell.history-size or 10000;
          completion = shell.completion or true;
          pluginSetup =
            lib.optionalString (selected "eza") ''
              unalias l ls la ll lt 2>/dev/null || true
              l() { ${pkgs.eza}/bin/eza --tree --group-directories-first -L 1 "$@"; }
              ls() { ${pkgs.eza}/bin/eza --tree --group-directories-first --long -L 1 "$@"; }
              la() { ${pkgs.eza}/bin/eza --tree --group-directories-first -la -L 1 "$@"; }
              ll() { local d=1; if [[ "$1" == <-> ]]; then d="$1"; shift; fi; ${pkgs.eza}/bin/eza --tree --group-directories-first --long -L "$d" "$@"; }
              lt() { local d=5; if [[ "$1" == <-> ]]; then d="$1"; shift; fi; ${pkgs.eza}/bin/eza --tree --group-directories-first -L "$d" "$@"; }
            ''
            + lib.optionalString ((selected "fzf") && (shell.completion or true)) ''
              source ${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.plugin.zsh
              zstyle ':fzf-tab:*' use-fzf-default-opts yes
              zstyle ':fzf-tab:*' fzf-flags '--color=${colorFlags}'
              zstyle ':completion:*' menu no
              zstyle ':completion:*:descriptions' format '%d'
              zstyle ':fzf-tab:*' switch-group '[' ']'
              bindkey '^I' fzf-tab-complete
              bindkey '^[j' fzf-history-widget
              bindkey '^[k' fzf-file-widget
              bindkey '^[l' fzf-cd-widget
            ''
            + zsh.renderPlugins pkgs shellSettings;
        }
      );
    };
  };
}
