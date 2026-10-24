# The root check composition copies its shared system-update guest instrumentation
# to guest-base.nix inside the frozen fixture; production never imports this file.
{ pkgs, lib, ... }: {
  imports = [ ./guest-base.nix ];
  networking.networkmanager.settings.connectivity.enabled = false;
  services.greetd.enable = lib.mkForce false;
  environment.systemPackages = [
    pkgs.jq
    pkgs.curl
    pkgs.iproute2
    pkgs.iptables
    pkgs.openssh
    pkgs.python3
    pkgs.dnsmasq
  ];
  virtualisation = {
    memorySize = lib.mkForce 4096;
    cores = lib.mkForce 2;
    diskSize = 16384;
  };
}
