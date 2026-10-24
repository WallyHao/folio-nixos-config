{ app, ... }:
{
  inherit (app) name;
  selected = app.selected or true;
  profile = null;
  files = [ ];
  unsupported = [
    "OBS appearance remains application-owned; GTK does not establish Qt theme parity"
  ];
}
