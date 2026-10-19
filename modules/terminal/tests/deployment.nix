{ pkgs, inputs, source, bootstrap, prepareInput, modules, runtime, cli, editor, legacySource ? null }:
let
  legacy = if legacySource == null then null else import (legacySource + "/modules/manager/src/outputs.nix") {
    inputs = inputs // { self.outPath = legacySource; };
  };
  oldBootstrap = if legacy == null then bootstrap else legacy.packages.x86_64-linux.manager-bootstrap;
  descriptor = pkgs.runCommand "folio-tools-test-descriptor" { nativeBuildInputs = [ pkgs.jq ]; } ''
    jq '.origin="system-generation" | .capabilities += {"system-repository":true}' ${bootstrap}/system-descriptor.json >$out
  '';
  prepared = name: base: config: modelBootstrap: pkgs.runCommand name { nativeBuildInputs = [ prepareInput ]; } ''
    mkdir $out
    cp -R ${base}/. $out/
    chmod -R u+w $out
    folio-prepare-input ${config} ${modelBootstrap} ${descriptor} >$out/folio-input.json
  '';
  old = prepared "folio-tools-old-source" (if legacy == null then source else legacySource) "${oldBootstrap}/user.json" oldBootstrap;
  upgraded = prepared "folio-tools-schema-upgrade" source "${oldBootstrap}/user.json" bootstrap;
  selected = prepared "folio-tools-selected" source "${bootstrap}/user.json" bootstrap;
  disabledConfig = pkgs.runCommand "folio-tools-disabled.json" { nativeBuildInputs = [ pkgs.jq ]; } ''
    jq '."folio-environment:environment".modules |= map(
      if (.name=="emacs" or .name=="agents") then .enabled=false
      elif .name=="terminal" then ."folio-terminal:terminal".tools.fzf=false |
        ."folio-terminal:terminal".git.enabled=false else . end)' \
      ${bootstrap}/user.json >$out
  '';
  disabled = prepared "folio-tools-disabled" source disabledConfig bootstrap;
  generation = seed: (import (seed + "/modules/manager/src/outputs.nix") {
    inputs = inputs // { self.outPath = seed; };
  }).homeConfigurations.folio.activationPackage;
in pkgs.testers.runNixOSTest {
  name = "folio-tools-deployment";
  nodes.machine = { lib, ... }: {
    imports = modules;
    _module.args.folioBootstrap = bootstrap;
    services.greetd.enable = lib.mkForce false;
    services.timesyncd.enable = lib.mkForce false;
    systemd.user.services.folio-manager.serviceConfig = {
      ExecStartPre = lib.mkForce "${pkgs.folio.repository}/bin/folio-repository user init ${oldBootstrap}/models/user ${oldBootstrap}/user.json";
      ExecStart = lib.mkForce "${runtime}/bin/folio-manager-subscriber user ${oldBootstrap}";
    };
    environment.systemPackages = [ pkgs.jq ];
    nix.settings.substituters = lib.mkForce [ ];
    virtualisation = {
      memorySize = 4096; cores = 2; diskSize = 12288;
      writableStoreUseTmpfs = false;
      additionalPaths = [ old upgraded selected disabled
        (generation old) (generation upgraded) (generation selected) (generation disabled)
        inputs.nixpkgs inputs.home-manager pkgs.stdenvNoCC pkgs.shellcheck-minimal pkgs.lndir pkgs.perl ];
    };
  };
  testScript = ''
    import datetime
    import json
    import shlex

    def user(command, timeout=240):
        prefix = "runuser -u folio -- env -i HOME=/home/folio USER=folio LOGNAME=folio TERM=xterm-256color PATH=/home/folio/.nix-profile/bin:/etc/profiles/per-user/folio/bin:/run/current-system/sw/bin:/run/wrappers/bin XDG_STATE_HOME=/home/folio/.local/state XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus bash -c "
        return machine.succeed(prefix + shlex.quote("set -euo pipefail; " + command), timeout=datetime.timedelta(seconds=timeout))

    def folio(arguments):
        return json.loads(user("${cli}/bin/folio --json " + arguments, 600))

    def apply(seed):
        result = folio("plan --source " + seed)
        assert result["status"]=="success", result
        identity = result["data"]["planId"]
        assert folio("build " + identity)["status"]=="success"
        assert folio("apply " + identity)["status"]=="success"
        user("systemctl --user is-active folio-manager folio-applications folio-devices")

    def configure(path):
        assert folio("config import " + path)["status"]=="success"

    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("folio-manager.service", user="folio")
    apply("${old}")
    ${pkgs.lib.optionalString (legacy != null) ''
    with subtest("paired terminal revision and new tool model upgrade"):
        user("${runtime}/bin/folio-manager-maintain user ${oldBootstrap} upgrade developer-models ${upgraded}", 600)
        user("folio-repository user ctl --list | grep folio-emacs")
    ''}
    configure("${bootstrap}/user.json")
    apply("${selected}")
    with subtest("real profile delivery and disposable note indexing"):
        # Interactive job control must not share the driver's controlling terminal.
        user("setsid --wait timeout --kill-after=2 30 zsh -i -c '[[ -n $HISTFILE ]] && (( $+functions[compdef] )) && (( $+functions[ll] ))' </dev/null >/home/folio/shell-check.log 2>&1", 40)
        user("command -v fzf; git init /home/folio/test-repository; git -C /home/folio/test-repository symbolic-ref HEAD | grep refs/heads/main; codex --version; dsh --version")
        user("test -s /home/folio/.codex/themes/folio.tmTheme; test ! -e /home/folio/.codex/auth.json")
        user("emacs --batch --load ${../../emacs/tests/org-roam.el}")
        user("printf keep > /home/folio/Documents/Notes/keep; printf keep > /home/folio/.codex/personal-state; git -C /home/folio/test-repository config user.email disposable@example.invalid")
        user("mkdir -p /home/folio/.dsh; printf keep >/home/folio/.dsh/personal-state")
    configure("${disabledConfig}")
    apply("${disabled}")
    with subtest("selection removes only owned contributions"):
        user("test ! -e /home/folio/.codex/themes/folio.tmTheme; test ! -e /home/folio/.config/folio/emacs/settings.el; test ! -e /home/folio/.config/git/config")
        user("test -z \"$(command -v fzf || true)\"; test -n \"$(command -v jq)\"")
        user("test -z \"$(command -v dsh || true)\"; grep keep /home/folio/.dsh/personal-state")
        user("grep keep /home/folio/Documents/Notes/keep; grep keep /home/folio/.codex/personal-state; ${pkgs.gitMinimal}/bin/git -C /home/folio/test-repository config --local user.email | grep disposable@example.invalid")
        user("test -s /home/folio/.local/state/folio/emacs/org-roam.db")
        assert folio("status")["data"]["health"]=="healthy"
    with subtest("offline snapshot resumes the larger profile within its readiness budget"):
        user("${runtime}/bin/folio-manager-maintain user ${bootstrap} snapshot tools-snapshot", 90)
        assert folio("status")["data"]["health"]=="healthy"
        user("${cli}/bin/folio --json status >/home/folio/tools-status.json")
        machine.copy_from_machine("/home/folio/tools-status.json")
  '';
}
