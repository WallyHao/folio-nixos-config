{
  pkgs,
  bootstrap,
  repository,
  maintenance,
  agentsHistory,
  terminalHistory,
  applicationsHistory,
  systemModules,
  homeManager,
  runtime,
  prepareInput,
  source,
  inputs,
  switcher,
}:
let
  previousModels = import ../../manager/tests/previous-theme-models.nix { inherit pkgs; };
  previousBootstrap =
    pkgs.lib.concatMapStringsSep "\n" (model: ''
      for scope in user system; do
        if [[ -f "$out/models/$scope/${model.name}" ]]; then
          rm "$out/models/$scope/${model.name}"
          cp ${model.path} "$out/models/$scope/${model.previousName or model.name}"
          jq --arg scope "$scope" --arg name "${model.name}" --arg previous "${
            model.previousName or model.name
          }" \
            '.models[$scope] |= map(if .name==$name then .name=$previous else . end)' $out/identities.json >identity.json
          mv identity.json $out/identities.json
        fi
      done
    '') previousModels
    + ''
      for scope in user system; do
        for model in "$out/models/$scope/"*.yang; do
          hash=$(sha256sum <"$model"); hash=''${hash%% *}
          jq --arg scope "$scope" --arg name "$(basename "$model")" --arg hash "$hash" \
            '.models[$scope] |= map(if .name==$name then .sha256=$hash else . end)' $out/identities.json >identity.json
          mv identity.json $out/identities.json
        done
      done
    '';
  harness = pkgs.runCommand "folio-before-pi-bootstrap" { nativeBuildInputs = [ pkgs.jq ]; } ''
    mkdir $out
    cp -RL ${bootstrap}/. $out/
    chmod -R u+w $out
    ${previousBootstrap}
    cp --remove-destination ${agentsHistory}/2026-10-22/folio-agents.yang $out/models/user/folio-agents.yang
    jq '."folio-environment:environment".modules |= map(
      if .name=="agents" then ."folio-agents:agents"={
        codex:{enabled:false,theme:false,"shell-completion":false},dsh:{enabled:true}}
      elif .name=="neovim" then .name="emacs"
      else . end)' ${bootstrap}/user.json >$out/user.json
    jq --arg hash "$(sha256sum <$out/models/user/folio-agents.yang | cut -d' ' -f1)" \
      '.models.user |= map(if .name=="folio-agents.yang" then .sha256=$hash else . end)' \
      $out/identities.json >identities.json
    mv identities.json $out/identities.json
  '';
  adoptionSource =
    pkgs.runCommand "folio-legacy-adoption-source"
      {
        nativeBuildInputs = [
          pkgs.jq
          pkgs.folio.normalizer
          prepareInput
          repository
          maintenance
          pkgs.nix
        ];
      }
      ''
        mkdir $out
        cp -R ${source}/. $out/
        chmod -R u+w $out
        # Generate candidate data through the same complete, hash-bound chain
        # used by maintenance, including shared model changes.
        export HOME=$TMPDIR/home XDG_STATE_HOME=$TMPDIR/state XDG_RUNTIME_DIR=$TMPDIR/run
        export NIX_REMOTE=local NIX_STATE_DIR=$TMPDIR/nix-state NIX_LOG_DIR=$TMPDIR/nix-log
        export NIX_CONFIG='substituters ='
        mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
        nix-store --load-db <${
          pkgs.closureInfo {
            rootPaths = [
              old
              bootstrap
            ];
          }
        }/registration
        jq --arg account "$(id -un)" '."folio-environment:environment".account=$account' ${old}/user.json >defaults.json
        folio-repository user init ${old}/models/user defaults.json
        folio-repository-maintain user snapshot adoption ${old} ${old} >snapshot.json
        folio-repository-maintain user prepare adoption ${bootstrap} >prepared.json
        jq '."folio-environment:environment".account="folio"' \
          "$XDG_STATE_HOME/folio/backups/repositories/adoption/new-running.json" >configuration.json
        folio-prepare-input configuration.json ${bootstrap} >$out/folio-input.json
      '';
  adoptedHome =
    (import ../../manager/src/outputs.nix {
      inputs = inputs // {
        self.outPath = adoptionSource;
      };
    }).homeConfigurations.folio.activationPackage;
  legacyHome =
    (homeManager.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        {
          home.username = "folio";
          home.homeDirectory = "/home/folio";
          home.stateVersion = "26.05";
          programs.zsh = {
            enable = true;
            dotDir = "/home/folio/.config/zsh";
          };
          systemd.user.services.niri = {
            Unit = {
              Description = "Legacy session sentinel";
              X-SwitchMethod = "keep-old";
              BindsTo = [ "graphical-session.target" ];
              Before = [ "graphical-session.target" ];
            };
            Service.ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
            Install.WantedBy = [ "default.target" ];
          };
          home.file.".config/folio-legacy-fixture".text = "retained legacy fixture\n";
          home.extraBuilderCommands = ''
            printf '%s\n' '{"protocolVersion":1,"schemaVersion":1,"user":"folio","home":"/home/folio"}' >$out/sylphy-home.json
          '';
        }
      ];
    }).activationPackage;
  old = pkgs.runCommand "folio-before-agents-bootstrap" { nativeBuildInputs = [ pkgs.jq ]; } ''
    mkdir $out
    cp -RL ${bootstrap}/. $out/
    chmod -R u+w $out
    ${previousBootstrap}
    rm $out/models/user/folio-agents.yang
    cp ${agentsHistory}/2026-10-19/folio-codex.yang $out/models/user/
    cp ${terminalHistory}/2026-10-19/folio-git.yang $out/models/user/
    cp --remove-destination ${terminalHistory}/2026-10-21/folio-terminal.yang $out/models/user/
    cp --remove-destination ${applicationsHistory}/2026-10-18/folio-applications.yang $out/models/user/
    jq '."folio-environment:environment".modules |=
      (map(if .name=="agents" then {name:"codex",enabled:true,
         "folio-codex:codex":{theme:false,"shell-completion":false}}
       elif .name=="neovim" then .name="emacs"
       else . end) + [{name:"git",enabled:true,"folio-git:git":{
         "user-name":"Fixture Contributor","user-email":"fixture@example.invalid",
         "github-cli":false,"default-branch":"trunk","pull-rebase":false}}])' \
      ${bootstrap}/user.json >$out/user.json
    jq --arg codex "$(sha256sum <$out/models/user/folio-codex.yang | cut -d' ' -f1)" \
       --arg git "$(sha256sum <$out/models/user/folio-git.yang | cut -d' ' -f1)" \
       --arg terminal "$(sha256sum <$out/models/user/folio-terminal.yang | cut -d' ' -f1)" \
       --arg applications "$(sha256sum <$out/models/user/folio-applications.yang | cut -d' ' -f1)" \
      '.models.user |= (map(select(.name!="folio-agents.yang") |
        if .name=="folio-terminal.yang" then .sha256=$terminal
        elif .name=="folio-applications.yang" then .sha256=$applications else . end) +
        [{name:"folio-codex.yang",sha256:$codex},{name:"folio-git.yang",sha256:$git}] | sort_by(.name))' \
      $out/identities.json >identities.json
    mv identities.json $out/identities.json
  '';
