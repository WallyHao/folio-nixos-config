{ pkgs, lib }:
let
  tools = import ./src/tools.nix { inherit pkgs; };
  runtime = import ./src/runtime.nix { inherit pkgs tools; };
in
{
  packages = {
    inherit tools;
    image = import ./src/image.nix { inherit pkgs lib tools; };
    inherit (runtime) subscriber;
  };
  models.user = [ ./model/folio-vm.yang ];
  commands.vm = {
    path = "${runtime.client}/bin/folio-vm";
    scopes = [ "user" ];
  };
  nixosModule = context: { ... }: {
    users.groups.kvm = { };
    environment.etc."folio/source".source = pkgs.folio.source;
  };
  homeManagerModule = context: { ... }: {
    assertions = [
      {
        assertion = context.capabilities.kvm-access-configured or false;
        message = "Folio VM requires system-provisioned KVM access; actual device access is checked on start";
      }
    ];
    home.packages = [ tools ];
    systemd.user.services.folio-vm = {
      Unit = {
        Description = "Folio VM lifecycle subscriber";
        Requires = [ "folio-manager.service" ];
        After = [ "folio-manager.service" ];
      };
      Service = {
        ExecStart = "${runtime.subscriber}/bin/folio-vm-subscriber";
        Restart = "on-failure";
        UMask = "0077";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
