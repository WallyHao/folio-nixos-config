# Adapted from Sylphy's local socket, loopback listener and credential provider policy.
{
  pkgs,
  lib,
  proxy,
}:
let
  enabled = proxy.enabled or false;
  tun = proxy.tun or false;
  provider = proxy.provider-file or null;
  dns =
    proxy.dns or [
      "119.29.29.29"
      "223.5.5.5"
    ];
  config = pkgs.writeText "folio-mihomo.json" (
    builtins.toJSON (
      {
        mixed-port = proxy.port or 7890;
        allow-lan = false;
        bind-address = "127.0.0.1";
        external-controller-unix = "/run/folio-mihomo/controller.sock";
        mode = proxy.mode or "rule";
        log-level = "info";
        ipv6 = false;
        profile.store-selected = true;
        proxy-groups = [
          (
            {
              name = "PROXY";
              type = "select";
              proxies = [ "DIRECT" ];
            }
            // lib.optionalAttrs (provider != null) { use = [ "runtime" ]; }
          )
        ];
        rules = [
          "DST-PORT,123,DIRECT"
          "MATCH,PROXY"
        ];
        tun = {
          enable = tun;
          device = "folio-mihomo";
          stack = "mixed";
          auto-route = tun;
          auto-detect-interface = tun;
          dns-hijack = lib.optional tun "any:53";
          iproute2-table-index = 2022;
          iproute2-rule-index = 9000;
        };
      }
      // lib.optionalAttrs (provider != null) {
        proxy-providers.runtime = {
          type = "file";
          path = "/run/credentials/folio-mihomo.service/provider.yaml";
        };
      }
      // lib.optionalAttrs tun {
        dns = {
          enable = true;
          listen = "127.0.0.1:1053";
          enhanced-mode = "fake-ip";
          fake-ip-range = "198.18.0.1/16";
          fake-ip-filter = [
            "ntp.aliyun.com"
            "ntp.tencent.com"
            "+.ntp.org"
          ];
          default-nameserver = dns;
          nameserver = dns;
        };
      }
    )
  );
in
{
  boot.kernelModules = lib.optional (enabled && tun) "tun";
  users.groups.folio-mihomo = lib.mkIf enabled { };
  users.users.folio-mihomo = lib.mkIf enabled {
    isSystemUser = true;
    group = "folio-mihomo";
  };
  systemd.services.folio-mihomo = lib.mkIf enabled {
    description = "Folio local Mihomo proxy";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      User = "folio-mihomo";
      Group = "folio-mihomo";
      StateDirectory = "folio-mihomo";
      StateDirectoryMode = "0700";
      RuntimeDirectory = "folio-mihomo";
      RuntimeDirectoryMode = "0700";
      ExecStart = "${pkgs.mihomo}/bin/mihomo -d /var/lib/folio-mihomo -f ${config}";
      LoadCredential = lib.optional (provider != null) "provider.yaml:${provider}";
      Environment = "SAFE_PATHS=/run/credentials/folio-mihomo.service";
      AmbientCapabilities = lib.optional tun "CAP_NET_ADMIN";
      CapabilityBoundingSet = lib.optional tun "CAP_NET_ADMIN";
      DeviceAllow = lib.optional tun "/dev/net/tun rw";
      PrivateDevices = !tun;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ]
      ++ lib.optional tun "AF_NETLINK";
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
  networking.firewall = lib.mkIf (enabled && tun) {
    checkReversePath = "loose";
    trustedInterfaces = [ "folio-mihomo" ];
  };
}
