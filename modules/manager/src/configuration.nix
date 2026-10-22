{ inputs, pkgs, lib, identities, collection, catalogueLib, target ? { settings = { }; } }:
let
  defaults = lib.genAttrs [ "system" "user" ] (scope:
    let shared = import ./defaults.nix { inherit scope; };
    in shared // { "folio-environment:environment" = shared."folio-environment:environment"
      // (target.environment.${scope} or { }) // {
      modules = map (entry: entry // (target.settings.${entry.name} or { })) shared."folio-environment:environment".modules;
    }; });
  # Prepared inputs are immutable source files; no datastore is queried here.
  preparedPath = inputs.self.outPath + "/folio-input.json";
  prepared =
    if builtins.pathExists preparedPath then
      import ./prepared.nix {
        prepared = builtins.fromJSON (builtins.readFile preparedPath);
        inherit identities;
      }
    else
      null;
  configuration =
    scope:
    if prepared != null && prepared.scope == scope then prepared.configuration else defaults.${scope};
  context =
    scope:
    let
      environment = (configuration scope)."folio-environment:environment";
      sharedPreferences =
        defaults.system."folio-environment:environment".preferences
        // (if scope == "user" && prepared != null then prepared.systemDescriptor.preferences else { })
        // (if scope == "user" then builtins.removeAttrs (environment.preferences or { }) [ "scheme" "appearance" ]
            else environment.preferences or { });
    in
    {
      configurationDigest = if prepared != null && prepared.scope == scope then prepared.configurationDigest else null;
      identity = {
        inherit scope;
        environment = environment.name;
        platform = environment.platform;
      }
      // lib.optionalAttrs (scope == "system") { users = environment.users; }
      // lib.optionalAttrs (scope == "user") {
        account = environment.account;
        home =
          let
            users =
              if prepared != null then
                prepared.systemDescriptor.users
              else
                defaults.system."folio-environment:environment".users;
            matches = builtins.filter (user: user.name == environment.account) users;
          in
          if builtins.length matches != 1 then
            throw "Folio: account is absent or ambiguous in system descriptor"
          else
            (builtins.head matches).home;
      };
      enabledModules = map (entry: entry.name) (builtins.filter (entry: entry.enabled or false) environment.modules);
      globals = sharedPreferences;
      theme = import ../../appearance/lib { preferences = sharedPreferences; };
      preferenceOrigins =
        if prepared != null && prepared.scope == scope then prepared.resolvedPreferences.origins
        else lib.mapAttrs (name: _: if scope == "system" then "system-configuration"
          else if !(builtins.elem name [ "scheme" "appearance" ]) && builtins.hasAttr name (environment.preferences or { }) then "user-configuration"
          else "system-default") sharedPreferences;
      capabilities =
        if scope == "user" && prepared != null then
          prepared.systemDescriptor.capabilities
        else
          {
            network-provisioned = lib.any (entry: entry.name == "network" && (entry.enabled or false))
              (configuration "system")."folio-environment:environment".modules;
            desktop-provisioned = lib.any (entry: entry.name == "desktop" && (entry.enabled or false))
              (configuration "system")."folio-environment:environment".modules;
            devices-provisioned = lib.any (entry: entry.name == "devices" && (entry.enabled or false))
              (configuration "system")."folio-environment:environment".modules;
            flatpak-provisioned = lib.any (entry: entry.name == "applications" && (entry.enabled or false))
              (configuration "system")."folio-environment:environment".modules;
            kvm-access-configured = lib.any (
              entry: entry.name == "vm" && (entry.enabled or false)
            ) (configuration "system")."folio-environment:environment".modules;
          };
    };
  adapters =
    scope:
    map (entry: entry.adapter ((context scope) // { settings = entry.settings; })) (
      builtins.filter (entry: entry.settings.enabled or false) (
        catalogueLib.select {
          inherit collection scope;
          selections = (configuration scope)."folio-environment:environment".modules;
        }
      )
    );
in { inherit defaults prepared configuration context adapters; }
