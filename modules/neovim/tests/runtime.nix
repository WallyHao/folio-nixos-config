{ pkgs, package }:
let
  themes = import ../../appearance/lib/catalogue.nix;
  settings =
    scheme: appearance:
    pkgs.writeText "neovim-${scheme}-${appearance}.json" (
      builtins.toJSON {
        inherit appearance;
        palette = themes.${scheme}.palettes.${appearance};
        accent = themes.${scheme}.palettes.${appearance}.${themes.${scheme}.roles.accent};
        notesDirectory = "~/Documents/documents";
      }
    );
in
pkgs.runCommand "folio-neovim-runtime" { nativeBuildInputs = [ package ]; } ''
  export HOME=$TMPDIR/home XDG_CONFIG_HOME=$TMPDIR/home/.config
  export XDG_STATE_HOME=$TMPDIR/home/.local/state XDG_DATA_HOME=$TMPDIR/home/.local/share
  export XDG_CACHE_HOME=$TMPDIR/home/.cache TERM=xterm-256color
  mkdir -p "$XDG_CONFIG_HOME/folio/neovim"
  ${pkgs.lib.concatMapStringsSep "\n"
    (
      scheme:
      pkgs.lib.concatMapStringsSep "\n"
        (appearance: ''
          cp --remove-destination ${settings scheme appearance} "$XDG_CONFIG_HOME/folio/neovim/settings.json"
          nvim --headless -i NONE '+lua dofile("${./smoke.lua}")' '+qa!'
        '')
        [
          "dark"
          "light"
        ]
    )
    [
      "everforest"
      "graphite"
    ]
  }
  FOLIO_TEST_LSP=1 nvim --headless -i NONE '+lua dofile("${./smoke.lua}")' '+qa!'
  mkdir $out
  printf 'Neovim startup, four palettes, search, syntax, formatting and Python LSP passed.\n' >$out/result
''
