{
  pkgs,
  generation,
  editor,
}:
pkgs.runCommand "folio-developer-tools"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.zsh
      pkgs.jq
      pkgs.python3
    ];
  }
  ''
    export HOME=$TMPDIR/home XDG_CONFIG_HOME=$TMPDIR/home/.config
    export XDG_STATE_HOME=$TMPDIR/home/.local/state XDG_CACHE_HOME=$TMPDIR/home/.cache
    export TERM=xterm-256color
    mkdir -p "$HOME" "$XDG_CONFIG_HOME"
    # Exercise the actual generated user files without activating on the builder.
    cp -RL ${generation}/home-files/. "$HOME/"
    chmod -R u+w "$HOME"
    # Relocate the generated absolute history path for this unprivileged builder;
    # the guest gate separately exercises /home/folio without relocation.
    for startup in "$HOME/.zshenv" "$HOME"/.config/zsh/.zsh*; do
      test ! -f "$startup" || substituteInPlace "$startup" --replace '/home/folio' "$HOME"
    done
    zsh -i -c '[[ -n "$HISTFILE" ]] && (( $+functions[compdef] )) && (( $+functions[ll] ))'
    env EDITOR=old-editor VISUAL=old-editor __HM_SESS_VARS_SOURCED=1 zsh -c \
      '[[ "$EDITOR" == "${editor}/bin/nvim" && "$VISUAL" == "$EDITOR" ]]'
    test "$(stat -c %a "$XDG_STATE_HOME/folio/zsh")" = 700
    test "$(stat -c %a "$XDG_CACHE_HOME/zsh")" = 700
    git config --global --get init.defaultBranch | ${pkgs.gnugrep}/bin/grep -x main
    test -z "$(git config --global --get user.email || true)"
    git init "$TMPDIR/repository"
    git -C "$TMPDIR/repository" symbolic-ref HEAD | ${pkgs.gnugrep}/bin/grep refs/heads/main
    ${generation}/home-path/bin/codex --version
    ${generation}/home-path/bin/codex completion zsh >$TMPDIR/codex-completion
    test -s "$TMPDIR/codex-completion"
    python3 - <<'PY'
    import json, os, pathlib, plistlib
    appearance = json.loads((pathlib.Path(os.environ["XDG_CONFIG_HOME"])/"folio/appearance.json").read_text())
    palette = appearance["palette"]
    assert appearance["cursor-size"] == 42
    accent = palette[appearance["roles"]["accent"]]
    niri = (pathlib.Path(os.environ["XDG_CONFIG_HOME"])/"niri/config.kdl").read_text()
    assert 'Super+Y hotkey-overlay-title="Open Yazi"' in niri
    assert 'Super+W hotkey-overlay-title="Open browser"' in niri
    assert '"-e" "yazi"' in niri
    assert '-folio-browser"' in niri
    theme = pathlib.Path(os.environ['HOME'])/'.codex/themes/folio.tmTheme'
    assert plistlib.loads(theme.read_bytes())['settings']
    assert not (theme.parent.parent/'auth.json').exists()
    assert not (theme.parent.parent/'config.toml').exists()
    btop = pathlib.Path(os.environ['XDG_CONFIG_HOME'])/'btop'
    assert 'color_theme = "folio"' in (btop/'btop.conf').read_text()
    assert f'theme[main_bg]="{palette["bg0"]}"' in (btop/'themes/folio.theme').read_text()
    assert f'theme[title]="{palette["yellow"]}"' in (btop/'themes/folio.theme').read_text()
    import tomllib
    yazi = tomllib.loads((pathlib.Path(os.environ['XDG_CONFIG_HOME'])/'yazi/yazi.toml').read_text())
    assert yazi['mgr']['sort_by'] == 'natural'
    assert any(rule.get('mime') == 'application/pdf' and rule['use'] == 'open'
               for rule in yazi['open']['prepend_rules'])
    assert any(rule.get('url') == '*.md' and rule['use'] == 'edit'
               for rule in yazi['open']['prepend_rules'])
    assert any(rule.get('mime') == 'image/*' and rule['use'] == 'open'
               for rule in yazi['open']['prepend_rules'])
    yazi_theme = tomllib.loads((pathlib.Path(os.environ['XDG_CONFIG_HOME'])/'yazi/theme.toml').read_text())
    assert yazi_theme['app']['overall']['bg'] == palette['bg0']
    assert yazi_theme['indicator']['current']['bg'] == palette['bg_visual']
    assert yazi_theme['tabs']['active']['bg'] == palette['green']
    icons = yazi_theme['icon']
    assert all(rule['fg'] == accent for rules in icons.values() for rule in rules)
    assert any(rule['name'] == 'Downloads' for rule in icons['dirs'])
    assert any(rule['name'] == 'rs' for rule in icons['exts'])
    PY
    ${editor}/bin/nvim --headless -i NONE '+lua dofile("${../../neovim/tests/smoke.lua}")' '+qa!'
    mkdir $out
    cp "$HOME/.config/folio/neovim/settings.json" $out/editor-settings.json
    printf 'Shell, Git, Codex packaging/theme and Neovim behavior passed.\n' >$out/result
  ''
