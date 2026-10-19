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
      configClient = catalogue.manager.packages.config-client;
      cli = catalogue.manager.packages.cli;
      inputLanguage = catalogue.input.packages.indicator;
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
    applications = import ../../applications/default.nix { inherit pkgs lib; };
    desktop = import ../../desktop/default.nix { inherit pkgs lib; };
    devices = import ../../devices/default.nix { inherit pkgs lib; };
    appearance = import ../../appearance/default.nix { inherit pkgs lib; };
    input = import ../../input/default.nix { inherit pkgs lib; };
  };
  collection = catalogueLib.collect catalogue;
  composition = import ./configuration.nix { inherit inputs pkgs lib identities collection catalogueLib; };
  inherit (composition) defaults prepared configuration context adapters;
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
    applications = lib.makeOverridable ({ cache ? null, plans ? null }: import ../../applications/tests/guest.nix {
      inherit pkgs inputs bootstrap cache plans;
      source = pkgs.folio.source;
      prepareInput = collection.packages.manager-input;
      modules = adapters "system";
    }) { };
    desktop = lib.makeOverridable ({ legacySource ? null, cache ? null, plans ? null, drm ? true }: import ../../desktop/tests/session.nix {
      inherit pkgs inputs bootstrap legacySource cache plans drm;
      source = pkgs.folio.source;
      prepareInput = collection.packages.manager-input;
      runtime = collection.packages.manager-runtime;
      cli = collection.packages.manager-cli;
      modules = adapters "system";
    }) { };
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
