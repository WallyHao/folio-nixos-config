{ pkgs }: [
  {
    module = "folio-desktop";
    from = "2026-10-19"; to = "2026-10-27";
    fromSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-19/folio-desktop.yang;
    toSha256 = builtins.hashFile "sha256" ./model/folio-desktop.yang;
    transform = "${pkgs.writeShellApplication {
      name = "folio-desktop-unified-theme";
      runtimeInputs = [ pkgs.jq ];
      text = "jq -ceS .";
    }}/bin/folio-desktop-unified-theme";
  }
]
