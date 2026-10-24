{
  pkgs,
  lib,
  collection,
  identities,
  system,
  targetName,
  defaults,
  context,
}:
let
  models = lib.genAttrs [ "system" "user" ] (
    scope:
    pkgs.linkFarm "folio-${scope}-models" (
      map (path: {
        name = builtins.baseNameOf path;
        inherit path;
      }) collection.models.${scope}
    )
  );
in
pkgs.runCommand "folio-bootstrap" { } ''
  mkdir -p $out/models
  cp ${pkgs.writeText "target.json" (builtins.toJSON { name = targetName; })} $out/target.json
  ln -s ${models.system} $out/models/system
  ln -s ${models.user} $out/models/user
  cp ${pkgs.writeText "system.json" (builtins.toJSON defaults.system)} $out/system.json
  cp ${pkgs.writeText "user.json" (builtins.toJSON defaults.user)} $out/user.json
  cp ${pkgs.folio.catalogue} $out/catalogue.json
  cp ${pkgs.writeText "identities.json" (builtins.toJSON identities)} $out/identities.json
  cp ${pkgs.writeText "migrations.json" (builtins.toJSON collection.migrations)} $out/migrations.json
  cp ${pkgs.writeText "subscribers.json" (builtins.toJSON collection.subscribers)} $out/subscribers.json
  cp ${
    pkgs.writeText "descriptor.json" (
      builtins.toJSON {
        format = 1;
        environment = "portable";
        platform = system;
        users = defaults.system."folio-environment:environment".users;
        preferences = defaults.system."folio-environment:environment".preferences;
        capabilities = (context "system").capabilities;
        origin = "bootstrap";
      }
    )
  } $out/system-descriptor.json
''
