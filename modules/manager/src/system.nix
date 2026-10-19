{ pkgs, lib, client, runtime, normalizer }:
let userService = import ./user-service.nix { inherit pkgs runtime; };
in
context:
    { folioBootstrap, folioInput ? null, ... }:
    let
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
      # Raw module composition (including guest fixtures) has no frozen input.
      _module.args.folioInput = lib.mkDefault null;
      users.groups.folio-operators = { };
      users.users.folio-builder = {
        isSystemUser = true;
        group = "folio-builder";
        home = "/var/lib/folio-builder";
        createHome = true;
      };
      users.groups.folio-builder = { };
      environment.systemPackages = [
        pkgs.folio.frontend
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
            '{format:1,workerProtocol:1,scope:"system",environment:$environment,bootstrap:$bootstrap,
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
    }
