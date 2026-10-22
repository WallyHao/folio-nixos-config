# Compose integration fixtures here; self-contained module checks are collected
# from each module's public exports. Legacy names below remain command aliases.
{
  pkgs,
  inputs,
  bootstrap,
  catalogue,
  collection,
  adapters,
  userPackages,
  userHome,
  catalogueLib,
}:
catalogueLib.exclusive "check names" [
  collection.checks
  {
    # Compatibility aliases reference the same derivation as the module check.
    account-migration = collection.checks.system-account-migration;
    appearance = collection.checks.appearance-gtk;
    browser-windows = collection.checks.applications-browser-windows;
    cli-workflow = collection.checks.manager-workflow;
    legacy-retirement-files = collection.checks.system-legacy-retirement-files;
    panel = collection.checks.panel-http;

    legacy-retirement = import ../../system/tests/legacy-retirement.nix {
      inherit pkgs inputs;
      cleanup = catalogue.system.packages.legacy-cleanup;
    };

    agents = import ../../agents/tests/runtime.nix {
      inherit pkgs bootstrap;
      pi = catalogue.agents.packages.pi;
    };
    agents-migration = import ../../agents/tests/migration.nix {
      inherit pkgs bootstrap;
      repository = catalogue.sysrepo.packages.tools;
      maintenance = catalogue.sysrepo.packages.maintenance;
      agentsHistory = catalogue.agents.packages.schema-history;
      terminalHistory = catalogue.terminal.packages.schema-history;
      applicationsHistory = catalogue.applications.packages.schema-history;
      systemModules = adapters "system";
      homeManager = inputs.home-manager.lib;
      runtime = collection.packages.manager-runtime;
      prepareInput = collection.packages.manager-input;
      source = pkgs.folio.source;
      inherit inputs;
      switcher = userPackages.sd-switch;
    };

    panel-network = import ../../network/tests/panel.nix {
      inherit pkgs bootstrap;
      repository = catalogue.sysrepo.packages.tools;
      subscriber = catalogue.network.packages.subscriber;
      wifi = catalogue.network.packages.wifi;
      devices = catalogue.devices.packages.panel;
      panel = catalogue.panel.packages.cli;
    };
    integrated-release = pkgs.lib.makeOverridable (
      {
        cache ? null,
        plans ? null,
      }:
      import ./system-deployment.nix {
        inherit
          pkgs
          inputs
          bootstrap
          cache
          plans
          ;
        integrated = true;
        source = pkgs.folio.source;
        modules = adapters "system";
        prepareInput = collection.packages.manager-input;
      }
    ) { };
    recovery = import ./system-deployment.nix {
      inherit pkgs inputs bootstrap;
      recovery = true;
      source = pkgs.folio.source;
      modules = adapters "system";
      prepareInput = collection.packages.manager-input;
    };
    system-deployment = import ./system-deployment.nix {
      inherit pkgs inputs bootstrap;
      source = pkgs.folio.sourceTree;
      modules = adapters "system";
      prepareInput = collection.packages.manager-input;
    };
    system-scope = import ./system-scope.nix {
      inherit pkgs inputs bootstrap;
      source = pkgs.folio.sourceTree;
      modules = adapters "system";
    };
    user-deployment = import ./user-deployment.nix {
      inherit pkgs inputs bootstrap;
      source = pkgs.folio.sourceTree;
      runtime = collection.packages.manager-runtime;
      cli = collection.packages.manager-cli;
      repository = collection.packages.sysrepo-tools;
      prepareInput = collection.packages.manager-input;
    };
    applications-native = import ../../applications/tests/native.nix {
      inherit pkgs inputs bootstrap;
      source = pkgs.folio.source;
      prepareInput = collection.packages.manager-input;
    };
    applications = pkgs.lib.makeOverridable (
      {
        cache ? null,
        plans ? null,
      }:
      import ../../applications/tests/guest.nix {
        inherit
          pkgs
          inputs
          bootstrap
          cache
          plans
          ;
        source = pkgs.folio.source;
        prepareInput = collection.packages.manager-input;
        modules = adapters "system";
      }
    ) { };
    desktop = pkgs.lib.makeOverridable (
      {
        legacySource ? null,
        cache ? null,
        plans ? null,
        drm ? true,
      }:
      import ../../desktop/tests/session.nix {
        inherit
          pkgs
          inputs
          bootstrap
          legacySource
          cache
          plans
          drm
          ;
        source = pkgs.folio.source;
        prepareInput = collection.packages.manager-input;
        runtime = collection.packages.manager-runtime;
        cli = collection.packages.manager-cli;
        modules = adapters "system";
      }
    ) { };
    theme-migration = import ./theme-migration.nix {
      inherit pkgs bootstrap;
      repository = catalogue.sysrepo.packages.tools;
      maintenance = catalogue.sysrepo.packages.maintenance;
    };
    configuration = import ./configuration.nix {
      inherit pkgs bootstrap;
      runtime = collection.packages.manager-runtime;
      cli = collection.packages.manager-cli;
      repository = collection.packages.sysrepo-tools;
    };
    network = import ../../network/tests/acceptance.nix {
      inherit pkgs inputs bootstrap;
      source = pkgs.folio.source;
      runtime = collection.packages.manager-runtime;
      cli = collection.packages.manager-cli;
      prepareInput = collection.packages.manager-input;
      guestInstrumentation = ./system-guest.nix;
      oldSystemModel = ../../system/model/revisions/2026-10-18/folio-system.yang;
    };
    tools-deployment = pkgs.lib.makeOverridable (
      {
        legacySource ? null,
      }:
      import ../../terminal/tests/deployment.nix {
        inherit
          pkgs
          inputs
          bootstrap
          legacySource
          ;
        source = pkgs.folio.source;
        prepareInput = collection.packages.manager-input;
        runtime = collection.packages.manager-runtime;
        cli = collection.packages.manager-cli;
        editor = catalogue.emacs.packages.editor;
        modules = adapters "system";
      }
    ) { };
    tools = import ./developer-environment.nix {
      inherit pkgs;
      generation = userHome.activationPackage;
      editor = catalogue.emacs.packages.editor;
    };
    catalogue = import ./catalogue.nix { inherit pkgs catalogueLib; };
    foundation = import ../../sysrepo/tests/foundation.nix {
      inherit pkgs bootstrap;
      tools = collection.packages.sysrepo-tools;
      normalizer = collection.packages.manager-normalizer;
      sysrepo = collection.packages.sysrepo-library;
      prepareInput = collection.packages.manager-input;
    };
  }
]
