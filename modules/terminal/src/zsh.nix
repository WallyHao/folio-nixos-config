{ }:
let
  # Standalone prompt defaults stay inside this Flake; root integration supplies
  # the full user-owned theme through the Home Manager option.
  defaultTheme = {
    colors = {
      appearance = "dark";
      palettes.dark = {
        fg = "#d3c6aa";
        green = "#a7c080";
        grey1 = "#859289";
      };
      roles = { foreground = "fg"; accent = "green"; muted = "grey1"; };
    };
  };

  renderPrompt = lib: theme:
    let
      paletteName = theme.colors.appearance or "dark";
      palette = theme.colors.palettes.${paletteName} or theme.colors.palettes.dark;
      roles = theme.colors.roles or { };
      rawColor = role:
        let
          paletteKey = roles.${role} or (if role == "accent" then "green" else "fg");
          color = palette.${paletteKey} or palette.fg;
        in
        if builtins.isString color && builtins.match "#[0-9A-Fa-f]{6}" color != null
        then color
        else throw "folio-zsh: theme role ${role} must resolve to a six-digit hexadecimal color";
      hexDigit = {
        "0" = 0; "1" = 1; "2" = 2; "3" = 3; "4" = 4;
        "5" = 5; "6" = 6; "7" = 7; "8" = 8; "9" = 9;
        a = 10; b = 11; c = 12; d = 13; e = 14; f = 15;
        A = 10; B = 11; C = 12; D = 13; E = 14; F = 15;
      };
      byte = color: offset:
        let
          pair = builtins.substring offset 2 (lib.toLower color);
          digits = lib.stringToCharacters pair;
        in
        builtins.foldl' (value: digit: value * 16 + hexDigit.${digit}) 0 digits;
      ansi = role:
        let color = rawColor role;
        in "38;2;${toString (byte color 1)};${toString (byte color 3)};${toString (byte color 5)}m";
    in
    ''
      typeset -g FOLIO_ZSH_PROMPT_VERSION=1
      typeset -g _folio_accent=$'\e[${ansi "accent"}'
      typeset -g _folio_muted=$'\e[${ansi "muted"}'
      typeset -g _folio_foreground=$'\e[${ansi "foreground"}'
      typeset -g _folio_reset=$'\e[0m'
      # Native consoles use their configured 16-color palette. Dumb terminals
      # need plain text rather than unsupported escape sequences.
      case "$TERM" in
        linux)
          _folio_accent=$'\e[32m'
          _folio_muted=$'\e[90m'
          _folio_foreground=$'\e[37m'
          ;;
        dumb)
          _folio_accent= _folio_muted= _folio_foreground= _folio_reset=
          ;;
      esac
      PROMPT="%{$_folio_accent%}%n%{$_folio_muted%}@%m %{$_folio_foreground%}%~%{$_folio_accent%} %#%{$_folio_reset%} "
    '';

  shellSetup = { prompt, historySize ? 10000, historySave ? 10000, completion ? true, pluginSetup ? "" }:
    ''
      # Inspect directories with Zsh builtins so warm startup needs no mkdir,
      # chmod, or external stat process. Never follow a private-dir symlink or
      # change permissions on a directory owned by another user.
      zmodload zsh/stat || return
      _folio_private_dir() {
        local directory="$1"
        local -A info
        [[ ! -L "$directory" ]] || return 1
        if [[ ! -d "$directory" ]]; then
          ( umask 077; command mkdir -p -- "$directory" ) || return 1
        fi
        [[ -d "$directory" && ! -L "$directory" && -O "$directory" ]] || return 1
        zstat -H info -- "$directory" || return 1
        if (( (info[mode] & 8#7777) != 8#700 )); then
          command chmod 700 -- "$directory" || return 1
          zstat -H info -- "$directory" || return 1
          (( (info[mode] & 8#7777) == 8#700 )) || return 1
        fi
      }
      typeset -g _folio_state_home="$HOME/.local/state"
      if [ -n "$XDG_STATE_HOME" ]; then _folio_state_home="$XDG_STATE_HOME"; fi
      typeset -g _folio_history_dir="$_folio_state_home/folio/zsh"
      _folio_private_dir "$_folio_history_dir" || { unfunction _folio_private_dir; return; }
      HISTFILE="$_folio_history_dir/history"
      HISTSIZE=${toString historySize}
      SAVEHIST=${toString historySave}
      setopt HIST_IGNORE_ALL_DUPS HIST_SAVE_NO_DUPS SHARE_HISTORY

      # Use a per-user cache directory for completion metadata.
      typeset -g _folio_cache_home="$HOME/.cache"
      if [ -n "$XDG_CACHE_HOME" ]; then _folio_cache_home="$XDG_CACHE_HOME"; fi
      _folio_private_dir "$_folio_cache_home/zsh" || { unfunction _folio_private_dir; return; }
      unfunction _folio_private_dir
      ${if completion then ''
        autoload -Uz compinit
        compinit -d "$_folio_cache_home/zsh/zcompdump"
      '' else ""}

      ${prompt}
      ${pluginSetup}
    '';

  renderPlugins = pkgs: settings:
    let
      theme = settings.theme or defaultTheme;
      p = theme.colors.palettes.${theme.colors.appearance or "dark"};
      color = key: p.${key} or p.fg;
      colors = {
        DIR_FOREGROUND = color "fg";
        DIR_PATH_SEPARATOR_FOREGROUND = color "grey1";
        DIR_PATH_HIGHLIGHT_FOREGROUND = color "yellow";
        VCS_FOREGROUND = color "green";
        VCS_INCOMING_CHANGESFORMAT_FOREGROUND = color "aqua";
        VCS_OUTGOING_CHANGESFORMAT_FOREGROUND = color "aqua";
        TIME_FOREGROUND = color "grey1";
        VIRTUALENV_FOREGROUND = color "aqua";
        COMMAND_EXECUTION_TIME_FOREGROUND = color "yellow";
        CONTEXT_FOREGROUND = color "grey1";
        PROMPT_CHAR_OK_VIINS_FOREGROUND = color "yellow";
        PROMPT_CHAR_OK_VICMD_FOREGROUND = color "yellow";
        PROMPT_CHAR_OK_VIVIS_FOREGROUND = color "yellow";
        PROMPT_CHAR_ERROR_VIINS_FOREGROUND = color "red";
        PROMPT_CHAR_ERROR_VICMD_FOREGROUND = color "red";
        PROMPT_CHAR_ERROR_VIVIS_FOREGROUND = color "red";
        CONTEXT_ROOT_TEMPLATE = "%F{${color "fg"}}%n%f%F{${color "grey1"}}@%m%f";
        CONTEXT_TEMPLATE = "%F{${color "grey1"}}%n@%m%f";
      };
    in pkgs.lib.optionalString (settings.promptStyle == "powerlevel10k") ''
      # Keep startup noninteractive; users may override these upstream variables.
      source ${../cli/resources/p10k.zsh}
      typeset -g POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
      ${pkgs.lib.concatStringsSep "\n" (pkgs.lib.mapAttrsToList
        (key: value: "typeset -g POWERLEVEL9K_${key}=${pkgs.lib.escapeShellArg value}") colors)}
      source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
    ''
    + pkgs.lib.optionalString settings.autosuggestions ''
      source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    ''
    + pkgs.lib.optionalString settings.syntaxHighlighting ''
      # Highlighting must follow prompt and widget definitions.
      source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    '';

in { inherit defaultTheme renderPrompt renderPlugins shellSetup; }
