{ pkgs }:
pkgs.buildNpmPackage {
  pname = "folio-dsh";
  version = "0.2.1-rc.2";
  src = pkgs.lib.fileset.toSource {
    root = ./.;
    fileset = pkgs.lib.fileset.unions [ ./package.json ./package-lock.json ];
  };
  nodejs = pkgs.nodejs_24;
  npmDepsHash = "sha256-1dcIDK763wu3lhFBL2cKhfz7lV+53sNs+oYhbvSg4pU=";
  npmFlags = [ "--ignore-scripts" ];
  dontNpmBuild = true;
  nativeBuildInputs = [ pkgs.autoPatchelfHook pkgs.python3 pkgs.makeWrapper pkgs.pkg-config ];
  buildInputs = [ pkgs.stdenv.cc.cc.lib pkgs.vips ];
  SHARP_FORCE_GLOBAL_LIBVIPS = "1";
  npm_config_nodedir = "${pkgs.nodejs_24}";
  npm_config_build_from_source = "true";
  postBuild = ''
    export PATH="$PWD/node_modules/.bin:$PATH"
    node-gyp rebuild --directory node_modules/node-pty
    (cd node_modules/sharp && node install/build.js)
    node node_modules/@deepseek-ai/dsh-subprocess-local/scripts/ensure-spawn-helper.mjs
    # Upstream probes machine code in official Node binaries to access internals.
    # Nix's compiler output differs; use Node's explicit internal-module flag.
    patch -p1 -d node_modules/node-addon-require-builtin < ${./expose-internals.patch}
  '';
  installPhase = ''
    runHook preInstall
    # This package targets glibc NixOS; bundled musl alternatives cannot load here.
    rm -r node_modules/@koromix/koffi-linux-x64/musl_x64 \
      node_modules/@deepseek-ai/node-addon-system-linux-x64/bin/musl
    mkdir -p $out/lib/folio-dsh $out/bin
    cp -R node_modules $out/lib/folio-dsh/
    makeWrapper ${pkgs.nodejs_24}/bin/node $out/bin/dsh \
      --add-flags "--expose-internals $out/lib/folio-dsh/node_modules/@deepseek-ai/dsh/lib/bin.js" \
      --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.nodejs_24 pkgs.pnpm pkgs.bashInteractive pkgs.gitMinimal pkgs.ripgrep pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.gnused pkgs.gawk pkgs.util-linux pkgs.which ]}
    runHook postInstall
  '';
  meta = {
    description = "Pinned official DeepSeek Harness with Nix-built terminal support";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = pkgs.lib.licenses.mit;
    mainProgram = "dsh";
    platforms = [ "x86_64-linux" ];
  };
}
