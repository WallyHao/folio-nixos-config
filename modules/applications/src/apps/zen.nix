{ pkgs, lib, context, app }:
let
  colors = context.theme or (import ../../../appearance/lib { preferences = context.globals; });
  theme.colors = colors // { appearance = context.globals.appearance; };
  palette = import ./zen/palette.nix { inherit theme; };
  preferences = {
    "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
    "zen.view.grey-out-inactive-windows" = false;
    "browser.theme.content-theme" = if context.globals.appearance == "dark" then 0 else 1;
    "layout.css.prefers-color-scheme.content-override" = if context.globals.appearance == "dark" then 0 else 1;
    "browser.display.use_system_colors" = false;
    "browser.display.background_color" = palette.colors.background;
    "browser.display.background_color.dark" = palette.colors.background;
    "browser.display.foreground_color" = palette.colors.foreground;
    "browser.display.foreground_color.dark" = palette.colors.foreground;
  };
  # Adapted from Sylphy browser preferences and browser-owned CSS scopes at
  # 9cba023d90c4485b33a91e2d12724b6920580580. No browser profile data is copied.
  userJs = lib.concatStringsSep "\n" (lib.mapAttrsToList (
    name: value: "user_pref(${builtins.toJSON name}, ${builtins.toJSON value});"
  ) preferences) + "\n";
  resource = destination: mode: text: {
    inherit destination mode;
    source = toString (pkgs.writeText "folio-browser-${builtins.baseNameOf destination}" text);
    sha256 = builtins.hashString "sha256" text;
  };
in
{
    inherit (app) name;
    selected = app.selected or true;
    profile = app.zen-profile or null;
    files = lib.optionals (app.name == "zen" && (app.selected or true)) [
      (resource "user.js" "replace" userJs)
      (resource "chrome/folio/ui.css" "replace" (import ./zen/theme.nix { inherit theme; }))
      (resource "chrome/folio/content.css" "replace" (import ./zen/content-theme.nix { inherit theme; }))
      (resource "chrome/userChrome.css" "include" "/* Folio managed include. */\n@import url(\"folio/ui.css\");\n")
      (resource "chrome/userContent.css" "include" "/* Folio managed include. */\n@import url(\"folio/content.css\");\n")
    ];
    unsupported = [ "Workspace seeding requires a supported Zen API; mutable workspace files are not overwritten" ];
  }
