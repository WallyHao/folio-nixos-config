{ pkgs, lib }:
let
  theme = import ../../appearance/lib { };
  runtime = lib.fileset.toSource {
    root = ./.;
    fileset = ./lua;
  };
  defaults = builtins.toJSON {
    inherit (theme) palette appearance;
    accent = theme.semantic.accent;
    notesDirectory = "~/Documents/documents";
  };
  tools = with pkgs; [
    ripgrep
    fd
    gitMinimal
    wl-clipboard
    nixd
    lua-language-server
    pyright
    bash-language-server
    vscode-langservers-extracted
    yaml-language-server
    typescript-language-server
    nixfmt
    stylua
    ruff
    shfmt
    prettier
  ];
in
pkgs.wrapNeovimUnstable pkgs.neovim-unwrapped {
  viAlias = true;
  vimAlias = true;
  withRuby = false;
  withPython3 = false;
  withNodeJs = false;
  plugins = with pkgs.vimPlugins; [
    plenary-nvim
    telescope-nvim
    nvim-web-devicons
    lualine-nvim
    gitsigns-nvim
    nvim-lspconfig
    nvim-cmp
    cmp-nvim-lsp
    cmp-buffer
    cmp-path
    luasnip
    cmp_luasnip
    nvim-autopairs
    which-key-nvim
    conform-nvim
    (nvim-treesitter.withPlugins (
      grammars: with grammars; [
        bash
        c
        cpp
        css
        html
        javascript
        json
        lua
        markdown
        markdown_inline
        nix
        python
        regex
        rust
        toml
        tsx
        typescript
        vim
        vimdoc
        yaml
      ]
    ))
  ];
  wrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath tools)
  ];
  luaRcContent = ''
    vim.opt.runtimepath:prepend(${builtins.toJSON "${runtime}"})
    require("folio").setup(vim.json.decode(${builtins.toJSON defaults}))
  '';
}
