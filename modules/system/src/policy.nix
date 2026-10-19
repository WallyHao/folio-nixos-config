# Adapted from Sylphy locale/time/TTY/journald/zram/Nix policy at 9cba023d90c4485b.
{ context }:
{ pkgs, ... }:
let
  settings = context.settings."folio-system:system" or { };
  sync = settings.time-sync or { };
  journal = settings.journal or { };
  zram = settings.zram or { };
  nix = settings.nix or { };
  colors = builtins.fromJSON (builtins.readFile ./colors.json);
  palette = colors.palettes.${context.globals.appearance};
in {
  time.timeZone = settings.time-zone or "Asia/Shanghai";
  i18n.defaultLocale = settings.locale or "en_US.UTF-8";
  console = {
    keyMap = settings.console-keymap or "us";
    font = "${pkgs.terminus_font}/share/consolefonts/ter-v${settings.console-font-size or "24"}n.psf.gz";
    earlySetup = true;
    colors = map (name: builtins.substring 1 6 palette.${name}) [
      "bg0" "red" "green" "yellow" "blue" "purple" "aqua" "fg"
      "grey0" "red" "green" "yellow" "blue" "purple" "aqua" "fg"
    ];
  };
  services.timesyncd = {
    enable = sync.enabled or true;
    servers = sync.servers or [ "ntp.aliyun.com" "ntp.tencent.com" ];
    fallbackServers = [ ];
  };
  services.journald.settings.Journal = {
    Storage = journal.storage or "auto";
    SystemMaxUse = "${toString (journal.max-disk-mib or 256)}M";
    RuntimeMaxUse = "${toString (journal.max-runtime-mib or 64)}M";
    RateLimitIntervalSec = "30s";
    RateLimitBurst = 10000;
  };
  zramSwap = { enable = zram.enabled or true; memoryPercent = zram.memory-percent or 25; algorithm = "zstd"; priority = 5; };
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    connect-timeout = 10; download-attempts = 3; fallback = true;
    max-jobs = nix.max-jobs or 1;
    auto-optimise-store = nix.auto-optimise or false;
    keep-outputs = true; keep-derivations = true;
  };
  # Retained deployment closures have explicit roots. Collection remains an
  # explicit manager operation; no competing generation-deletion timer is added.
  nix.gc.automatic = false;
}
