{ pkgs }:
context: {
  programs.dconf.enable = true;
  fonts = {
    fontconfig.enable = true;
    packages = [
      (import ./font.nix { inherit pkgs; })
      pkgs.maple-mono.NF-CN
      pkgs.noto-fonts-cjk-sans
      pkgs.noto-fonts-color-emoji
    ];
    fontconfig.defaultFonts = {
      monospace = [
        context.globals.font-family
        "Maple Mono NF CN"
      ];
      sansSerif = [ "Noto Sans CJK SC" ];
      emoji = [ "Noto Color Emoji" ];
    };
  };
}
