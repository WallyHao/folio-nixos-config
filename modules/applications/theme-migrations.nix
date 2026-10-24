{ pkgs }: [
  {
    module = "folio-applications";
    from = "2026-10-26";
    to = "2026-10-27";
    fromSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-26/folio-applications.yang;
    toSha256 = builtins.hashFile "sha256" ./model/folio-applications.yang;
    transform = "${
      pkgs.writeShellApplication {
        name = "folio-applications-unified-theme";
        runtimeInputs = [ pkgs.jq ];
        text = "jq -ceS .";
      }
    }/bin/folio-applications-unified-theme";
  }
]
