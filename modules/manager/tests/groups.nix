# Execution groups reference existing checks; aliases remain public outputs.
let
  fast = [
    "catalogue"
    "foundation"
    "configuration"
    "manager-workflow"
    "manager-pending-upgrade"
    "panel-http"
    "applications-store"
    "network-proxy"
    "workspace-preparation"
    "appearance-contrast"
  ];
  integration = fast ++ [
    "neovim-runtime"
    "neovim-migration"
    "tools"
    "agents"
    "agents-colors"
    "agents-migration"
    "applications-native"
    "appearance-gtk"
    "appearance-themes"
    "desktop-focus-fade"
    "applications-browser-windows"
    "theme-migration"
    "panel-browser"
    "panel-network"
    "system-account-migration"
    "system-legacy-retirement-files"
    "isaac-runtime"
  ];
in
{
  inherit fast integration;
  release = integration ++ [
    "user-deployment"
    "system-scope"
    "system-deployment"
    "recovery"
    "network"
    "desktop"
    "tools-deployment"
    "applications"
    "legacy-retirement"
    "integrated-release"
  ];
}
