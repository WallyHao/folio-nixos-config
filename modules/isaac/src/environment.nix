{ pkgs }:
pkgs.buildFHSEnv {
  name = "isaac-fhs";
  targetPkgs =
    p: with p; [
      bashInteractive
      coreutils
      findutils
      gnugrep
      gnused
      gawk
      util-linux
      python312
      uv
      git
      curl
      cacert
      jq
      file
      binutils
      patchelf
      gcc
      cmake
      ninja
      pkg-config
      gnumake
      zlib
      openssl
      libffi
      libxml2_13
      libGL
      libglvnd
      vulkan-loader
      vulkan-tools
      libx11
      libxcb
      libxcursor
      libxi
      libxrandr
      libxinerama
      libxext
      libxrender
      libxfixes
      libxkbcommon
      libxt
      libice
      libsm
      libxxf86vm
      wayland
      dbus
      glib
      nss
      nspr
      alsa-lib
      fontconfig
      freetype
      libdrm
      libunwind
      libuuid
      numactl
      pciutils
      which
    ];
  multiPkgs = _: [ ];
  profile = ''
    export UV_PYTHON_DOWNLOADS=never
    export PYTHONNOUSERSITE=1
    export SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
    export LD_LIBRARY_PATH="/run/opengl-driver/lib:/usr/lib:''${LD_LIBRARY_PATH:-}"
    if [ -f /run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json ]; then
      export VK_DRIVER_FILES=/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json
    fi
  '';
  runScript = pkgs.writeShellScript "isaac-fhs-entry" ''
    if [ "$#" -eq 0 ]; then exec /bin/bash -i; fi
    exec "$@"
  '';
}
