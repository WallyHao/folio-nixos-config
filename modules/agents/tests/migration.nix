{ pkgs, bootstrap, repository, maintenance, agentsHistory, terminalHistory }:
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
  nodes.machine = {
    users.users.folio = { isNormalUser = true; uid = 1000; };
    nix.settings.substituters = [ ];
    virtualisation.additionalPaths = [ bootstrap old ];
    environment.systemPackages = [ pkgs.jq repository maintenance ];
  };
  testScript = ''
    import datetime
    import shlex
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("install -d -o folio -m 0700 /run/user/1000")
    command = "bash ${./migration.sh} ${bootstrap} ${old} ${repository} ${maintenance}"
    machine.succeed("runuser -u folio -- env HOME=/home/folio XDG_RUNTIME_DIR=/run/user/1000 bash -c " + shlex.quote(command), timeout=datetime.timedelta(seconds=180))
  '';
}
