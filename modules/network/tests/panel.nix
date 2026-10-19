{ pkgs, bootstrap, repository, subscriber, wifi, devices, panel }:
pkgs.testers.runNixOSTest {
  name = "folio-panel-native-controls";
  nodes.machine = { lib, ... }: {
    virtualisation = { memorySize = 2048; cores = 2; };
    boot.kernelModules = [ "mac80211_hwsim" ];
    networking.usePredictableInterfaceNames = false;
    networking.firewall.interfaces.wlan1.allowedUDPPorts = [ 67 ];
    # qemu-vm disables wireless at priority 10; this fixture explicitly needs it.
    networking.wireless = { enable = lib.mkOverride 0 true; dbusControlled = true; };
    networking.networkmanager = {
      enable = true;
      settings.keyfile.unmanaged-devices = "interface-name:wlan1";
    };
    users.groups.folio-operators = { };
    users.users.folio = {
      isNormalUser = true; uid = 1000; linger = true;
      extraGroups = [ "networkmanager" "folio-operators" ];
    };
    security.polkit.enable = true;
    # Disposable fixture authorization only; production retains native policy.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (subject.user === "folio" && action.id.indexOf("org.freedesktop.NetworkManager.") === 0)
          return polkit.Result.YES;
      });
    '';
    services.pipewire = { enable = true; pulse.enable = true; };
    environment.systemPackages = [ wifi devices panel repository pkgs.hostapd pkgs.iw
      pkgs.jq pkgs.pulseaudio pkgs.wireplumber pkgs.iptables pkgs.dnsmasq ];
    systemd.services.folio-network = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = "root";
        Group = "folio-operators";
        StateDirectory = "folio";
        StateDirectoryMode = "0750";
        UMask = "0007";
        RuntimeDirectory = "folio/network";
        ExecStartPre = "${repository}/bin/folio-repository system init ${bootstrap}/models/system ${bootstrap}/system.json";
        ExecStart = "${subscriber}/bin/folio-network-subscriber";
      };
    };
    systemd.services.folio-mihomo = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        RuntimeDirectory = "folio-mihomo";
        StateDirectory = "folio-mihomo";
        ExecStart = "${pkgs.mihomo}/bin/mihomo -d /var/lib/folio-mihomo -f ${pkgs.writeText "folio-proxy-fixture.json" (builtins.toJSON {
          mixed-port = 7890; allow-lan = false;
          external-controller-unix = "/run/folio-mihomo/controller.sock";
          proxy-groups = [{ name = "PROXY"; type = "select"; proxies = [ "DIRECT" "REJECT" ]; }];
          rules = [ "MATCH,PROXY" ];
        })}";
      };
    };
  };
  testScript = builtins.replaceStrings
    [ "@wifi@" "@devices@" "@panel@" "@python@" ]
    [ "${wifi}/bin/folio-network-wifi" "${devices}/bin/folio-devices-panel" "${panel}" "${pkgs.python3}/bin/python3" ]
    (builtins.readFile ./panel.py);
}
