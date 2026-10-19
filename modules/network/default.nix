{ pkgs, lib }:
let packages = import ./src/package.nix { inherit pkgs; };
in {
  inherit packages;
  models.system = [ ./model/folio-network.yang ];
  subscribers.system = [ "folio-network.service" ];
  commands.network = {
    path = "${packages.client}/bin/folio-network";
    help = "${./cli/commands/network/help.txt}";
    scopes = [ "system" ];
  };
  nixosModule = import ./src/system.nix { inherit pkgs lib packages; };
  migrationModule = { lib, ... }: {
    systemd.tmpfiles.rules = [ "L /run/sylphy-mihomo - - - - /run/folio-mihomo" ];
    systemd.services.folio-mihomo.aliases = [ "sylphy-mihomo.service" ];
    # Existing private proxy policy is captured by the root-only migration
    # worker, never by evaluation or a build. Keep current routing/selections.
    systemd.services.folio-mihomo.serviceConfig.ExecStart = lib.mkForce
      "${pkgs.mihomo}/bin/mihomo -d /var/lib/folio-mihomo -f /var/lib/folio-mihomo/config.json";
  };
}
