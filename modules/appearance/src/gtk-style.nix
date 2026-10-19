{ theme }:
let
  p = theme.colors.palettes.${theme.colors.appearance};
  css = ''
    @define-color accent_color ${p.yellow};
    @define-color accent_bg_color ${p.yellow};
    @define-color accent_fg_color ${p.bg0};
    @define-color window_bg_color ${p.bg0};
    @define-color window_fg_color ${p.fg};
    @define-color view_bg_color ${p.bg0};
    @define-color view_fg_color ${p.fg};
    @define-color headerbar_bg_color ${p.bg0};
    @define-color headerbar_fg_color ${p.fg};
    @define-color sidebar_bg_color ${p.bg1};
    @define-color sidebar_fg_color ${p.fg};
    @define-color card_bg_color ${p.bg1};
    @define-color card_fg_color ${p.fg};
    @define-color dialog_bg_color ${p.bg0};
    @define-color dialog_fg_color ${p.fg};
    @define-color popover_bg_color ${p.bg1};
    @define-color popover_fg_color ${p.fg};
    @define-color borders ${p.grey0};
    @define-color theme_bg_color ${p.bg0};
    @define-color theme_fg_color ${p.fg};
    @define-color theme_base_color ${p.bg0};
    @define-color theme_text_color ${p.fg};
    @define-color theme_selected_bg_color ${p.yellow};
    @define-color theme_selected_fg_color ${p.bg0};
    @define-color theme_unfocused_bg_color ${p.bg0};
    @define-color theme_unfocused_fg_color ${p.grey1 or p.fg};
    window, window.background, headerbar, .titlebar, popover,
    menu, tooltip, dialog, messagedialog, decoration { border-radius: 0; }
    /* Niri owns the focus highlight; avoid duplicate client-side borders. */
    decoration, window.csd { border: none; box-shadow: none; }
  '';
in css
