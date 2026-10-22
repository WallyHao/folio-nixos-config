{ theme }:
let
  p = theme.colors.palettes.${theme.colors.appearance};
  accent = p.${theme.colors.roles.accent};
  css = ''
    @define-color accent_color ${accent};
    @define-color accent_bg_color ${accent};
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
    @define-color success_color ${p.green};
    @define-color warning_color ${p.yellow};
    @define-color error_color ${p.red};
    @define-color destructive_color ${p.red};
    @define-color destructive_bg_color ${p.red};
    @define-color destructive_fg_color ${p.bg0};
    @define-color theme_bg_color ${p.bg0};
    @define-color theme_fg_color ${p.fg};
    @define-color theme_base_color ${p.bg0};
    @define-color theme_text_color ${p.fg};
    @define-color theme_selected_bg_color ${accent};
    @define-color theme_selected_fg_color ${p.bg0};
    @define-color theme_unfocused_bg_color ${p.bg0};
    @define-color theme_unfocused_fg_color ${p.grey1 or p.fg};
    window {
      font-family: ${builtins.toJSON theme.font-family};
      font-size: ${toString theme.font-size}pt;
    }
    window, window.background, headerbar, .titlebar, popover,
    menu, tooltip, dialog, messagedialog, decoration { border-radius: 0; }
    /* Niri owns the focus highlight; avoid duplicate client-side borders. */
    decoration, window.csd { border: none; box-shadow: none; }
  '';
in {
  gtk3 = css;
  # Since libadwaita 1.6, named colors alone no longer recolor its widgets.
  # Keep this separate: GTK 3 cannot parse CSS custom properties.
  gtk4 = css + ''
    :root {
      --accent-color: ${accent};
      --accent-bg-color: ${accent};
      --accent-fg-color: ${p.bg0};
      --window-bg-color: ${p.bg0};
      --window-fg-color: ${p.fg};
      --view-bg-color: ${p.bg0};
      --view-fg-color: ${p.fg};
      --headerbar-bg-color: ${p.bg0};
      --headerbar-fg-color: ${p.fg};
      --headerbar-backdrop-color: ${p.bg0};
      --headerbar-shade-color: transparent;
      --headerbar-darker-shade-color: transparent;
      --sidebar-bg-color: ${p.bg1};
      --sidebar-fg-color: ${p.fg};
      --sidebar-backdrop-color: ${p.bg1};
      --secondary-sidebar-bg-color: ${p.bg1};
      --secondary-sidebar-fg-color: ${p.fg};
      --secondary-sidebar-backdrop-color: ${p.bg1};
      --card-bg-color: ${p.bg1};
      --card-fg-color: ${p.fg};
      --dialog-bg-color: ${p.bg0};
      --dialog-fg-color: ${p.fg};
      --popover-bg-color: ${p.bg1};
      --popover-fg-color: ${p.fg};
      --thumbnail-bg-color: ${p.bg1};
      --thumbnail-fg-color: ${p.fg};
      --destructive-color: ${p.red};
      --destructive-bg-color: ${p.red};
      --destructive-fg-color: ${p.bg0};
      --success-color: ${p.green};
      --warning-color: ${p.yellow};
      --error-color: ${p.red};
      font-family: ${builtins.toJSON theme.font-family};
      font-size: ${toString theme.font-size}pt;
    }
  '';
}
