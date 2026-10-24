# Shared browser UI tokens. Import only inside browser-owned document scopes.
{ theme }:
let
  palette = theme.colors.palettes.${theme.colors.appearance};
  role = name: palette.${theme.colors.roles.${name}};
  colors = {
    background = role "background";
    surface = role "surface";
    foreground = role "foreground";
    accent = role "accent";
    selection = role "selection";
    border = role "border";
    muted = role "muted";
    hover = palette.bg2;
    active = palette.bg3;
    error = role "error";
    warning = role "warning";
    success = role "success";
    info = role "info";
  };
  groups = with colors; [
    {
      value = background;
      names = [
        "background-color-canvas"
        "in-content-page-background"
        "zen-colors-tertiary"
        "zen-dialog-background"
        "zen-branding-bg"
      ];
    }
    {
      value = surface;
      names = [
        "background-color-box"
        "background-color-menu"
        "arrowpanel-background"
        "panel-background"
        "panel-background-color"
        "in-content-box-background"
        "in-content-button-background"
        "button-background-color"
        "input-background-color"
        "input-text-background-color"
        "zen-colors-primary"
        "zen-colors-secondary"
        "zen-colors-input-bg"
        "zen-toolbar-element-bg"
        "zen-in-content-dialog-background"
      ];
    }
    {
      value = foreground;
      names = [
        "text-color"
        "in-content-page-color"
        "in-content-text-color"
        "in-content-button-text-color"
        "button-text-color"
        "input-color"
        "input-text-color"
        "arrowpanel-color"
        "panel-color"
        "panel-text-color"
        "zen-colors-primary-foreground"
        "toolbar-color"
        "zen-branding-bg-reverse"
      ];
    }
    {
      value = muted;
      names = [
        "text-color-deemphasized"
        "text-color-disabled"
        "input-text-color-disabled"
      ];
    }
    {
      value = hover;
      names = [
        "button-background-color-hover"
        "in-content-button-background-hover"
        "toolbarbutton-background-color-hover"
        "zen-toolbar-element-bg-hover"
        "zen-colors-hover-bg"
        "background-color-dimmed"
      ];
    }
    {
      value = active;
      names = [
        "button-background-color-active"
        "in-content-button-background-active"
        "toolbarbutton-background-color-active"
        "background-color-dimmed-further"
      ];
    }
    {
      value = border;
      names = [
        "border-color"
        "border-color-deemphasized"
        "border-color-interactive"
        "input-border-color"
        "input-text-border-color"
        "zen-input-border-color"
        "zen-colors-border"
        "arrowpanel-border-color"
        "panel-border-color"
        "panel-separator-color"
        "in-content-box-border-color"
      ];
    }
    {
      value = accent;
      names = [
        "color-accent-primary"
        "color-accent-primary-hover"
        "color-accent-primary-active"
        "zen-primary-color"
        "focus-outline-color"
        "in-content-primary-button-background"
        "in-content-primary-button-background-hover"
        "in-content-primary-button-background-active"
        "button-background-color-primary"
        "button-background-color-primary-hover"
        "button-background-color-primary-active"
        "button-primary-hover-bgcolor"
        "button-primary-active-bgcolor"
      ];
    }
    {
      value = background;
      names = [
        "color-accent-primary-contrast"
        "in-content-primary-button-text-color"
        "button-text-color-primary"
        "button-primary-color"
      ];
    }
    {
      value = selection;
      names = [
        "background-color-selected"
        "in-content-item-selected"
        "zen-selected-bg"
      ];
    }
    {
      value = foreground;
      names = [
        "text-color-selected"
        "in-content-item-selected-text"
        "zen-selected-color"
      ];
    }
    {
      value = info;
      names = [
        "link-color"
        "link-color-hover"
        "link-color-active"
        "link-color-visited"
        "in-content-link-color"
        "in-content-link-color-hover"
        "in-content-link-color-active"
      ];
    }
    {
      value = error;
      names = [
        "text-color-error"
        "border-color-error"
        "button-background-color-destructive"
      ];
    }
    {
      value = background;
      names = [ "button-text-color-destructive" ];
    }
    {
      value = palette.bg_red;
      names = [ "background-color-critical" ];
    }
    {
      value = palette.bg_yellow;
      names = [ "background-color-warning" ];
    }
    {
      value = palette.bg_green;
      names = [ "background-color-success" ];
    }
    {
      value = palette.bg_blue;
      names = [ "background-color-information" ];
    }
  ];
  declarations = builtins.concatStringsSep "\n" (
    builtins.concatMap (group: map (name: "--${name}: ${group.value} !important;") group.names) groups
  );
in
assert builtins.all (
  value: builtins.isString value && builtins.match "#[0-9a-fA-F]{6}" value != null
) (builtins.attrValues colors);
{
  inherit colors declarations;
}
