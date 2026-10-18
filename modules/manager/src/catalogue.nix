{ lib }:
let
  scopes = [
    "system"
    "user"
  ];
  exclusive =
    label: sets:
    lib.foldl' (
      acc: next:
      let
        duplicates = lib.intersectLists (builtins.attrNames acc) (builtins.attrNames next);
      in
      if duplicates != [ ] then
        throw "Folio: duplicate ${label}: ${lib.concatStringsSep ", " duplicates}"
      else
        acc // next
    ) { } sets;
  modelName =
    path: builtins.head (lib.splitString "@" (lib.removeSuffix ".yang" (builtins.baseNameOf path)));
in
rec {
  inherit exclusive;
  collect =
    catalogue:
    let
      definitions = lib.mapAttrs (_: entry: {
        packages = entry.packages or { };
        models = {
          system = [ ];
          user = [ ];
        }
        // (entry.models or { });
        commands = entry.commands or { };
        migrations = entry.migrations or [ ];
        subscribers = {
          system = [ ];
          user = [ ];
        }
        // (entry.subscribers or { });
        nixosModule = entry.nixosModule or null;
        homeManagerModule = entry.homeManagerModule or null;
      }) catalogue;
      commands = exclusive "command roots" (lib.mapAttrsToList (_: d: d.commands) definitions);
      validCommands = lib.all (
        command:
        command ? path
        && command ? scopes
        && command.scopes != [ ]
        && lib.all (scope: builtins.elem scope scopes) command.scopes
      ) (builtins.attrValues commands);
      models = lib.genAttrs scopes (
        scope:
        builtins.attrValues (
          exclusive "model names/revisions" (
            lib.mapAttrsToList (
              _: d:
              exclusive "model names/revisions" (map (path: { ${modelName path} = path; }) d.models.${scope})
            ) definitions
          )
        )
      );
      packages = exclusive "package names" (
        lib.mapAttrsToList (
          name: d:
          lib.mapAttrs' (component: package: lib.nameValuePair "${name}-${component}" package) d.packages
        ) definitions
      );
    in
    if !validCommands then
      throw "Folio: invalid command scope or missing command path"
    else
      builtins.deepSeq models {
        inherit
          definitions
          commands
          models
          packages
          ;
        migrations = lib.concatMap (definition: definition.migrations) (builtins.attrValues definitions);
        subscribers = lib.genAttrs scopes (
          scope:
          lib.unique (
            lib.concatMap (definition: definition.subscribers.${scope}) (builtins.attrValues definitions)
          )
        );
      };

  select =
    {
      collection,
      scope,
      selections,
    }:
    if !(builtins.elem scope scopes) then
      throw "Folio: unsupported scope ${scope}"
    else
      map (
        selection:
        let
          name = selection.name;
          definition = collection.definitions.${name} or (throw "Folio: unknown module ${name}");
          adapter = if scope == "system" then definition.nixosModule else definition.homeManagerModule;
        in
        if adapter == null then
          throw "Folio: module ${name} does not support ${scope} scope"
        else
          {
            inherit name adapter;
            settings = selection;
          }
      ) selections;
}
