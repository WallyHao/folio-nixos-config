# Reuse Sylphy's Org-roam editor, without its private CLI or OMP integration.
{ pkgs }:
let
  editor = (pkgs.emacsPackagesFor pkgs.emacs-pgtk).emacsWithPackages (
    epkgs: with epkgs; [
      org-roam
      doom-modeline
      dashboard
      consult
      vertico
      orderless
      marginalia
      org-modern
    ]
  );
  init = pkgs.writeText "folio-emacs-init.el" (import ./config.nix { });
in
pkgs.symlinkJoin {
  name = "folio-emacs-${pkgs.emacs-pgtk.version}";
  paths = [ editor ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/emacs --add-flags "--no-init-file --load ${init}" \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.ripgrep
          pkgs.fd
        ]
      }
  '';
}
