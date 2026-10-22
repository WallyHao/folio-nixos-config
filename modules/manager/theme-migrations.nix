{ pkgs }: [
  {
    module = "folio-environment";
    from = "2026-10-18"; to = "2026-10-27";
    fromSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-18/folio-environment.yang;
    toSha256 = builtins.hashFile "sha256" ./model/folio-environment.yang;
    transform = "${pkgs.writeShellApplication {
      name = "folio-environment-unified-theme";
      runtimeInputs = [ pkgs.jq ];
      text = "jq -ceS -f ${./src/migrate-theme.jq}";
    }}/bin/folio-environment-unified-theme";
  }
  {
    module = "folio-deployment";
    from = "2026-10-19"; to = "2026-10-27";
    fromSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-19/folio-deployment.yang;
    toSha256 = builtins.hashFile "sha256" ./model/folio-deployment.yang;
    transform = "${pkgs.writeShellApplication {
      name = "folio-deployment-unified-theme";
      runtimeInputs = [ pkgs.jq ];
      text = "jq -ceS .";
    }}/bin/folio-deployment-unified-theme";
  }
]
