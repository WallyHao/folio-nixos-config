{ pkgs }: [
  {
    module = "folio-input";
    from = "2026-10-19";
    to = "2026-10-27";
    fromSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-19/folio-input.yang;
    toSha256 = builtins.hashFile "sha256" ./model/folio-input.yang;
    transform = "${
      pkgs.writeShellApplication {
        name = "folio-input-unified-theme";
        runtimeInputs = [ pkgs.jq ];
        text = "jq -ceS .";
      }
    }/bin/folio-input-unified-theme";
  }
]
