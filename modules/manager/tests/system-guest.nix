# Test instrumentation is imported explicitly by the generated fixture Flake.
# The production portable target never imports this module.
{ lib, ... }:
{
  virtualisation = {
    useBootLoader = true;
    useEFIBoot = true;
    useBIOSBoot = false;
    memorySize = 3072;
    cores = 2;
    writableStoreUseTmpfs = false;
  };
  system.switch.enable = true;
  # The disposable QEMU fixture follows its virtual RTC; production time-sync
  # policy is evaluated separately and this guest does not attest NTP health.
  services.timesyncd.enable = lib.mkForce false;
  nix.settings.substituters = lib.mkForce [ ];
  users.users.visitor = {
    isNormalUser = true;
    uid = 1001;
  };
}
