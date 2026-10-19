{ pkgs, lib, packages }:
context:
let
  settings = context.settings."folio-network:network" or { };
  firewall = settings.firewall or { };
  ssh = settings.ssh or { };
  proxy = settings.proxy or { };
in {
  imports = [ (import ./mihomo.nix { inherit pkgs lib proxy; }) ];
  networking = {
    useDHCP = false;
    dhcpcd.enable = false;
    resolvconf.enable = false;
    networkmanager = {
      enable = true;
      dns = "default";
      settings = {
        main.rc-manager = "file";
        connection."wifi.powersave" = { default = 0; ignore = 1; disable = 2; enable = 3; }.${settings.wifi-powersave or "disable"};
      } // lib.optionalAttrs ((settings.dns or [ ]) != [ ]) {
        "global-dns-domain-*".servers = lib.concatStringsSep "," settings.dns;
      };
    };
    firewall = {
      enable = firewall.enabled or true;
      allowPing = firewall.allow-ping or true;
      allowedTCPPorts = firewall.tcp-ports or [ ];
      allowedUDPPorts = firewall.udp-ports or [ ];
    };
  };
  services.resolved.enable = false;
  systemd.services.NetworkManager-wait-online.enable = settings.wait-online or false;
  services.openssh = lib.mkIf (ssh.enabled or false) {
    enable = true;
    ports = [ (ssh.port or 2222) ];
    openFirewall = ssh.open-firewall or false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      # Public keys are provisioned on the target, outside desired/build data.
      AuthorizedKeysFile = ".ssh/authorized_keys /run/folio/authorized_keys/%u";
    };
  };
  environment.systemPackages = [ pkgs.networkmanager ];
  systemd.services.folio-network = {
    description = "Folio system network observations and bounded controls";
    wantedBy = [ "multi-user.target" ];
    after = [ "folio-manager.service" "NetworkManager.service" ];
    requires = [ "folio-manager.service" ];
    serviceConfig = {
      User = "root"; Group = "folio-operators";
      RuntimeDirectory = "folio/network"; RuntimeDirectoryMode = "0700";
      RuntimeDirectoryPreserve = true;
      ExecStart = "${packages.subscriber}/bin/folio-network-subscriber";
      Restart = "on-failure"; RestartSec = 2; UMask = "0077";
    };
  };
}
