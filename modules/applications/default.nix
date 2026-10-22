{ pkgs, lib }:
let implementation = import ./src/package.nix { inherit pkgs lib; };
in
{
  checks.browser-windows = import ./tests/browser-windows.nix { inherit pkgs; browser = import ./src/zen.nix { inherit pkgs; }; };
  models.user = [ ./model/folio-applications.yang ];
  requirements.user.capabilities = [ "flatpak-provisioned" ];
  checks.store = import ./tests/store.nix { inherit pkgs; package = implementation.store; };
  impacts = [ "Native packages follow the user generation; Flatpak revisions use the applications lifecycle. Personal app data is retained." ];
  migrations = [{
    module = "folio-applications";
    from = "2026-10-18"; to = "2026-10-23";
    fromSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-18/folio-applications.yang;
    toSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-23/folio-applications.yang;
    transform = "${pkgs.writeShellApplication {
      name = "folio-applications-add-native";
      runtimeInputs = [ pkgs.jq ];
      text = "jq -ceS .";
    }}/bin/folio-applications-add-native";
  } {
    module = "folio-applications";
    from = "2026-10-23"; to = "2026-10-24";
    fromSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-23/folio-applications.yang;
    toSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-24/folio-applications.yang;
    transform = "${pkgs.writeShellApplication {
      name = "folio-applications-add-zathura";
      runtimeInputs = [ pkgs.jq ];
      text = "jq -ceS .";
    }}/bin/folio-applications-add-zathura";
  } {
    module = "folio-applications";
    from = "2026-10-24"; to = "2026-10-25";
    fromSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-24/folio-applications.yang;
    toSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-25/folio-applications.yang;
    transform = "${pkgs.writeShellApplication {
      name = "folio-applications-add-imv";
      runtimeInputs = [ pkgs.jq ];
      text = "jq -ceS .";
    }}/bin/folio-applications-add-imv";
  } {
    module = "folio-applications";
    from = "2026-10-25"; to = "2026-10-26";
    fromSha256 = builtins.hashFile "sha256" ./model/revisions/2026-10-25/folio-applications.yang;
    toSha256 = builtins.hashFile "sha256" ./model/folio-applications.yang;
    transform = "${pkgs.writeShellApplication {
      name = "folio-applications-unified-store";
      runtimeInputs = [ pkgs.jq ];
      text = "jq -ceS .";
    }}/bin/folio-applications-unified-store";
  }];
  subscribers.user = [ "folio-applications.service" ];
  packages = (builtins.removeAttrs implementation [ "client" ]) // {
    zen = import ./src/zen.nix { inherit pkgs; };
    schema-history = pkgs.linkFarm "folio-applications-schema-history" [
      { name = "2026-10-18/folio-applications.yang"; path = ./model/revisions/2026-10-18/folio-applications.yang; }
      { name = "2026-10-23/folio-applications.yang"; path = ./model/revisions/2026-10-23/folio-applications.yang; }
      { name = "2026-10-24/folio-applications.yang"; path = ./model/revisions/2026-10-24/folio-applications.yang; }
      { name = "2026-10-25/folio-applications.yang"; path = ./model/revisions/2026-10-25/folio-applications.yang; }
    ];
  };
  commands.apps = { path = "${implementation.client}/bin/folio-apps"; scopes = [ "user" ]; help = "${./cli/commands/applications/help.txt}"; };
  nixosModule = context: import ./src/system.nix;
  homeManagerModule = import ./src/user.nix { inherit pkgs lib; runtime = implementation; };
}
