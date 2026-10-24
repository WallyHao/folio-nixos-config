{ pkgs, lib }:
{
  migrations = import ./theme-migrations.nix { inherit pkgs; };
  models.user = [ ./model/folio-input.yang ];
  requirements.user.modules = [
    {
      module = "appearance";
      when = {
        path = [
          "folio-input:input"
          "wayland-frontend"
        ];
        default = true;
        equals = true;
      };
    }
  ];
  packages.seed = import ./src/package.nix { inherit pkgs; };
  packages.indicator = import ./src/indicator.nix { inherit pkgs; };
  homeManagerModule = import ./src/user.nix { inherit pkgs lib; };
}
