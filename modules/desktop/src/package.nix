{ pkgs }:
{
  niri = import ./compositor.nix { inherit pkgs; };
  clipboard = pkgs.writeShellApplication {
    name = "folio-clipboard-pick";
    runtimeInputs = [ pkgs.cliphist pkgs.fuzzel pkgs.wl-clipboard ];
    text = builtins.readFile ../runtime/operations/clipboard.sh;
  };
  session = pkgs.writeShellApplication {
    name = "folio-session-confirm";
    runtimeInputs = [ pkgs.zenity pkgs.folio.cli ];
    text = builtins.readFile ../runtime/operations/session.sh;
  };
}
