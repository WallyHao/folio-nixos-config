{
  pkgs,
  lib,
  client,
  runtime,
  normalizer,
}:
let
  userService = import ./user-service.nix { inherit pkgs runtime; };
  userBootstrapCondition =
    bootstrap:
    pkgs.writeShellApplication {
      name = "folio-user-bootstrap-compatible";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.diffutils
        pkgs.folio.sysrepo
      ];
      text = ''
        state="''${XDG_STATE_HOME:-$HOME/.local/state}/folio"
        [[ -f "$state/model-identity" ]] || exit 0
        expected=$(mktemp)
        trap 'rm -f "$expected"' EXIT
        for model in ${bootstrap}/models/user/*.yang; do
          printf '%s ' "$(basename "$model")" >>"$expected"
          sha256sum <"$model" >>"$expected"
        done
        sysrepoctl --version >>"$expected"
        if ! cmp -s "$expected" "$state/model-identity"; then
          echo 'User repository requires a separate paired upgrade; system fallback subscriber deferred.' >&2
          exit 1
        fi
      '';
    };
in
context:
{
  folioBootstrap,
  folioInput ? null,
  ...
}:
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
  system.build.folioDescriptor = descriptor;
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
    unitConfig.ConditionUser =
      context.bootstrapAccount or (import ./defaults.nix { scope = "user"; })
      ."folio-environment:environment".account;
    # A system update must not force the system's newer user schemas onto
    # an independently managed (or still legacy) Home Manager generation.
    serviceConfig = userService folioBootstrap // {
      ExecCondition = "${userBootstrapCondition folioBootstrap}/bin/folio-user-bootstrap-compatible";
    };
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
