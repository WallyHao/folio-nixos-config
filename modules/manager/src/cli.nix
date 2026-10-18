{
  pkgs,
  repository,
  cliCommands,
  runtime,
}:
let
  common = builtins.replaceStrings [ "@normalizeFilter@" "@requestFilter@" ] [ "${../runtime/snapshot/normalize.jq}" "${../cli/commands/config/request.jq}" ] (
    builtins.readFile ../cli/lib/transport.sh
  );
  client =
    name: source: shared:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        repository
        pkgs.coreutils
        pkgs.jq
      ];
      text = builtins.readFile ../cli/lib/output.sh + "\n" + shared + "\n" + builtins.readFile source;
    };
  adapters = {
    config = client "folio-config" ../cli/commands/config/command.sh common;
    modules = client "folio-modules" ../cli/commands/modules/command.sh common;
    plan = client "folio-deployment" ../cli/commands/deploy/command.sh "";
    build = adapters.plan;
    apply = adapters.plan;
    status = adapters.plan;
    rollback = pkgs.writeShellApplication {
      name = "folio-maintenance";
      runtimeInputs = [ runtime pkgs.coreutils pkgs.jq ];
      text = builtins.readFile ../cli/lib/output.sh + "\n" + builtins.readFile ../cli/commands/rollback/command.sh;
    };
    cleanup = adapters.rollback;
  };
  cli = pkgs.writeShellApplication {
    name = "folio";
    runtimeInputs = [ pkgs.jq ];
    text =
      builtins.replaceStrings
        [ "@commands@" ]
        [
          (toString (pkgs.writeText "folio-commands.json" (builtins.toJSON cliCommands)))
        ]
        (builtins.readFile ../cli/lib/arguments.sh + "\n"
          + builtins.readFile ../cli/lib/help.sh + "\n"
          + builtins.readFile ../cli/lib/commands.sh + "\n"
          + builtins.readFile ../cli/bin/folio.sh);
  };
in
{
  inherit cli adapters;
}
