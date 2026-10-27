{ pkgs, networkPrepare }:
let
  health = pkgs.writeTextDir "folio_workspace_health.py" (builtins.readFile ../runtime/health.py);
in
{
  system = pkgs.writeShellApplication {
    name = "folio-workspace-system";
    runtimeInputs = [
      pkgs.nix
      pkgs.systemd
      pkgs.util-linux
      networkPrepare
    ];
    text = ''
      export LC_ALL=C
      export PYTHONUNBUFFERED=1
      export PYTHONPATH=${health}
      exec ${pkgs.python3}/bin/python3 ${../runtime/system.py} "$@"
    '';
  };
  client = pkgs.writeShellApplication {
    name = "folio-prepare";
    runtimeInputs = [
      pkgs.systemd
      pkgs.curl
      pkgs.getent
    ];
    text = ''
      export PYTHONPATH=${health}
      exec ${pkgs.python3}/bin/python3 ${../cli/prepare.py} "$@"
    '';
  };
}
