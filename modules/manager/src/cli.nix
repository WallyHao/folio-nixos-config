{
  pkgs,
  repository,
  cliCommands,
  runtime,
  bootstrapPreferences,
}:
let
  preferenceDefaults = pkgs.writeText "folio-preference-defaults.json" (
    builtins.toJSON bootstrapPreferences
  );
  common =
    builtins.replaceStrings
      [ "@normalizeFilter@" "@requestFilter@" ]
      [ "${../runtime/snapshot/normalize.jq}" "${../cli/commands/config/request.jq}" ]
      (builtins.readFile ../cli/lib/transport.sh);
  client =
    name: source: shared:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        repository
        pkgs.coreutils
        pkgs.jq
        pkgs.python3
      ];
      text =
        builtins.replaceStrings
          [ "@fields@" "@describe@" ]
          [ "${../cli/commands/config}/fields.py" "${../cli/commands/config}/describe.py" ]
          (
            "export FOLIO_CATALOGUE=${pkgs.folio.catalogue}\n"
            + "export FOLIO_PREFERENCE_DEFAULTS=${preferenceDefaults}\n"
            + builtins.readFile ../cli/lib/output.sh
            + "\n"
            + shared
            + "\n"
            + builtins.readFile source
          );
    };
  adapters = {
    config = client "folio-config" ../cli/commands/config/command.sh common;
    theme = pkgs.writeShellApplication {
      name = "folio-theme";
      runtimeInputs = [ pkgs.python3 ];
      text = ''
        export FOLIO_CONFIG_ADAPTER=${adapters.config}/bin/folio-config
        export FOLIO_WORKFLOW_ADAPTER=${workflow}/bin/folio-workflow
        export FOLIO_THEME_SOURCE=${pkgs.folio.source}
        export FOLIO_THEME_CATALOGUE=${
          pkgs.writeText "folio-theme-catalogue.json" (
            builtins.toJSON (
              builtins.mapAttrs (_: scheme: builtins.attrNames scheme.palettes) (
                import ../../appearance/lib/catalogue.nix
              )
            )
          )
        }
        exec python3 ${../cli/commands/theme/command.py} "$@"
      '';
    };
    modules = client "folio-modules" ../cli/commands/modules/command.sh common;
    plan = client "folio-deployment" ../cli/commands/deploy/command.sh "";
    build = adapters.plan;
    apply = adapters.plan;
    status = adapters.plan;
    history = adapters.plan;
    rollback = pkgs.writeShellApplication {
      name = "folio-maintenance";
      runtimeInputs = [
        runtime
        pkgs.coreutils
        pkgs.jq
      ];
      text =
        builtins.readFile ../cli/lib/output.sh
        + "\n"
        + builtins.readFile ../cli/commands/rollback/command.sh;
    };
    cleanup = adapters.rollback;
  };
  workflow = pkgs.writeShellApplication {
    name = "folio-workflow";
    runtimeInputs = [
      pkgs.python3
      pkgs.nix
      pkgs.gnutar
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      export FOLIO_DEPLOY_ADAPTER=${adapters.plan}/bin/folio-deployment
      export FOLIO_MAINTENANCE_ADAPTER=${adapters.rollback}/bin/folio-maintenance
      export FOLIO_REVIEW_COMMAND=${../runtime/snapshot/review.py}
      export FOLIO_WORKFLOW_EXECUTABLE="$0"
      exec python3 ${../cli/commands/workflow}/command.py "$@"
    '';
  };
  cli = pkgs.writeShellApplication {
    name = "folio";
    runtimeInputs = [ pkgs.jq ];
    text =
      builtins.replaceStrings
        [ "@commands@" "@workflow@" ]
        [
          (toString (pkgs.writeText "folio-commands.json" (builtins.toJSON cliCommands)))
          "${workflow}/bin/folio-workflow"
        ]
        (
          builtins.readFile ../cli/lib/arguments.sh
          + "\n"
          + builtins.readFile ../cli/lib/help.sh
          + "\n"
          + builtins.readFile ../cli/lib/commands.sh
          + "\n"
          + builtins.readFile ../cli/bin/folio.sh
        );
  };
in
{
  inherit cli adapters;
}
