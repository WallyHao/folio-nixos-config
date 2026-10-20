{ pkgs, lib }:
let implementation = import ./src/package.nix { inherit pkgs lib; };
in
{
  models.user = [ ./model/folio-applications.yang ];
  migrations = [{
    module = "folio-applications";
    from = "2026-10-18"; to = "2026-10-23";
    fromSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-18/folio-applications.yang;
    toSha256 = builtins.hashFile "sha256" ./model/folio-applications.yang;
    transform = "${pkgs.writeShellApplication {
      name = "folio-applications-add-native";
      runtimeInputs = [ pkgs.jq ];
      text = "jq -ceS .";
    }}/bin/folio-applications-add-native";
  }];
  subscribers.user = [ "folio-applications.service" ];
  packages = (builtins.removeAttrs implementation [ "client" ]) // {
    schema-history = pkgs.linkFarm "folio-applications-schema-history" [
      { name = "2026-10-18/folio-applications.yang"; path = ./model/revisions/2026-10-18/folio-applications.yang; }
    ];
  };
  commands.apps = { path = "${implementation.client}/bin/folio-apps"; scopes = [ "user" ]; help = "${./cli/commands/applications/help.txt}"; };
  nixosModule = context: import ./src/system.nix;
  homeManagerModule = import ./src/user.nix { inherit pkgs lib; runtime = implementation; };
}
