{ pkgs }:
{ lib, ... }: {
  # The portable installation retains its private rules and selected nodes.
  # Credential material is provisioned at runtime and never read by evaluation.
  systemd.services.folio-mihomo.serviceConfig.ExecStart = lib.mkForce
    "${pkgs.mihomo}/bin/mihomo -d /var/lib/folio-mihomo -f /var/lib/folio-mihomo/config.json";
}
