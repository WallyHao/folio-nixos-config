{
  inputs,
  pkgs,
  bootstrap,
  composition,
}:
let
  inherit (composition) context adapters prepared;
in
inputs.home-manager.lib.homeManagerConfiguration {
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
}
