{ pkgs, lib }:
let implementation = import ./src/package.nix { inherit pkgs lib; };
in
{
  models.user = [ ./model/folio-applications.yang ];
  subscribers.user = [ "folio-applications.service" ];
  packages = builtins.removeAttrs implementation [ "client" ];
  commands.apps = { path = "${implementation.client}/bin/folio-apps"; scopes = [ "user" ]; help = "${./cli/commands/applications/help.txt}"; };
  nixosModule = context: import ./src/system.nix;
  homeManagerModule = import ./src/user.nix { inherit pkgs lib; runtime = implementation; };
}
