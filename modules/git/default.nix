{ pkgs, lib }: {
  models.user = [ ./model/folio-git.yang ];
  homeManagerModule = import ./src/user.nix { inherit pkgs lib; };
}
