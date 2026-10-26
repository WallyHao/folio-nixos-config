{ pkgs }:
pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "lxgw-wenkai-gb";
  version = "1.530";

  src = pkgs.fetchurl {
    url = "https://github.com/lxgw/LxgwWenKaiGB/releases/download/v${finalAttrs.version}/lxgw-wenkai-gb-v${finalAttrs.version}.tar.gz";
    hash = "sha256-QsEefftGIYZkxAUI0/v+IYV4KZKv82Br9zk+OTzHrRY=";
  };

  nativeBuildInputs = [ pkgs.installFonts ];

  meta = {
    description = "Simplified Chinese LXGW WenKai GB fonts, including the monospaced family";
    homepage = "https://github.com/lxgw/LxgwWenKaiGB";
    license = pkgs.lib.licenses.ofl;
    platforms = pkgs.lib.platforms.all;
  };
})
