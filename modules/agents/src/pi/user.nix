{
  pkgs,
  lib,
  package,
}:
context:
{ config, ... }:
let
  directory = context.settings.pi.config-directory or null;
in
{
  home.packages = [ package ];
  xdg.configFile."folio/pi".source =
    if directory == null then ./config else config.lib.file.mkOutOfStoreSymlink directory;
}
