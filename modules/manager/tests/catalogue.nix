{ pkgs, catalogueLib }:
let
  valid = {
    manager = {
      homeManagerModule = context: { };
    };
  };
  collection = catalogueLib.collect valid;
  rejected = value: !(builtins.tryEval (builtins.deepSeq value true)).success;
  cases = [
    (rejected (
      catalogueLib.select {
        inherit collection;
        scope = "invalid";
        selections = [ ];
      }
    ))
    (rejected (
      catalogueLib.select {
        inherit collection;
        scope = "user";
        selections = [
          {
            name = "missing";
            enabled = true;
          }
        ];
      }
    ))
    (rejected (
      catalogueLib.select {
        inherit collection;
        scope = "system";
        selections = [
          {
            name = "manager";
            enabled = true;
          }
        ];
      }
    ))
    (rejected (
      catalogueLib.collect {
        a.commands.config = {
          path = ./catalogue.nix;
          scopes = [ "user" ];
        };
        b.commands.config = {
          path = ./catalogue.nix;
          scopes = [ "system" ];
        };
      }
    ))
    (rejected (
      catalogueLib.collect {
        a.commands.config = {
          path = ./catalogue.nix;
          scopes = [ "invalid" ];
        };
      }
    ))
    (rejected (
      catalogueLib.collect {
        a.models.user = [ ../model/folio-environment.yang ];
        b.models.user = [ ../model/folio-environment.yang ];
      }
    ))
  ];
in
assert builtins.all (value: value) cases;
pkgs.runCommand "folio-catalogue-contract" { } ''
  echo 'Unknown modules, unsupported scopes, duplicate commands/models rejected' > $out
''
