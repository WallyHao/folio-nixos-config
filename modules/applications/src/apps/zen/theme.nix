# Browser-owned chrome only; web documents keep their extension-managed theme.
{ theme }:
let
  ui = import ./palette.nix { inherit theme; };
  c = ui.colors;
in
''
  @-moz-document url-prefix("chrome://browser/content/"),
                 url-prefix("chrome://global/content/"),
                 url-prefix("chrome://mozapps/content/") {
    /* Panels, fields and modern controls redefine tokens locally in Zen. */
    :root, panel, menupopup, dialog, .dialogBox, #urlbar,
    .urlbar-background, moz-button, moz-input-box {
      ${ui.declarations}
      color-scheme: ${theme.colors.appearance} !important;
    }
    :root {
      --zen-main-browser-background: ${c.background} !important;
      --zen-main-browser-background-toolbar: ${c.background} !important;
      --zen-main-browser-background-old: ${c.background} !important;
      --zen-main-browser-background-toolbar-old: ${c.background} !important;
      --zen-themed-toolbar-bg-transparent: ${c.background} !important;
      --zen-navigator-toolbox-background: ${c.background} !important;
      --zen-background-opacity: 1 !important;
      --toolbox-textcolor: ${c.foreground} !important;
      --toolbar-bgcolor: ${c.background} !important;
      --tabpanel-background-color: ${c.background} !important;
      --sidebar-background-color: ${c.background} !important;
      --sidebar-text-color: ${c.foreground} !important;
      --tab-selected-bgcolor: ${c.selection} !important;
      --tab-background-color-selected: ${c.selection} !important;
      --tab-selected-textcolor: ${c.foreground} !important;
      --tab-background-color-hover: ${c.hover} !important;
      --toolbar-field-background-color: ${c.surface} !important;
      --toolbar-field-focus-background-color: ${c.surface} !important;
      --toolbar-field-color: ${c.foreground} !important;
      --toolbar-field-focus-color: ${c.foreground} !important;
      --toolbar-field-border-color: ${c.border} !important;
      --toolbar-field-focus-border-color: ${c.accent} !important;
      --lwt-text-color: ${c.foreground} !important;
      background-color: ${c.background} !important;
      color: ${c.foreground} !important;
    }
    #navigator-toolbox, #sidebar-box, #sidebar-main, .browserSidebarContainer,
    #zen-sidebar-web-panel, #zen-workspaces-button {
      background-color: ${c.background} !important;
      color: ${c.foreground} !important;
    }
    .zen-browser-generic-background,
    .zen-browser-generic-background::before,
    .zen-browser-generic-background::after,
    .zen-toolbar-background,
    .zen-toolbar-background::before,
    .zen-toolbar-background::after {
      background: ${c.background} !important;
      background-image: none !important;
      backdrop-filter: none !important;
    }
    .zen-browser-grain { display: none !important; }

    /* Backing surfaces remain visible before a remote document first paints. */
    #tabbrowser-tabbox, #tabbrowser-tabpanels, .browserStack,
    browser[type="content"] {
      background-color: ${c.background} !important;
    }

    panel::part(content), menupopup::part(content), .panel-viewstack,
    panelview, .dialogBox, dialog {
      background: ${c.surface} !important;
      color: ${c.foreground} !important;
      border-color: ${c.border} !important;
    }
    menupopup { appearance: none !important; }
    menu, menuitem, .subviewbutton {
      color: ${c.foreground} !important;
    }
    menu[disabled="true"], menuitem[disabled="true"], .subviewbutton[disabled] {
      color: ${c.muted} !important;
    }
    menu[_moz-menuactive="true"], menuitem[_moz-menuactive="true"],
    .subviewbutton:not([disabled]):hover {
      background-color: ${c.hover} !important;
      color: ${c.foreground} !important;
    }
    .urlbar-background, #urlbar-background {
      --zen-urlbar-background: ${c.surface} !important;
      --zen-urlbar-background-base: ${c.surface} !important;
      --zen-urlbar-background-transparent: ${c.surface} !important;
      --zen-urlbar-filter: none !important;
      background: ${c.surface} !important;
      backdrop-filter: none !important;
      border-color: ${c.border} !important;
    }
    #urlbar-input, .urlbarView-row, .urlbarView-title {
      color: ${c.foreground} !important;
    }
    .urlbarView-url, .urlbarView-action { color: ${c.info} !important; }
    .urlbarView-row:hover { background-color: ${c.hover} !important; }
    .urlbarView-row[selected], .urlbarView-row[selected] .urlbarView-row-inner,
    #urlbar-search-mode-indicator, #urlbar-label-box {
      background-color: ${c.selection} !important;
      color: ${c.foreground} !important;
    }
    .urlbarView-row[selected] *, .urlbarView-row[selected] .urlbarView-shortcutContent {
      color: ${c.foreground} !important;
    }
    .urlbarView-shortcutContent { background-color: ${c.hover} !important; }
    .tabbrowser-tab {
      --zen-essential-tab-selected-bg: ${c.selection} !important;
      --zen-essential-tab-hover-bg: ${c.hover} !important;
      color: ${c.foreground} !important;
    }
    .tabbrowser-tab:hover .tab-background { background-color: ${c.hover} !important; }
    .tabbrowser-tab:is([visuallyselected], [selected="true"], [multiselected="true"]) .tab-background,
    .tabbrowser-tab[zen-essential]:is([visuallyselected], [selected="true"]) .tab-background::before {
      background: ${c.selection} !important;
    }
    .tabbrowser-tab:is([visuallyselected], [selected="true"]) .tab-label {
      color: ${c.foreground} !important;
    }
    ::selection { background-color: ${c.selection} !important; color: ${c.foreground} !important; }
  }
''
