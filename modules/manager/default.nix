{
  pkgs,
  lib,
  cliCommands ? { },
}:
let
  normalizer = pkgs.callPackage ./src/normalizer.nix { };
  prepareInput = pkgs.writeShellApplication {
    name = "folio-prepare-input";
    runtimeInputs = [
      normalizer
      pkgs.jq
      pkgs.coreutils
    ];
    text = builtins.readFile ./src/prepare-input.sh;
  };
  runtime = import ./src/runtime.nix {
    inherit pkgs normalizer prepareInput;
    sysrepo = pkgs.folio.sysrepo;
    repository = pkgs.folio.repository;
  };
  client = import ./src/cli.nix {
    inherit pkgs cliCommands;
    repository = pkgs.folio.repository;
  };
  userService = folioBootstrap: {
    ExecStartPre = "${pkgs.folio.repository}/bin/folio-repository user init ${folioBootstrap}/models/user ${folioBootstrap}/user.json";
    ExecStart = "${runtime}/bin/folio-manager-subscriber user ${folioBootstrap}";
    Restart = "on-failure";
    RestartSec = 2;
    TimeoutStopSec = 5;
    UMask = "0077";
  };
in
{
  subscribers = {
    user = [ "folio-manager.service" ];
    system = [ "folio-manager.service" ];
  };
  models = {
    system = [
      ./model/folio-environment.yang
      ./model/folio-deployment.yang
    ];
    user = [
      ./model/folio-environment.yang
      ./model/folio-deployment.yang
    ];
  };
  packages = {
    inherit normalizer runtime;
    cli = client.cli;
    input = prepareInput;
    atomic = runtime.atomic;
    cli-support = pkgs.writeTextDir "share/folio/client-common.sh" (
      builtins.readFile ./src/client-common.sh
    );
  };
  commands = lib.mapAttrs (_: adapter: {
    path = "${adapter}/bin/${adapter.meta.mainProgram}";
    scopes = [
      "user"
      "system"
    ];
  }) client.adapters;
  nixosModule =
    context:
    args@{ folioBootstrap, ... }:
    let
      folioInput = args.folioInput or null;
      descriptor = pkgs.writeText "folio-system-descriptor.json" (
        builtins.toJSON {
          format = 1;
          environment = context.identity.environment;
          platform = context.identity.platform;
          users = context.identity.users;
          preferences = context.globals;
          capabilities = context.capabilities // {
            system-repository = true;
          };
          origin = "system-generation";
        }
      );
      publish = pkgs.writeShellApplication {
        name = "folio-publish-system-descriptor";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.jq
        ];
        text = ''
          install -d -m 0755 /run/folio/public
          temporary=$(mktemp /run/folio/public/.descriptor.XXXXXX)
          trap 'rm -f "$temporary"' EXIT
          jq -cS . ${descriptor} >"$temporary"
          chmod 0444 "$temporary"
          mv -T "$temporary" /run/folio/public/system-descriptor.json
        '';
      };
    in
    {
      users.groups.folio-operators = { };
      users.users.folio-builder = {
        isSystemUser = true;
        group = "folio-builder";
        home = "/var/lib/folio-builder";
        createHome = true;
      };
      users.groups.folio-builder = { };
      environment.systemPackages = [
        client.cli
        runtime
      ];
      system.systemBuilderCommands =
        let
          configuration =
            if folioInput == null then
              "${folioBootstrap}/system.json"
            else
              pkgs.writeText "folio-system-input.json" (builtins.toJSON folioInput.configuration);
        in
        ''
          ${normalizer}/bin/folio-normalize ${folioBootstrap}/models/system ${configuration} > "$out/folio-configuration.json"
          configuration_digest=$(${pkgs.coreutils}/bin/sha256sum < "$out/folio-configuration.json")
          ${pkgs.jq}/bin/jq -cnS --arg digest "''${configuration_digest%% *}" \
            --arg environment ${lib.escapeShellArg context.identity.environment} \
            --arg bootstrap ${lib.escapeShellArg (toString folioBootstrap)} \
            --slurpfile configuration "$out/folio-configuration.json" \
            '{format:1,scope:"system",environment:$environment,bootstrap:$bootstrap,
              configurationDigest:$digest,configuration:$configuration[0]}' > "$out/folio-system.json"
        '';
      systemd.user.services.folio-manager = {
        description = "Folio user configuration subscriber";
        wantedBy = [ "default.target" ];
        unitConfig.ConditionUser = "folio";
        serviceConfig = userService folioBootstrap;
      };
      systemd.services.folio-manager = {
        description = "Folio system configuration subscriber";
        wantedBy = [ "multi-user.target" ];
        after = [
          "local-fs.target"
          "nix-daemon.service"
        ];
        wants = [ "nix-daemon.service" ];
        serviceConfig = {
          User = "root";
          Group = "folio-operators";
          Environment = [ "HOME=/root" ];
          StateDirectory = "folio";
          StateDirectoryMode = "0750";
          RuntimeDirectory = "folio";
          RuntimeDirectoryMode = "0755";
          RuntimeDirectoryPreserve = "yes";
          ExecStartPre = [
            "${pkgs.folio.repository}/bin/folio-repository system init ${folioBootstrap}/models/system ${folioBootstrap}/system.json"
            "${publish}/bin/folio-publish-system-descriptor"
          ];
          ExecStart = "${runtime}/bin/folio-manager-subscriber system ${folioBootstrap}";
          Restart = "on-failure";
          RestartSec = 2;
          UMask = "0007";
        };
      };
    };
  homeManagerModule = context: { folioBootstrap, ... }: {
    home.packages = [
      client.cli
      runtime
    ];
    systemd.user.services.folio-manager = {
      Unit = {
        Description = "Folio user configuration subscriber";
      };
      Service = userService folioBootstrap;
      Install.WantedBy = [ "default.target" ];
    };
  };
}
