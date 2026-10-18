{
  pkgs,
  repository,
  cliCommands,
}:
let
  common = builtins.replaceStrings [ "@normalizeFilter@" ] [ "${./normalize.jq}" ] (
    builtins.readFile ./client-common.sh
  );
  client =
    name: source:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        repository
        pkgs.coreutils
        pkgs.jq
      ];
      text = common + "\n" + builtins.readFile source;
    };
  adapters = {
    config = client "folio-config" ./config-client.sh;
    modules = client "folio-modules" ./modules-client.sh;
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
