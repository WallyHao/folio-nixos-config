{ pkgs }: [
  {
    module = "folio-network";
    from = "2026-10-19";
    to = "2026-10-27";
    fromSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-19/folio-network.yang;
    toSha256 = builtins.hashFile "sha256" ./model/folio-network.yang;
    transform = "${
      pkgs.writeShellApplication {
        name = "folio-network-unified-theme";
        runtimeInputs = [ pkgs.jq ];
        text = "jq -ceS .";
      }
    }/bin/folio-network-unified-theme";
  }
  {
    module = "folio-network-panel";
    from = "2026-10-19";
    to = "2026-10-27";
    fromSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-19/folio-network-panel.yang;
    toSha256 = builtins.hashFile "sha256" ./model/folio-network-panel.yang;
    transform = "${
      pkgs.writeShellApplication {
        name = "folio-network-panel-unified-theme";
        runtimeInputs = [ pkgs.jq ];
        text = "jq -ceS .";
      }
    }/bin/folio-network-panel-unified-theme";
  }
]
