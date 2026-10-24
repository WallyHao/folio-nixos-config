{ pkgs, runtime }:
folioBootstrap: {
  ExecStartPre = "${pkgs.folio.repository}/bin/folio-repository user init ${folioBootstrap}/models/user ${folioBootstrap}/user.json";
  ExecStart = "${runtime}/bin/folio-manager-subscriber user ${folioBootstrap}";
  Restart = "on-failure";
  RestartSec = 2;
  TimeoutStopSec = 5;
  UMask = "0077";
}
