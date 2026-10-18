{
  pkgs,
  lib,
  cliCommands ? { },
}:
let
  normalizer = pkgs.callPackage ./src/normalizer.nix { };
  prepareInput = pkgs.writeShellApplication {
    name = "folio-prepare-input";
    runtimeInputs = [
      normalizer
      pkgs.jq
      pkgs.coreutils
    ];
    text = builtins.readFile ./src/prepare-input.sh;
  };
  runtime = import ./src/runtime.nix {
    inherit pkgs normalizer prepareInput;
    sysrepo = pkgs.folio.sysrepo;
    repository = pkgs.folio.repository;
  };
  client = import ./src/cli.nix {
    inherit pkgs cliCommands;
    repository = pkgs.folio.repository;
  };
in
{
  models = {
    system = [
      ./model/folio-environment.yang
      ./model/folio-deployment.yang
    ];
    user = [
      ./model/folio-environment.yang
      ./model/folio-deployment.yang
    ];
  };
  packages = {
    inherit normalizer runtime;
    cli = client.cli;
    input = prepareInput;
  };
  commands = lib.mapAttrs (_: adapter: {
    path = "${adapter}/bin/${adapter.meta.mainProgram}";
    scopes = [ "user" ];
  }) client.adapters;
  nixosModule = context: { };
  homeManagerModule = context: { folioBootstrap, ... }: {
    home.packages = [
      client.cli
      runtime
    ];
    systemd.user.services.folio-manager = {
      Unit = {
        Description = "Folio user configuration subscriber";
      };
      Service = {
        ExecStartPre = "${pkgs.folio.repository}/bin/folio-repository user init ${folioBootstrap}/models/user ${folioBootstrap}/user.json";
        ExecStart = "${runtime}/bin/folio-manager-subscriber user ${folioBootstrap}";
        Restart = "on-failure";
        RestartSec = 2;
        TimeoutStopSec = 5;
        UMask = "0077";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
