{ migration }:
{ lib, pkgs, ... }: {
  # Keep the machine identity stable while changing the login identity; native
  # application profile locks can include the hostname.
  networking.hostName = lib.mkForce "sylphy-portable";
  users.mutableUsers = true;
  users.users.folio = {
    extraGroups = [ "wheel" "networkmanager" ];
    # The offline rename retains the existing shadow entry. Never seed a new
    # password over it; passwd performs the later interactive password change.
    hashedPassword = lib.mkForce null;
  };
  environment.systemPackages = [ migration pkgs.seahorse ];
  system.activationScripts.folioLegacyContext = {
    deps = [ "etc" ];
    text = "${migration}/bin/folio-migrate-account restore-context";
  };
  # Activation must never create a second UID 1000 account before cutover.
  system.activationScripts.users.text = lib.mkBefore ''
    if ! ${pkgs.getent}/bin/getent passwd folio | ${pkgs.gnugrep}/bin/grep -q '^folio:[^:]*:1000:[^:]*:[^:]*:/home/folio:'; then
      echo 'Folio migration requires the offline account rename before activation' >&2
      exit 1
    fi
    if ${pkgs.getent}/bin/getent passwd sylphy >/dev/null; then
      echo 'Folio migration refuses a duplicate legacy account' >&2
      exit 1
    fi
  '';
}
