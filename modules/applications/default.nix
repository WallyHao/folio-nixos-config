{ pkgs, lib }:
let
  files = pkgs.stdenv.mkDerivation {
    pname = "folio-applications-files";
    version = "0.1.0";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.jansson pkgs.openssl ];
    buildPhase = ''
      $CC -std=c11 -Wall -Wextra -Werror -O2 ${./src/files.c} $(pkg-config --cflags --libs jansson openssl) -o folio-applications-files
    '';
    installPhase = "mkdir -p $out/bin; cp folio-applications-files $out/bin/";
  };
  transaction = pkgs.stdenv.mkDerivation {
    pname = "folio-applications-transaction";
    version = "0.1.0";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.flatpak pkgs.jansson ];
    buildPhase = ''
      $CC -std=gnu11 -Wall -Wextra -Werror -O2 ${./src/transaction.c} $(pkg-config --cflags --libs flatpak jansson) -o folio-applications-transaction
    '';
    installPhase = "mkdir -p $out/bin; cp folio-applications-transaction $out/bin/";
  };
  runtime = import ./src/runtime.nix { inherit pkgs files transaction; };
in
{
  models.user = [ ./model/folio-applications.yang ];
  subscribers.user = [ "folio-applications.service" ];
  packages = { inherit files transaction; inherit (runtime) worker tools subscriber; };
  commands.apps = { path = "${runtime.client}/bin/folio-apps"; scopes = [ "user" ]; };
  nixosModule = context: { services.flatpak.enable = true; };
  homeManagerModule = context: { folioBootstrap, ... }: {
    assertions = [{ assertion = context.capabilities.flatpak-provisioned or false; message = "Applications require system-provisioned Flatpak support"; }];
    home.packages = [ pkgs.flatpak ];
    systemd.user.services.folio-applications = {
      Unit = {
        Description = "Folio owned applications subscriber";
        Requires = [ "folio-manager.service" ];
        After = [ "folio-manager.service" ];
      };
      Service = {
        Environment = "FOLIO_BOOTSTRAP=${folioBootstrap}";
        ExecStartPre = [ "${runtime.tools}/bin/folio-applications-tool ready" "${runtime.tools}/bin/folio-applications-tool recover" ];
        ExecStart = "${runtime.subscriber}/bin/folio-applications-subscriber";
        Restart = "on-failure";
        UMask = "0077";
      };
      Install.WantedBy = [ "default.target" ];
    };
    home.extraBuilderCommands = ''
      cp ${pkgs.writeText "folio-applications.json" (builtins.toJSON (import ./src/manifest.nix {
        inherit pkgs lib context;
        configurationDigest = context.configurationDigest or null;
      }))} $out/folio-applications.json
    '';
  };
}
