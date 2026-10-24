{ pkgs }: [
  {
    module = "folio-agents";
    from = "2026-10-23";
    to = "2026-10-27";
    fromSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-23/folio-agents.yang;
    toSha256 = builtins.hashFile "sha256" ./model/folio-agents.yang;
    transform = "${
      pkgs.writeShellApplication {
        name = "folio-agents-unified-theme";
        runtimeInputs = [ pkgs.jq ];
        text = "jq -ceS .";
      }
    }/bin/folio-agents-unified-theme";
  }
]
