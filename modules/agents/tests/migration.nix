{ pkgs, bootstrap, repository, maintenance, agentsHistory, terminalHistory, systemModules }:
let
  old = pkgs.runCommand "folio-before-agents-bootstrap" { nativeBuildInputs = [ pkgs.jq ]; } ''
    mkdir $out
    cp -RL ${bootstrap}/. $out/
    chmod -R u+w $out
    rm $out/models/user/folio-agents.yang
    cp ${agentsHistory}/2026-10-19/folio-codex.yang $out/models/user/
    cp ${terminalHistory}/2026-10-19/folio-git.yang $out/models/user/
    cp ${terminalHistory}/2026-10-21/folio-terminal.yang $out/models/user/
    jq '."folio-environment:environment".modules |=
      (map(if .name=="agents" then {name:"codex",enabled:true,
         "folio-codex:codex":{theme:false,"shell-completion":false}}
       else . end) + [{name:"git",enabled:true,"folio-git:git":{
         "user-name":"Fixture Contributor","user-email":"fixture@example.invalid",
         "github-cli":false,"default-branch":"trunk","pull-rebase":false}}])' \
      ${bootstrap}/user.json >$out/user.json
    jq --arg codex "$(sha256sum <$out/models/user/folio-codex.yang | cut -d' ' -f1)" \
       --arg git "$(sha256sum <$out/models/user/folio-git.yang | cut -d' ' -f1)" \
       --arg terminal "$(sha256sum <$out/models/user/folio-terminal.yang | cut -d' ' -f1)" \
      '.models.user |= (map(select(.name!="folio-agents.yang") |
        if .name=="folio-terminal.yang" then .sha256=$terminal else . end) +
        [{name:"folio-codex.yang",sha256:$codex},{name:"folio-git.yang",sha256:$git}] | sort_by(.name))' \
      ${bootstrap}/identities.json >$out/identities.json
  '';
in pkgs.testers.runNixOSTest {
  name = "folio-agents-terminal-migration";
  nodes.machine = { lib, ... }: {
    imports = systemModules;
    _module.args.folioBootstrap = bootstrap;
    users.users.folio.linger = true;
    services.greetd.enable = lib.mkForce false;
    services.timesyncd.enable = lib.mkForce false;
    nix.settings.substituters = lib.mkForce [ ];
    virtualisation.memorySize = 2048;
    virtualisation.additionalPaths = [ bootstrap old ];
    environment.systemPackages = [ pkgs.jq repository maintenance ];
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
  '';
}
