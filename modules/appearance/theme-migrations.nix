{ pkgs }: [
  {
    module = "folio-appearance";
    from = "2026-10-19";
    to = "2026-10-27";
    fromSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-19/folio-appearance.yang;
    toSha256 = builtins.hashFile "sha256" ./model/folio-appearance.yang;
    transform = "${
      pkgs.writeShellApplication {
        name = "folio-appearance-unified-theme";
        runtimeInputs = [ pkgs.jq ];
        text = "jq -ceS -f ${./src/migrate-theme.jq}";
      }
    }/bin/folio-appearance-unified-theme";
  }
]
