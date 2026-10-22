{ pkgs, lib, cliCommands ? { } }:
let implementation = import ./src/package.nix { inherit pkgs lib cliCommands; };
in
{
  checks.workflow = import ./tests/workflow.nix { inherit pkgs; };
  subscribers = {
    user = [ "folio-manager.service" ];
    system = [ "folio-manager.service" ];
  };
  models = {
    system = [
      ./model/folio-environment.yang
      ./model/folio-deployment.yang
    ];
    user = [
      ./model/folio-environment.yang
      ./model/folio-deployment.yang
    ];
  };
  inherit (implementation) packages commands;
  migrations = (import ./theme-migrations.nix { inherit pkgs; }) ++ [{
    module = "folio-deployment";
    from = "2026-10-18"; to = "2026-10-19";
    fromSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-18/folio-deployment.yang;
    toSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-19/folio-deployment.yang;
    transform = "${pkgs.writeShellApplication {
      name = "folio-deployment-add-review";
      runtimeInputs = [ pkgs.jq ];
      text = "jq -ceS .";
    }}/bin/folio-deployment-add-review";
  }];
  nixosModule = import ./src/system.nix {
    inherit pkgs lib;
    inherit (implementation) client runtime normalizer;
  };
  homeManagerModule = import ./src/user.nix {
    inherit pkgs;
    inherit (implementation) client runtime;
  };
}
