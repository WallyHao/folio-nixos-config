{ pkgs, migration }:
pkgs.testers.runNixOSTest {
  name = "folio-account-migration";
  nodes.machine = { ... }: {
    users.users.sylphy = { isNormalUser = true; uid = 1000; initialPassword = "fixture-only"; };
    environment.systemPackages = [ migration pkgs.jq ];
    system.stateVersion = "26.05";
    virtualisation.memorySize = 1024;
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    # Source the exact packaged helper definitions without running its dispatcher.
    machine.succeed("sed '/^action=/,$d' ${migration}/bin/folio-migrate-account >/root/identity-functions")
    machine.succeed("mkdir -p /home/sylphy/.config/zen/profile /home/sylphy/.local/share/keyrings /home/sylphy/.local/state/nix/profiles /nix/var/nix/profiles/per-user/sylphy /nix/var/nix/gcroots/per-user/sylphy")
    machine.succeed("printf fixture-cookie >/home/sylphy/.config/zen/profile/cookies.sqlite; printf encrypted-fixture >/home/sylphy/.local/share/keyrings/login.keyring; chmod 600 /home/sylphy/.local/share/keyrings/login.keyring; chown -R 1000:users /home/sylphy")
    machine.succeed("ln -s /home/sylphy/.config/zen/profile /home/sylphy/absolute-profile; ln -s ${pkgs.hello} /home/sylphy/.local/state/nix/profiles/retained; ln -s /home/sylphy/.local/state/nix/profiles/retained /home/sylphy/.nix-profile")
    machine.succeed("getent shadow sylphy | cut -d: -f2 >/root/before-hash; stat -c '%i %u %g %a' /home/sylphy/.local/share/keyrings/login.keyring >/root/before-inode")
    machine.succeed("bash -c 'source /root/identity-functions; rename_identity'")
    assert machine.succeed("getent passwd folio | cut -d: -f3,6").strip() == "1000:/home/folio"
    machine.fail("getent passwd sylphy")
    machine.succeed("getent shadow folio | cut -d: -f2 | cmp - /root/before-hash; stat -c '%i %u %g %a' /home/folio/.local/share/keyrings/login.keyring | cmp - /root/before-inode")
    assert machine.succeed("cat /home/folio/absolute-profile/cookies.sqlite").strip() == "fixture-cookie"
    assert machine.succeed("/home/folio/.nix-profile/bin/hello").strip() == "Hello, world!"
    machine.succeed("test -z \"$(find /home/folio -xtype l -print -quit)\"; test -d /nix/var/nix/profiles/per-user/folio; test -d /nix/var/nix/profiles/per-user/sylphy")
    machine.succeed("bash -c 'source /root/identity-functions; restore_identity'")
    assert machine.succeed("getent passwd sylphy | cut -d: -f3,6").strip() == "1000:/home/sylphy"
    machine.fail("getent passwd folio")
    machine.succeed("getent shadow sylphy | cut -d: -f2 | cmp - /root/before-hash; stat -c '%i %u %g %a' /home/sylphy/.local/share/keyrings/login.keyring | cmp - /root/before-inode")
    assert machine.succeed("cat /home/sylphy/absolute-profile/cookies.sqlite").strip() == "fixture-cookie"
    machine.succeed("test -L /home/folio; test -z \"$(find /home/sylphy -xtype l -print -quit)\"")
    # A generation switch also changes /etc/static. Preserve the legacy native
    # clients' descriptors rather than leaving their second symlink hop broken.
    machine.succeed("mkdir -p /etc/sylphy /var/lib/folio-migration/legacy-etc; printf fixture-policy >/var/lib/folio-migration/legacy-etc/zsh.json; ln -s /etc/static/missing-legacy-file /etc/sylphy/zsh.json")
    machine.succeed("${migration}/bin/folio-migrate-account restore-context")
    assert machine.succeed("cat /etc/sylphy/zsh.json").strip() == "fixture-policy"
  '';
}
