{ inputs, targetName ? null }:
let
  targetPath = inputs.self.outPath + "/folio-target.json";
  selectedTarget = if targetName != null then targetName
    else if builtins.pathExists targetPath then (builtins.fromJSON (builtins.readFile targetPath)).name
    else "portable";
  system = "x86_64-linux";
  basePkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfreePredicate = package: (basePkgs.lib.getName package) == "unrar";
  };
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
      frontend = catalogue.panel.packages.cli;
      inputLanguage = catalogue.input.packages.indicator;
      normalizer = catalogue.manager.packages.normalizer;
      repositoryMaintenance = sysrepoModule.packages.maintenance;
      catalogue = pkgs.writeText "folio-catalogue.json" (builtins.toJSON (
        lib.mapAttrs (_: d: {
          inherit (d) requirements impacts;
          scopes = lib.optional (d.nixosModule != null) "system" ++ lib.optional (d.homeManagerModule != null) "user";
        }) collection.definitions));
      systemConfiguration = portableSystem;
      source = pkgs.runCommand "folio-${selectedTarget}-source" { } ''
        mkdir $out
        cp -R ${sourceTree}/. $out/
        chmod -R u+w $out
        cp ${pkgs.writeText "folio-target.json" (builtins.toJSON { name = selectedTarget; })} $out/folio-target.json
      '';
      sourceTree = lib.fileset.toSource {
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
  sourceTree = pkgs.folio.sourceTree;
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
    emacs = import ../../emacs/default.nix { inherit pkgs lib; };
    agents = import ../../agents/default.nix { inherit pkgs lib; };
    isaac = import ../../isaac/default.nix { inherit pkgs lib; };
    network = import ../../network/default.nix { inherit pkgs lib; };
    panel = import ../../panel/default.nix {
      inherit pkgs;
      legacyCli = catalogue.manager.packages.cli;
      storeBackend = catalogue.applications.packages.store;
      wifi = catalogue.network.packages.wifi;
      devices = catalogue.devices.packages.panel;
      repository = catalogue.sysrepo.packages.tools;
    };
  };
  collection = catalogueLib.collect catalogue;
  targets = import ./targets.nix { inherit catalogue; };
  target = targets.${selectedTarget} or (throw "Folio: unknown hardware target '${selectedTarget}'; configure its module-owned hardware and storage before use");
  composition = import ./configuration.nix { inherit inputs pkgs lib identities collection catalogueLib target; };
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
  systemModule = {
    imports = adapters "system" ++ target.modules;
    _module.args = {
      folioBootstrap = bootstrap;
      folioInput = if prepared != null && prepared.scope == "system" then prepared else null;
    };
  };
  portableSystem = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = {
      folioBootstrap = bootstrap;
      folioInput = if prepared != null && prepared.scope == "system" then prepared else null;
    };
    modules = [ systemModule ];
  };
  bootstrap = pkgs.runCommand "folio-bootstrap" { } ''
    mkdir -p $out/models
    cp ${pkgs.writeText "target.json" (builtins.toJSON { name = selectedTarget; })} $out/target.json
    ln -s ${models.system} $out/models/system
    ln -s ${models.user} $out/models/user
    cp ${pkgs.writeText "system.json" (builtins.toJSON defaults.system)} $out/system.json
    cp ${pkgs.writeText "user.json" (builtins.toJSON defaults.user)} $out/user.json
    cp ${
      pkgs.writeText "catalogue.json" (
        builtins.toJSON (
          lib.mapAttrs (_: d: {
            inherit (d) requirements impacts;
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
  userPackages = basePkgs.extend (_final: previous: {
    inherit (pkgs) folio;
    # Honor keep-old for an already active system-provided user service when
    # Home Manager takes ownership of its unit for the first time.
    sd-switch = previous.sd-switch.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./sd-switch-keep-active.patch ];
    });
  });
  userHome = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = userPackages;
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

in
{
  packages.${system} = collection.packages // {
    manager-bootstrap = bootstrap;
    folio = catalogue.panel.packages.cli;
  };
  nixosModules.portable = systemModule;
  nixosConfigurations.portable = portableSystem;
  nixosConfigurations.folio = if selectedTarget == "folio" then portableSystem
    else (import ./outputs.nix { inherit inputs; targetName = "folio"; }).nixosConfigurations.portable;
  lib.folio.identities = identities;
  lib.folio.targets = {
    portable = "Disposable UEFI guest";
    folio = "Existing migrated USB system shared by the Intel/NVIDIA laptop and AMD/NVIDIA desktop";
  };
  homeConfigurations.folio = userHome;
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
      catalogue.panel.packages.cli
      collection.packages.manager-runtime
    ];
    inputsFrom = [
      collection.packages.sysrepo-library
      collection.packages.manager-normalizer
    ];
  };
  checks.${system} = import ../tests/default.nix {
    inherit pkgs inputs bootstrap catalogue collection adapters userPackages userHome catalogueLib;
  };
}