in
pkgs.testers.runNixOSTest {
  name = "folio-agents-terminal-migration";
  nodes.machine = { lib, ... }: {
    imports = systemModules;
    _module.args.folioBootstrap = bootstrap;
    users.users.folio.linger = true;
    services.greetd.enable = lib.mkForce false;
    services.timesyncd.enable = lib.mkForce false;
    nix.settings.substituters = lib.mkForce [ ];
    virtualisation.memorySize = 4096;
    virtualisation.diskSize = 12288;
    virtualisation.writableStoreUseTmpfs = false;
    virtualisation.additionalPaths = [
      bootstrap
      old
      harness
      legacyHome
      adoptionSource
      adoptedHome
      inputs.nixpkgs
      inputs.home-manager
      pkgs.stdenvNoCC
      pkgs.shellcheck-minimal
      pkgs.lndir
      pkgs.perl
      pkgs.python3Packages.xmltodict
      pkgs.libxml2Python
    ];
    environment.systemPackages = [
      pkgs.jq
      repository
      maintenance
      runtime
      prepareInput
    ];
  };
  testScript = ''
    import datetime
    import shlex
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("folio-manager.service", user="folio")
    # The fresh matching fallback starts normally. Move only disposable state
    # aside before recreating the legacy user repository for the migration test.
    machine.succeed("runuser -u folio -- env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user stop folio-manager")
    machine.succeed("mv /home/folio/.local/state/folio /home/folio/fresh-folio-state")
    machine.succeed("mv /run/user/1000/folio /run/user/1000/fresh-folio-runtime")
    command = "bash ${./migration.sh} ${bootstrap} ${old} ${repository} ${maintenance}"
    machine.succeed("runuser -u folio -- env HOME=/home/folio XDG_RUNTIME_DIR=/run/user/1000 bash -c " + shlex.quote(command), timeout=datetime.timedelta(seconds=180))
    # A newer system fallback must defer an incompatible retained user repository
    # instead of failing activation or changing its models. Home Manager owns it.
    user_systemctl = "runuser -u folio -- env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user "
    machine.succeed(user_systemctl + "start folio-manager")
    machine.fail(user_systemctl + "is-active folio-manager")
    machine.fail(user_systemctl + "is-failed folio-manager")
    machine.succeed("journalctl _SYSTEMD_USER_UNIT=folio-manager.service _UID=1000 --no-pager | grep 'fallback subscriber deferred'")
    # Reproduce sudo's root primary group, not the service's operator primary
    # group: a restore imports datastores and used to recreate root:root files.
    machine.succeed("test $(id -gn) = root")
    machine.succeed("systemctl stop folio-network folio-system folio-manager")
    maintain = "${maintenance}/bin/folio-repository-maintain system "
    machine.succeed(maintain + "snapshot root-permissions ${bootstrap} $(readlink -f /run/current-system)")
    machine.succeed(maintain + "restore root-permissions")
    machine.succeed(maintain + "finalize root-permissions")
    machine.succeed("systemctl start folio-manager folio-network folio-system")
    machine.wait_for_unit("folio-manager.service")
    machine.wait_until_succeeds("folio --json --system status | jq -e '.status == \"success\" and .data.offline != true'")
    machine.succeed("${repository}/bin/folio-repository system ctl --list | grep 'folio-environment.*root:folio-operators'")
    command = "bash ${./adopt.sh} ${bootstrap} ${old} ${legacyHome} ${adoptionSource} ${switcher}"
    machine.succeed("runuser -u folio -- env -i HOME=/home/folio USER=folio PATH=/run/current-system/sw/bin XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus bash -c " + shlex.quote(command), timeout=datetime.timedelta(seconds=600))
    with subtest("existing agents dsh selection upgrades and restores with real sysrepo"):
        command = "bash ${./pi-migration.sh} ${bootstrap} ${harness} ${repository} ${maintenance}"
        machine.succeed("runuser -u folio -- env HOME=/home/folio bash -c " + shlex.quote(command), timeout=datetime.timedelta(seconds=180))
  '';
}
