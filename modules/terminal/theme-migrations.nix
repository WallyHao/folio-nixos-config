{ pkgs }: [
  {
    module = "folio-terminal";
    from = "2026-10-24";
    to = "2026-10-27";
    fromSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-24/folio-terminal.yang;
    toSha256 = builtins.hashFile "sha256" ./model/folio-terminal.yang;
    transform = "${
      pkgs.writeShellApplication {
        name = "folio-terminal-unified-theme";
        runtimeInputs = [ pkgs.jq ];
        text = "jq -ceS .";
      }
    }/bin/folio-terminal-unified-theme";
  }
]
