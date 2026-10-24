{
  pkgs,
  palette ? null,
  accent ? palette.green,
}:
let
  lib = pkgs.lib;
  command = if palette == null then "${pkgs.codex}/bin/codex" else "${pkgs.python3}/bin/python3";
  arguments = lib.escapeShellArgs [
    "${./colors.py}"
    "--accent"
    accent
    "--selection"
    palette.bg_visual
    "--selection-text"
    palette.fg
    "--"
    "${pkgs.codex}/bin/codex"
    "--config"
    ''tui.theme="folio"''
  ];
  themeFlags = lib.optionalString (palette != null) " --add-flags ${lib.escapeShellArg arguments}";
in
pkgs.symlinkJoin {
  name = "folio-codex-${pkgs.codex.version}";
  paths = [ pkgs.codex ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    rm "$out/bin/codex"
    makeWrapper ${command} "$out/bin/codex" --prefix PATH : ${
      lib.makeBinPath [ pkgs.gitMinimal ]
    }${themeFlags}
  '';
}
