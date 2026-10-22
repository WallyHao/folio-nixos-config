# Coherent pre-theme model set for historical upgrade fixtures.
{ pkgs }:
let
  owners = [ "agents" "appearance" "applications" "desktop" "devices" "emacs" "input" "manager" "network" "system" "terminal" "vm" ];
in pkgs.lib.concatMap (owner:
  map (entry: {
    inherit owner;
    name = "${entry.module}.yang";
    path = ../../. + "/${owner}/model/revisions/${entry.from}/${entry.module}.yang";
  }) (import (../../. + "/${owner}/theme-migrations.nix") { inherit pkgs; })
) owners
