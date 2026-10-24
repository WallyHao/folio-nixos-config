{ pkgs, lib }:
let
  environment = import ./environment.nix { inherit pkgs; };
  shell = pkgs.writeShellApplication {
    name = "isaac-shell";
    text = ''
      if [[ ''${1:-} == --command ]]; then shift; fi
      exec ${environment}/bin/isaac-fhs "$@"
    '';
  };
  launcher = action: ''
    export ISAAC_VERSIONS=${./versions.json}
    export ISAAC_VALIDATION_SCRIPTS=${../runtime/validation}
    export ISAAC_COMPATIBILITY=${./compatibility.txt}
    export ISAAC_RUNTIME=${shell}
    exec ${shell}/bin/isaac-shell --command /usr/bin/python3.12 ${../cli/isaac.py} ${action} "$@"
  '';
  tools = pkgs.symlinkJoin {
    name = "isaac-tools";
    paths =
      map
        (
          action:
          pkgs.writeShellApplication {
            name = "isaac-${if action == "run" then "lab" else action}";
            text = launcher action;
          }
        )
        [
          "setup"
          "doctor"
          "status"
          "run"
          "sim"
        ];
  };
in
{
  inherit shell tools;
}
