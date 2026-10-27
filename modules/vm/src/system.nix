{ pkgs }:
context: { ... }: {
  users.groups.kvm = { };
  environment.etc."folio/source".source = pkgs.folio.source;

  virtualisation.docker = {
    enable = true;
    enableOnBoot = false;
  };
  # NixOS otherwise enables socket activation even when enableOnBoot is false.
  systemd.sockets.docker.wantedBy = pkgs.lib.mkForce [ ];
}
