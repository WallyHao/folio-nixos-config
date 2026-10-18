{ pkgs }:
pkgs.writeShellApplication {
  name = "folio-vm-tool";
  runtimeInputs = [
    pkgs.folio.atomicWrite
    pkgs.coreutils
    pkgs.jq
    pkgs.util-linux
    pkgs.nix
    pkgs.systemd
    pkgs.qemu_kvm
    pkgs.socat
  ];
  text =
    builtins.replaceStrings
      [ "@tool@" "@code@" "@vars@" ]
      [
        "\"$0\""
        "${pkgs.OVMF.fd}/FV/OVMF_CODE.fd"
        "${pkgs.OVMF.fd}/FV/OVMF_VARS.fd"
      ]
      (builtins.readFile ../runtime/operations/lifecycle.sh);
}
