{ pkgs, lib }:
context:
let settings = context.settings."folio-devices:devices" or { };
in {
  security.rtkit.enable = settings.audio or true;
  services.pipewire = lib.mkIf (settings.audio or true) {
    enable = true;
    audio.enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
    systemWide = false;
  };
  hardware.bluetooth = lib.mkIf (settings.bluetooth or true) { enable = true; powerOnBoot = false; };
  services.blueman.enable = settings.bluetooth or true;
  services.udev.packages = lib.optionals (settings.brightness or true) [ pkgs.brightnessctl ];
  services.power-profiles-daemon.enable = settings.power-profiles or true;
}
