{ pkgs, lib, cliCommands ? { } }:
let
  normalizer = pkgs.callPackage ./normalizer.nix { };
  prepareInput = pkgs.writeShellApplication {
    name = "folio-prepare-input";
    runtimeInputs = [
      normalizer
      pkgs.jq
      pkgs.coreutils
    ];
    text = builtins.readFile ../runtime/snapshot/prepare-input.sh;
  };
  runtime = import ./runtime.nix {
    inherit pkgs normalizer prepareInput;
    sysrepo = pkgs.folio.sysrepo;
    repository = pkgs.folio.repository;
  };
  client = import ./cli.nix {
    inherit pkgs cliCommands runtime;
    repository = pkgs.folio.repository;
  };
in
{
  inherit normalizer prepareInput runtime client;
  packages = {
    inherit normalizer runtime;
    cli = client.cli;
    config-client = client.adapters.config;
    input = prepareInput;
    atomic = runtime.atomic;
    cli-support = pkgs.writeTextDir "share/folio/client-common.sh" (
      builtins.readFile ../cli/lib/output.sh
    );
  };
  commands = lib.mapAttrs (name: adapter: {
    path = "${adapter}/bin/${adapter.meta.mainProgram}";
    help = "${(
      if name == "config" then ../cli/commands/config/help.txt
      else if name == "modules" then ../cli/commands/modules/help.txt
      else if name == "rollback" || name == "cleanup" then ../cli/commands/rollback/help.txt
      else ../cli/commands/deploy/help.txt
    )}";
    scopes = [
      "user"
      "system"
    ];
  }) client.adapters;
}
