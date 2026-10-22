{ pkgs }: [
  {
    module = "folio-emacs";
    from = "2026-10-20"; to = "2026-10-27";
    fromSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-20/folio-emacs.yang;
    toSha256 = builtins.hashFile "sha256" ./model/folio-emacs.yang;
    transform = "${pkgs.writeShellApplication {
      name = "folio-emacs-unified-theme";
      runtimeInputs = [ pkgs.jq ];
      text = "jq -ceS .";
    }}/bin/folio-emacs-unified-theme";
  }
]
