{ pkgs, lib }:
let
  package = import ./src/package.nix { inherit pkgs; };
  previous = ./model/revisions/2026-10-19/folio-emacs.yang;
  current = ./model/folio-emacs.yang;
  migration = pkgs.writeShellApplication {
    name = "folio-emacs-library-directory";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      jq -ceS '."folio-environment:environment".modules |= map(
        if .name=="emacs" and ."folio-emacs:emacs"."notes-directory"=="~/Documents/Notes"
        then ."folio-emacs:emacs"."notes-directory"="~/Documents/documents"
        else . end)'
    '';
  };
in {
  models.user = [ current ];
  migrations = [{
    module = "folio-emacs";
    from = "2026-10-19"; to = "2026-10-20";
    fromSha256 = builtins.hashFile "sha256" previous;
    toSha256 = builtins.hashFile "sha256" current;
    transform = "${migration}/bin/folio-emacs-library-directory";
  }];
  packages.editor = package;
  homeManagerModule = import ./src/user.nix { inherit pkgs lib package; };
}
