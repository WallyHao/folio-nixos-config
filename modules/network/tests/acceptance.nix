{ pkgs, inputs, source, bootstrap, runtime, cli, prepareInput, guestInstrumentation, oldSystemModel }:
let
  fixtureFlake = pkgs.writeText "folio-network-test-flake.nix" ''
    {
      inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
        home-manager = { url = "github:nix-community/home-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
      };
      outputs = inputs:
        let base = import ./modules/manager/src/outputs.nix { inherit inputs; };
        in base // {
          nixosConfigurations.portable = base.nixosConfigurations.portable.extendModules {
            modules = [ (inputs.nixpkgs + "/nixos/modules/virtualisation/qemu-vm.nix")
              (inputs.nixpkgs + "/nixos/lib/testing/nixos-test-base.nix") ./modules/network/tests/guest.nix ];
          };
        };
    }
  '';
  currentSource = pkgs.runCommand "folio-network-test-source" { } ''
    mkdir $out
    cp -R ${source}/. $out/
    chmod -R u+w $out
    cp ${fixtureFlake} $out/flake.nix
    cp ${guestInstrumentation} $out/modules/network/tests/guest-base.nix
  '';
  # A documented synthetic source retains the real prior system model/hash.
  # It is not claimed to be an unchanged historic release checkout.
  initialSource = pkgs.runCommand "folio-network-prior-system-model" { } ''
    mkdir $out
    cp -R ${currentSource}/. $out/
    chmod -R u+w $out
    ${pkgs.lib.concatMapStringsSep "\n" (model: ''
      cp ${model.path} "$out/modules/${model.owner}/model/${model.name}"
    '') (import ../../manager/tests/previous-theme-models.nix { inherit pkgs; })}
    cp ${oldSystemModel} $out/modules/system/model/folio-system.yang
    substituteInPlace $out/modules/manager/src/defaults.nix \
      --replace-fail '{ name = "network"; enabled = true; }' '{ name = "network"; enabled = false; }'
  '';
  evaluate = seed: import (seed + "/modules/manager/src/outputs.nix") {
    inputs = inputs // { self.outPath = seed; };
  };
  initial = evaluate initialSource;
  oldBootstrap = initial.packages.x86_64-linux.manager-bootstrap;
  descriptor = pkgs.runCommand "folio-network-prior-descriptor" { nativeBuildInputs = [ pkgs.jq ]; } ''
    jq '.origin="system-generation" | .capabilities += {"system-repository":true}' ${oldBootstrap}/system-descriptor.json >$out
  '';
  desired = pkgs.runCommand "folio-network-desired.json" { nativeBuildInputs = [ pkgs.jq ]; } ''
    jq '."folio-environment:environment".modules |= map(
      if .name=="system" then ."folio-system:system"."time-zone"="UTC"
      elif .name=="network" then ."folio-network:network"={dns:["127.0.0.1"],
        proxy:{enabled:true,tun:false,mode:"rule"},ssh:{enabled:true,port:2222,"open-firewall":true}}
      else . end)' ${bootstrap}/system.json >$out
  '';
  prepared = name: config: pkgs.runCommand name { nativeBuildInputs = [ prepareInput ]; } ''
    mkdir $out
    cp -R ${currentSource}/. $out/
    chmod -R u+w $out
    folio-prepare-input ${config} ${bootstrap} ${descriptor} >$out/folio-input.json
  '';
  upgraded = prepared "folio-network-schema-upgrade" "${oldBootstrap}/system.json";
  selected = prepared "folio-network-system-selected" desired;
  guestSystem = seed: (evaluate seed).nixosConfigurations.portable.extendModules {
    modules = [ (inputs.nixpkgs + "/nixos/modules/virtualisation/qemu-vm.nix")
      (inputs.nixpkgs + "/nixos/lib/testing/nixos-test-base.nix")
      (seed + "/modules/network/tests/guest.nix") ];
  };
  oldSystem = guestSystem initialSource;
  upgradedSystem = guestSystem upgraded;
  selectedSystem = guestSystem selected;
in pkgs.testers.runNixOSTest {
  name = "folio-network-system";
  nodes.machine = { ... }: {
    imports = [ initial.nixosModules.portable (currentSource + "/modules/network/tests/guest.nix") ];
    virtualisation.additionalPaths = [ currentSource initialSource upgraded selected desired
      runtime cli bootstrap prepareInput
      oldSystem.config.system.build.toplevel upgradedSystem.config.system.build.toplevel selectedSystem.config.system.build.toplevel
      inputs.nixpkgs inputs.home-manager pkgs.stdenvNoCC pkgs.shellcheck-minimal pkgs.lndir pkgs.perl ];
  };
  testScript = builtins.replaceStrings
    [ "@cli@" "@runtime@" "@oldBootstrap@" "@bootstrap@" "@upgraded@" "@selected@" "@desired@" ]
    [ "${cli}/bin/folio" "${runtime}/bin/folio-manager-maintain" "${oldBootstrap}" "${bootstrap}" "${upgraded}" "${selected}" "${desired}" ]
    (builtins.readFile ./acceptance.py);
}
