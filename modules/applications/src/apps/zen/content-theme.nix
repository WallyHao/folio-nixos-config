# Strict allowlist: never apply browser UI styles to websites or extensions.
{ theme }:
let
  ui = import ./palette.nix { inherit theme; };
  c = ui.colors;
in
''
  @-moz-document url-prefix("about:preferences"), url-prefix("about:addons"),
                 url-prefix("about:config"), url-prefix("about:downloads"),
                 url-prefix("about:profiles"), url-prefix("about:logins"),
                 url("about:home"), url("about:newtab"), url("about:blank") {
    :root, body, dialog, .dialogBox, panel, menupopup, moz-button, moz-input-box {
      ${ui.declarations}
      color-scheme: ${theme.colors.appearance} !important;
    }
    :root, body, .main-content, #categories, #sidebar, .navigation {
      background-color: ${c.background} !important;
      color: ${c.foreground} !important;
    }
    .card, .addon.card, .dialogBox, dialog, .section-main, .logins-list {
      background-color: ${c.surface} !important;
      color: ${c.foreground} !important;
      border-color: ${c.border} !important;
    }
    #categories > .category[selected], .category[selected="true"],
    .category[selected="true"] .category-name {
      background-color: ${c.selection} !important;
      color: ${c.foreground} !important;
    }
    ::selection { background-color: ${c.selection} !important; color: ${c.foreground} !important; }
  }
''
