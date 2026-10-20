{ pkgs, inputs, cleanup }:
let
  physical = (import ../../manager/src/outputs.nix {
    inherit inputs;
    targetName = "folio";
  }).nixosConfigurations.folio.config;
  evidence = pkgs.writeText "folio-retired-system.json" (builtins.toJSON {
    hostname = physical.networking.hostName;
    mutableUsers = physical.users.mutableUsers;
    password = physical.users.users.folio.hashedPassword;
    keyring = physical.services.gnome.gnome-keyring.enable;
    restartLogin = physical.systemd.services.greetd.restartIfChanged;
    credentials = physical.systemd.services.folio-mihomo.serviceConfig.LoadCredential;
    proxyCommand = physical.systemd.services.folio-mihomo.serviceConfig.ExecStart;
    aliases = physical.systemd.services.folio-mihomo.aliases;
    tmpfiles = physical.systemd.tmpfiles.rules;
    restoresLegacy = physical.system.activationScripts ? folioLegacyContext;
    packages = map pkgs.lib.getName physical.environment.systemPackages;
  });
in pkgs.runCommand "folio-legacy-retirement" { nativeBuildInputs = [ pkgs.jq ]; } ''
  jq -e '
    .hostname=="folio" and .mutableUsers and .password==null and .keyring and
    (.restartLogin|not) and (.restoresLegacy|not) and
    (.credentials==["provider.yaml:/var/lib/folio-mihomo-private/provider.yaml"]) and
    (.proxyCommand|endswith("-d /var/lib/folio-mihomo -f /var/lib/folio-mihomo/config.json")) and
    (all(.aliases[]; contains("sylphy")|not)) and
    (all(.tmpfiles[]; contains("sylphy")|not)) and
    (all(.packages[]; .!="folio-migrate-account"))' ${evidence}
  if ${cleanup}/bin/folio-retire-legacy apply /nonexistent >refusal.log 2>&1; then
    echo 'Cleanup unexpectedly accepted an unprivileged invocation' >&2
    exit 1
  fi
  grep -F 'Run with sudo' refusal.log
  mkdir $out
  cp ${evidence} $out/system.json
''
