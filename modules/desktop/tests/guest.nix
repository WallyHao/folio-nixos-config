# Shared disposable session instrumentation; never imported by production.
{ pkgs, drm ? true }:
let
  testPython = pkgs.python3.withPackages (p: [ p.websocket-client p.pillow ]);
  softwareQemu = pkgs.symlinkJoin {
    name = "folio-capture-software-qemu";
    paths = [ pkgs.qemu_kvm ];
    postBuild = ''
      rm "$out/bin/qemu-system-x86_64"
      ln -s ${pkgs.writeShellScript "folio-capture-qemu" ''
        export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
        export SDL_VIDEODRIVER=x11 __GLX_VENDOR_LIBRARY_NAME=mesa
        export LIBGL_DRIVERS_PATH=${pkgs.mesa}/lib/dri
        export __EGL_VENDOR_LIBRARY_FILENAMES=${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json
        export LD_LIBRARY_PATH=${pkgs.mesa}/lib
        unset WAYLAND_DISPLAY
        ${builtins.replaceStrings
          [ "@coreutils@" "@xvfb@" "@qemu@" ]
          [ "${pkgs.coreutils}" "${pkgs.xorg.xorgserver}/bin/Xvfb" "${pkgs.qemu_kvm}/bin/qemu-system-x86_64" ]
          (builtins.readFile ./qemu-software.sh)}
      ''} "$out/bin/qemu-system-x86_64"
    '';
  };
  exportSession = pkgs.writeShellApplication {
    name = "folio-test-export-niri-session";
    runtimeInputs = [ pkgs.systemd pkgs.dbus pkgs.coreutils ];
    text = ''
      systemctl --user import-environment WAYLAND_DISPLAY DISPLAY NIRI_SOCKET XDG_CURRENT_DESKTOP XDG_SESSION_TYPE
      dbus-update-activation-environment WAYLAND_DISPLAY DISPLAY NIRI_SOCKET XDG_CURRENT_DESKTOP XDG_SESSION_TYPE
      touch "$XDG_RUNTIME_DIR/folio-test-session-exported"
    '';
  };
in { lib, config, ... }: {
    # Keep the helper in every guest/root-generation closure, not just in the
    # host-side driver string's references.
    environment.etc."folio-test/obs-capture.py".source = ./obs-capture.py;
    # The guest's main Niri session runs on a dedicated virtual X server. This
    # exercises real Wayland clients/portals with software GL, without claiming
    # a direct DRM or physical GPU acceptance result.
    services.greetd.enable = lib.mkForce false;
    systemd.user.services.folio-test-xserver = lib.mkIf (!drm) {
      description = "Disposable virtual display for the Niri integration gate";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.xorg.xorgserver}/bin/Xvfb :1 -screen 0 1280x800x24 -nolisten tcp -ac";
        Restart = "on-failure";
      };
    };
    systemd.services.folio-test-drm-session = lib.mkIf drm {
      description = "Disposable DRM session for actual portal capture";
      after = [ "systemd-user-sessions.service" "getty@tty1.service" ];
      conflicts = [ "getty@tty1.service" ];
      serviceConfig = {
        User = "folio";
        PAMName = "login";
        TTYPath = "/dev/tty1";
        StandardInput = "tty";
        StandardOutput = "journal";
        Environment = [ "XDG_RUNTIME_DIR=/run/user/1000" "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus" "XDG_SESSION_TYPE=wayland" "XDG_CURRENT_DESKTOP=niri" ];
        ExecStart = "${config.programs.niri.package}/bin/niri-session";
      };
    };
    systemd.user.services.niri.serviceConfig = lib.mkIf (!drm) {
      Environment = "LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath (with pkgs; [ libxcursor libxrandr libxi libx11 libxkbcommon libglvnd ])}";
      ExecStart = lib.mkForce [ "" "${config.programs.niri.package}/bin/niri --config /home/folio/.config/niri/config.test.kdl -- ${exportSession}/bin/folio-test-export-niri-session" ];
      ExecStartPost = "${pkgs.coreutils}/bin/timeout 20 ${pkgs.bash}/bin/bash -c 'until test -f /run/user/1000/folio-test-session-exported; do sleep 0.1; done'";
    };
    environment.systemPackages = [ pkgs.jq pkgs.xdotool pkgs.libnotify pkgs.wayland-utils
      pkgs.wl-clipboard pkgs.glib pkgs.pipewire pkgs.cliphist pkgs.mako config.programs.niri.package testPython ];
    virtualisation = {
      qemu.package = lib.mkIf drm (lib.mkForce softwareQemu);
      qemu.options = pkgs.lib.optionals drm [ "-vga none" "-device virtio-vga-gl" ];
      memorySize = 6144; cores = 4; diskSize = 24576;
      writableStoreUseTmpfs = false;
    };
}
