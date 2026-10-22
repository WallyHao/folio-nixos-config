{ pkgs }: [
  {
    module = "folio-system";
    from = "2026-10-19"; to = "2026-10-27";
    fromSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-19/folio-system.yang;
    toSha256 = builtins.hashFile "sha256" ./model/folio-system.yang;
    transform = "${pkgs.writeShellApplication {
      name = "folio-system-unified-theme";
      runtimeInputs = [ pkgs.jq ];
      text = "jq -ceS .";
    }}/bin/folio-system-unified-theme";
  }
]
