{ pkgs }:
let
  source = pkgs.runCommand "folio-retirement-fixture-source" { } ''
    mkdir $out
    echo '{}' >$out/flake.nix
    echo '{"name":"folio"}' >$out/folio-target.json
  '';
  client = pkgs.writeShellScriptBin "folio" ''
    set -eu
    while [[ $1 == --* ]]; do shift; done
    case "$1 ''${2:-}" in
      'config export') cp /var/lib/fixture-desired.json "$3" ;;
      'config import') cp "$3" /var/lib/fixture-desired.json; echo '{"status":"success"}' ;;
      'plan --source') echo '{"status":"success","data":{"planId":"fixture"}}' ;;
      'status '*) echo '{"status":"success","data":{"health":"healthy"}}' ;;
      'build fixture') echo '{"status":"success"}' ;;
      'apply fixture')
        if [[ -e /var/lib/fixture-fail-apply ]]; then
          echo '{"status":"error"}'
        else
          echo '{"status":"success"}'
        fi
        ;;
      *) exit 2 ;;
    esac
  '';
  services = pkgs.writeShellScriptBin "systemctl" ''
    case "$1" in
      is-active) exit 0 ;;
      show) echo 'provider.yaml:/var/lib/folio-mihomo-private/provider.yaml' ;;
      *) exit 2 ;;
    esac
  '';
in pkgs.testers.runNixOSTest {
  name = "folio-legacy-retirement-files";
  nodes.machine = { ... }: {
    networking.hostName = "folio";
    users.users.folio = { isNormalUser = true; uid = 1000; };
    environment.systemPackages = [ pkgs.jq pkgs.util-linux pkgs.getent pkgs.diffutils pkgs.inetutils ];
    environment.etc."folio-test/retire-legacy.sh".source = ../runtime/retire-legacy.sh;
    virtualisation.memorySize = 1024;
  };
  testScript = ''
    import json
    import shlex

    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /etc/sylphy /var/lib/sylphy-mihomo /var/lib/sylphy-mihomo-private /var/lib/folio-mihomo /var/lib/folio/backups")
    machine.succeed("printf private-fixture >/var/lib/sylphy-mihomo-private/provider.yaml; chmod 600 /var/lib/sylphy-mihomo-private/provider.yaml")
    machine.succeed("printf retained-fixture >/etc/sylphy/fixture; printf '{}' >/var/lib/folio-mihomo/config.json")
    configuration = {"folio-environment:environment": {"modules": [{"name":"network", "folio-network:network": {"proxy": {"provider-file":"/var/lib/sylphy-mihomo-private/provider.yaml"}}}]}}
    machine.succeed("printf %s " + shlex.quote(json.dumps(configuration)) + " >/var/lib/fixture-desired.json")
    runner = "env PATH=${pkgs.lib.makeBinPath [ client services ]}:$PATH bash /etc/folio-test/retire-legacy.sh"

    with subtest("failed activation retains legacy prerequisites"):
        machine.succeed("touch /var/lib/fixture-fail-apply")
        machine.fail(runner + " apply ${source}")
        machine.succeed("test -f /etc/sylphy/fixture; test -f /var/lib/sylphy-mihomo-private/provider.yaml")
        machine.succeed("cmp /var/lib/sylphy-mihomo-private/provider.yaml /var/lib/folio-mihomo-private/provider.yaml")
        machine.succeed("test $(stat -c %u:%a /var/lib/folio-mihomo-private/provider.yaml) = 0:600")

    with subtest("retry archives only after successful activation"):
        machine.succeed("rm /var/lib/fixture-fail-apply")
        machine.succeed(runner + " apply ${source}")
        machine.succeed("test ! -e /etc/sylphy; test ! -e /var/lib/sylphy-mihomo; test ! -e /var/lib/sylphy-mihomo-private")
        backup = machine.succeed("for directory in /var/lib/folio/backups/legacy-*; do test $(cat $directory/phase) != complete || echo $directory; done").strip()
        assert backup.startswith("/var/lib/folio/backups/legacy-") and "\n" not in backup
        machine.succeed("cmp " + backup + "/sylphy-mihomo-private/provider.yaml /var/lib/folio-mihomo-private/provider.yaml")
        machine.succeed("test $(stat -c %a " + backup + ") = 700")

    with subtest("explicit recovery restores prerequisites and retains the archive"):
        machine.succeed(runner + " restore-files " + backup)
        machine.succeed("test -f /etc/sylphy/fixture; test -d /var/lib/sylphy-mihomo")
        machine.succeed("cmp /var/lib/sylphy-mihomo-private/provider.yaml /var/lib/folio-mihomo-private/provider.yaml")
        machine.succeed("test -d " + backup + "/sylphy-mihomo-private")
  '';
}
