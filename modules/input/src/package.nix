{ pkgs, candidateCount ? 7 }:
let
  profile = pkgs.writeText "folio-fcitx5-initial-profile" ''
    [Groups/0]
    Name=Default
    Default Layout=us
    DefaultIM=rime

    [Groups/0/Items/0]
    Name=keyboard-us
    Layout=

    [Groups/0/Items/1]
    Name=rime
    Layout=

    [GroupOrder]
    0=Default
  '';
  rimeDefaults = pkgs.writeText "folio-rime-initial-defaults.yaml" ''
    patch:
      __include: rime_ice_suggestion:/
      menu/page_size: ${toString candidateCount}
      ascii_composer/switch_key/Shift_L: commit_code
      ascii_composer/switch_key/Shift_R: commit_code
  '';
in pkgs.writeShellApplication {
  name = "folio-input-seed";
  runtimeInputs = [ pkgs.coreutils ];
  text = builtins.replaceStrings [ "@profile@" "@rimeDefaults@" ] [ "${profile}" "${rimeDefaults}" ]
    (builtins.readFile ../runtime/operations/seed.sh);
}
