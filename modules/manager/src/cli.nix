{
  pkgs,
  repository,
  cliCommands,
  runtime,
}:
let
  common = builtins.replaceStrings [ "@normalizeFilter@" ] [ "${./normalize.jq}" ] (
    builtins.readFile ./configuration-client-common.sh
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
      text = builtins.readFile ./client-common.sh + "\n" + shared + "\n" + builtins.readFile source;
    };
  adapters = {
    config = client "folio-config" ./config-client.sh common;
    modules = client "folio-modules" ./modules-client.sh common;
    plan = client "folio-deployment" ./deployment-client.sh "";
    build = adapters.plan;
    apply = adapters.plan;
    status = adapters.plan;
    rollback = pkgs.writeShellApplication {
      name = "folio-maintenance";
      runtimeInputs = [ runtime pkgs.coreutils pkgs.jq ];
      text = builtins.readFile ./client-common.sh + "\n" + builtins.readFile ./maintenance-client.sh;
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
        (builtins.readFile ./cli.sh);
  };
in
{
  inherit cli adapters;
}
