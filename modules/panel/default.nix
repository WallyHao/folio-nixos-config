{
  pkgs,
  legacyCli,
  wifi,
  devices,
  repository,
  storeBackend,
}:
let
  package = import ./src/package.nix {
    inherit
      pkgs
      legacyCli
      wifi
      devices
      repository
      storeBackend
      ;
  };
in
{
  packages.cli = package;
  checks = {
    http = import ./tests/http.nix { inherit pkgs package; };
    browser = import ./tests/browser.nix { inherit pkgs package; };
  };
}
