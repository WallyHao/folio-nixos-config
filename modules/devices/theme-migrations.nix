{ pkgs }: [
  {
    module = "folio-devices";
    from = "2026-10-19"; to = "2026-10-27";
    fromSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-19/folio-devices.yang;
    toSha256 = builtins.hashFile "sha256" ./model/folio-devices.yang;
    transform = "${pkgs.writeShellApplication {
      name = "folio-devices-unified-theme";
      runtimeInputs = [ pkgs.jq ];
      text = "jq -ceS .";
    }}/bin/folio-devices-unified-theme";
  }
]
