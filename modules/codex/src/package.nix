{ pkgs }: pkgs.symlinkJoin {
  name = "folio-codex-${pkgs.codex.version}";
  paths = [ pkgs.codex ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/codex --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.gitMinimal ]}
  '';
}
