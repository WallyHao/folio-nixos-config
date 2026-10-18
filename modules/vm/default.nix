{ pkgs, lib }:
let
  tools = import ./src/tools.nix { inherit pkgs; };
  runtime = import ./src/package.nix { inherit pkgs tools; };
in
{
  subscribers.user = [ "folio-vm.service" ];
  packages = {
    inherit tools;
    image = import ./src/image.nix { inherit pkgs lib tools; };
    inherit (runtime) subscriber;
  };
  models.user = [ ./model/folio-vm.yang ];
  commands.vm = {
    help = "${./cli/commands/vm/help.txt}";
    path = "${runtime.client}/bin/folio-vm";
    scopes = [ "user" ];
  };
  nixosModule = import ./src/system.nix { inherit pkgs; };
  homeManagerModule = import ./src/user.nix { inherit tools runtime; };
}
