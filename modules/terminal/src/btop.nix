# Everforest mapping adapted from Sylphy's btop theme renderer.
{ lib, palette }:
let
  p = palette;
  colors = {
    main_bg = p.bg0; main_fg = p.fg; title = p.yellow; hi_fg = p.yellow;
    selected_bg = p.bg1; selected_fg = p.fg; inactive_fg = p.grey0;
    graph_text = p.fg; meter_bg = p.bg2; proc_misc = p.aqua;
    cpu_box = p.grey0; mem_box = p.grey0; net_box = p.grey0;
    proc_box = p.grey0; div_line = p.grey0;
    temp_start = p.green; temp_mid = p.yellow; temp_end = p.red;
    cpu_start = p.green; cpu_mid = p.red; cpu_end = p.fg;
    free_start = p.bg1; free_mid = p.grey0; free_end = p.green;
    cached_start = p.bg1; cached_mid = p.grey0; cached_end = p.yellow;
    available_start = p.bg1; available_mid = p.green; available_end = p.aqua;
    used_start = p.yellow; used_mid = p.red; used_end = p.fg;
    download_start = p.bg1; download_mid = p.green; download_end = p.aqua;
    upload_start = p.bg1; upload_mid = p.grey0; upload_end = p.yellow;
    process_start = p.green; process_mid = p.aqua; process_end = p.blue;
  };
in lib.concatStringsSep "\n" (lib.mapAttrsToList (key: value:
  if builtins.match "#[0-9A-Fa-f]{6}" value == null
  then throw "folio-terminal: btop colors must be six-digit hexadecimal values"
  else ''theme[${key}]="${value}"'') colors) + "\n"
