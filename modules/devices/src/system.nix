{ pkgs, lib }:
context: {
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      audio.enable = true;
      alsa.enable = true;
      pulse.enable = true;
      wireplumber.enable = true;
      systemWide = false;
    };
  }
