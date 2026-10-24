{ pkgs }: [
  {
    module = "folio-vm";
    from = "2026-10-18";
    to = "2026-10-27";
    fromSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-18/folio-vm.yang;
    toSha256 = builtins.hashFile "sha256" ./model/folio-vm.yang;
    transform = "${
      pkgs.writeShellApplication {
        name = "folio-vm-unified-theme";
        runtimeInputs = [ pkgs.jq ];
        text = "jq -ceS .";
      }
    }/bin/folio-vm-unified-theme";
  }
]
