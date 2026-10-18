{ inputs }:
let
  system = "x86_64-linux";
  basePkgs = import inputs.nixpkgs { inherit system; };
  sysrepoModule = import ../../sysrepo/default.nix {
    inherit pkgs;
    lib = basePkgs.lib;
  };
  # Explicit public build resources; no module imports another's private files.
  pkgs = basePkgs // {
    folio = {
      sysrepo = sysrepoModule.packages.library;
      repository = sysrepoModule.packages.tools;
      atomicWrite = catalogue.manager.packages.atomic;
      cliSupport = catalogue.manager.packages.cli-support;
      normalizer = catalogue.manager.packages.normalizer;
      repositoryMaintenance = sysrepoModule.packages.maintenance;
      systemConfiguration = portableSystem;
      source = lib.fileset.toSource {
        root = ../../..;
        fileset = lib.fileset.unions [
          ../../../flake.nix
          ../../../flake.lock
          ../../../modules
        ];
      };
      lockedInputs = [
        inputs.nixpkgs
        inputs.home-manager
      ];
    };
  };
  inherit (pkgs) lib;
  catalogueLib = import ./catalogue.nix { inherit lib; };
  catalogue = {
    manager = import ../default.nix {
      inherit pkgs lib;
      cliCommands = collection.commands;
    };
    sysrepo = sysrepoModule;
    system = import ../../system/default.nix { inherit pkgs lib; };
    terminal = import ../../terminal/default.nix { inherit pkgs lib; };
    vm = import ../../vm/default.nix { inherit pkgs lib; };
  };
  collection = catalogueLib.collect catalogue;
  defaults = lib.genAttrs [ "system" "user" ] (scope: import ./defaults.nix { inherit scope; });
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
    in
    {
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
      globals =
        defaults.system."folio-environment:environment".preferences
        // (if scope == "user" && prepared != null then prepared.systemDescriptor.preferences else { })
        // (environment.preferences or { });
      capabilities =
        if scope == "user" && prepared != null then
          prepared.systemDescriptor.capabilities
        else
          {
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
  models = lib.genAttrs [ "system" "user" ] (
    scope:
    pkgs.linkFarm "folio-${scope}-models" (
      map (path: {
        name = builtins.baseNameOf path;
        inherit path;
      }) collection.models.${scope}
    )
  );
  identities = {
    format = 1;
    tools = {
      libyang = pkgs.libyang.version;
      sysrepo = catalogue.sysrepo.packages.library.version;
    };
    models = lib.genAttrs [ "system" "user" ] (
      scope:
      map (path: {
        name = builtins.baseNameOf path;
        sha256 = builtins.hashFile "sha256" path;
      }) collection.models.${scope}
    );
  };
  portableSystem = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = {
      folioBootstrap = bootstrap;
      folioInput = if prepared != null && prepared.scope == "system" then prepared else null;
    };
    modules = adapters "system";
  };
  bootstrap = pkgs.runCommand "folio-bootstrap" { } ''
    mkdir -p $out/models
    ln -s ${models.system} $out/models/system
    ln -s ${models.user} $out/models/user
    cp ${pkgs.writeText "system.json" (builtins.toJSON defaults.system)} $out/system.json
    cp ${pkgs.writeText "user.json" (builtins.toJSON defaults.user)} $out/user.json
    cp ${
      pkgs.writeText "catalogue.json" (
        builtins.toJSON (
          lib.mapAttrs (_: d: {
            scopes =
              lib.optional (d.nixosModule != null) "system" ++ lib.optional (d.homeManagerModule != null) "user";
          }) collection.definitions
        )
      )
    } $out/catalogue.json
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
  '';
in
{
  packages.${system} = collection.packages // {
    manager-bootstrap = bootstrap;
    folio = collection.packages.manager-cli;
  };
  nixosConfigurations.portable = portableSystem;
  homeConfigurations.folio = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs.folioBootstrap = bootstrap;
    modules = adapters "user" ++ [
      {
        home.username = (context "user").identity.account;
        home.homeDirectory = (context "user").identity.home;
        home.stateVersion = "26.05";
        home.extraBuilderCommands = ''
          cp ${
            pkgs.writeText "folio-home.json" (
              builtins.toJSON {
                format = 1;
                workerProtocol = 1;
                scope = "user";
                bootstrap = toString bootstrap;
                account = (context "user").identity.account;
                home = (context "user").identity.home;
                configurationDigest =
                  if prepared != null && prepared.scope == "user" then prepared.configurationDigest else null;
              }
            )
          } $out/folio-home.json
        '';
      }
    ];
  };
  devShells.${system}.default = pkgs.mkShell {
    packages = [
      pkgs.cmake
      pkgs.pkg-config
      pkgs.jq
      pkgs.shellcheck
      pkgs.nixfmt
      pkgs.python3
      pkgs.util-linux
      collection.packages.sysrepo-tools
      collection.packages.manager-normalizer
      collection.packages.manager-input
      collection.packages.manager-cli
      collection.packages.manager-runtime
    ];
    inputsFrom = [
      collection.packages.sysrepo-library
      collection.packages.manager-normalizer
    ];
  };
  checks.${system} = {
    recovery = import ../tests/system-deployment.nix {
      inherit pkgs inputs bootstrap;
      recovery = true;
      source = pkgs.folio.source;
      modules = adapters "system";
      prepareInput = collection.packages.manager-input;
    };
    system-deployment = import ../tests/system-deployment.nix {
      inherit pkgs inputs bootstrap;
      source = lib.fileset.toSource {
        root = ../../..;
        fileset = lib.fileset.unions [
          ../../../flake.nix
          ../../../flake.lock
          ../../../modules
        ];
      };
      modules = adapters "system";
      prepareInput = collection.packages.manager-input;
    };
    system-scope = import ../tests/system-scope.nix {
      inherit pkgs inputs bootstrap;
      source = lib.fileset.toSource {
        root = ../../..;
        fileset = lib.fileset.unions [
          ../../../flake.nix
          ../../../flake.lock
          ../../../modules
        ];
      };
      modules = adapters "system";
    };
    user-deployment = import ../tests/user-deployment.nix {
      inherit pkgs inputs bootstrap;
      source = lib.fileset.toSource {
        root = ../../..;
        fileset = lib.fileset.unions [
          ../../../flake.nix
          ../../../flake.lock
          ../../../modules
        ];
      };
      runtime = collection.packages.manager-runtime;
      cli = collection.packages.manager-cli;
      repository = collection.packages.sysrepo-tools;
      prepareInput = collection.packages.manager-input;
    };
    configuration = import ../tests/configuration.nix {
      inherit pkgs bootstrap;
      runtime = collection.packages.manager-runtime;
      cli = collection.packages.manager-cli;
      repository = collection.packages.sysrepo-tools;
    };
    catalogue = import ../tests/catalogue.nix { inherit pkgs catalogueLib; };
    foundation = import ../../sysrepo/tests/foundation.nix {
      inherit pkgs bootstrap;
      tools = collection.packages.sysrepo-tools;
      normalizer = collection.packages.manager-normalizer;
      sysrepo = collection.packages.sysrepo-library;
      prepareInput = collection.packages.manager-input;
    };
  };
}
