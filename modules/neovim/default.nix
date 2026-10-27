{ pkgs, lib }:
let
  package = import ./src/package.nix { inherit pkgs lib; };
  current = ./model/folio-neovim.yang;
  migration = pkgs.writeShellApplication {
    name = "folio-neovim-replace-emacs";
    runtimeInputs = [ pkgs.jq ];
    text = "jq -ceS -f ${./src/migrate.jq}";
  };
in
{
  models.user = [ current ];
  packages = {
    editor = package;
    inherit migration;
    schema-history = pkgs.linkFarm "folio-retired-emacs-models" (
      map
        (revision: {
          name = "${revision}/folio-emacs.yang";
          path = ./model/revisions + "/${revision}/folio-emacs.yang";
        })
        [
          "2026-10-19"
          "2026-10-20"
          "2026-10-27"
        ]
    );
  };
  migrations =
    map
      (revision: {
        module = "folio-emacs";
        toModule = "folio-neovim";
        from = revision;
        to = "2026-10-27";
        fromSha256 = builtins.hashFile "sha256" (./model/revisions + "/${revision}/folio-emacs.yang");
        toSha256 = builtins.hashFile "sha256" current;
        transform = "${migration}/bin/folio-neovim-replace-emacs";
      })
      [
        "2026-10-19"
        "2026-10-20"
        "2026-10-27"
      ];
  checks.runtime = import ./tests/runtime.nix { inherit pkgs package; };
  homeManagerModule = import ./src/user.nix { inherit lib package; };
  impacts = [ "Open a new Neovim process to load editor and theme changes." ];
}
