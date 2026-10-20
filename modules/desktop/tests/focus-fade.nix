{ pkgs, niri }:
pkgs.runCommand "folio-niri-focus-fade" {
  nativeBuildInputs = [
    (pkgs.python3.withPackages (p: [ p.pillow ]))
    pkgs.xorg.xorgserver pkgs.foot pkgs.coreutils niri
  ];
  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (with pkgs; [
    libxcursor libxrandr libxi libx11 libxkbcommon libglvnd
  ]);
  LIBGL_ALWAYS_SOFTWARE = "1";
  GALLIUM_DRIVER = "llvmpipe";
  FONTCONFIG_FILE = pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts ]; };
  __EGL_VENDOR_LIBRARY_FILENAMES = "${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json";
} ''
  mkdir -p "$out"
  python ${./focus-fade.py} "$out" || {
    tail -80 "$out/niri.log"
    exit 1
  }
''
