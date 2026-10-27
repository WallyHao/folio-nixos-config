{ pkgs }:
let
  tools = [
    pkgs.nixfmt
    pkgs.ruff
    pkgs.stylua
    pkgs.shellcheck
    pkgs.git
    pkgs.findutils
  ];
  wrapper =
    name: arguments:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = tools ++ [
        pkgs.nix
        pkgs.jq
        pkgs.coreutils
        pkgs.bash
      ];
      text = ''
        exec bash ${../development/check.sh} ${arguments} "$@"
      '';
    };
in
{
  inherit tools;
  check = wrapper "folio-check" "";
  formatter = wrapper "folio-format" "format";
}
