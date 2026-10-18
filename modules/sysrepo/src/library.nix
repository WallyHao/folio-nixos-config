{ pkgs, lib }:
pkgs.stdenv.mkDerivation rec {
  pname = "sysrepo";
  version = "3.7.11";
  src = pkgs.fetchFromGitHub {
    owner = "sysrepo";
    repo = "sysrepo";
    rev = "v${version}";
    hash = "sha256-v3FXY33PuM4/TXH49M6JBKweIry17TxS2ksIBm9X9wg=";
  };
  nativeBuildInputs = [
    pkgs.cmake
    pkgs.pkg-config
  ];
  buildInputs = [ pkgs.libyang ];
  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
    "-DREPO_PATH=${placeholder "out"}/var/lib/sysrepo"
    "-DENABLE_EXAMPLES=OFF"
    "-DENABLE_TESTS=OFF"
    "-DENABLE_SYSREPO_PLUGIND=OFF"
    "-DSYSREPO_UMASK=0007"
  ];
  meta = {
    description = "Pinned sysrepo library and administration tools for Folio";
    homepage = "https://github.com/sysrepo/sysrepo";
    license = lib.licenses.bsd3;
    platforms = [ "x86_64-linux" ];
  };
}
