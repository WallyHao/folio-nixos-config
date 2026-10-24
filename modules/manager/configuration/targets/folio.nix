# Installation-specific choices. Modules retain the implementation of each policy.
{ catalogue }:
{
  environment.system.users = [
    {
      name = "folio";
      uid = 1000;
      home = "/home/folio";
      groups = [
        "folio-operators"
        "kvm"
        "video"
        "wheel"
        "networkmanager"
      ];
      login-shell = "zsh";
    }
  ];
  environment.system.modules = [
    {
      name = "system";
      "folio-system:system" = {
        time-zone = "Asia/Shanghai";
        storage-profile = "physical";
        prototype-password = false;
        root-filesystem = "btrfs";
        root-device = "/dev/disk/by-uuid/4e59b522-0ecc-4bc7-b6d0-edc4531e4a00";
        boot-device = "/dev/disk/by-uuid/767D-8E97";
      };
    }
    {
      name = "network";
      "folio-network:network".proxy = {
        enabled = true;
        tun = true;
        provider-file = "/var/lib/folio-mihomo-private/provider.yaml";
      };
    }
  ];
  environment.user.modules = [
    {
      name = "agents";
      "folio-agents:agents".pi = {
        enabled = true;
        config-directory = "/home/folio/Workspace/folio-nixos-config/modules/agents/src/pi/config";
      };
    }
  ];
  modules = [
    catalogue.system.targetModules.folio
    catalogue.devices.targetModules.folio
    catalogue.network.targetModules.folio
  ];
}
