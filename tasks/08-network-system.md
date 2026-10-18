# Stage 08: Remaining network and system capabilities

Dependencies: 07.
Expected commit: `feat(network): complete modeled connectivity and system policy`.

## Objective and deliverables

Complete system/network beyond Stage 03's minimal provisioning while preserving
the same modules, scopes, identities and protocols. No real host secret/disk copy.

## Ordered work

1. Compare delivered catalogue against README and Sylphy system/network sources.
   Fill actual omissions rather than duplicating working bootstrap adapters.
2. Complete boot/storage/account policy, locale/time, console/logging, zram and Nix.
   System records own UID/home/groups/login policy; user repositories cannot
   redefine identity. Keep explicit ownership of system-provided user services.
3. Separate physical target storage from disposable VM fixtures. Leave real disk
   IDs/mounts pending actual target inspection; never infer them from Sylphy's
   hardware.nix or the guest image. No physical install is authorized by testing.
4. Complete NetworkManager/Mihomo/DNS/firewall/OpenSSH models/adapters. Reuse
   applicable policies and renderers without private subscriptions/keys/network
   records. Required secrets are explicit deployment-time inputs, not build data.
5. Implement concrete connection/proxy actions using network-owned subscriptions,
   scoped adapters and modeled errors/results. Reject prerequisites/scope failures
   before effects; keep configured intent distinct from observed connectivity.
6. Make effects bounded/observable. Test network changes in guests, preserving
   host connectivity. Do not open broad ports or weaken credentials for test ease.
7. Update public descriptor/capability facts and user findings. Check that later
   migrations have not duplicated audio/device/system option ownership.
8. Update root README for actual actions, scope/account rules, secret injection
   and real deployment/hardware limitations.

## Bounded gate

Evaluate affected outputs/schemas. Use one representative guest network/proxy
success/failure case with local fixtures, checking DNS/firewall/SSH against
isolated endpoints as applicable. Reuse system-update fixture for a changed
setting and descriptor. No rerun of all editor/Flatpak/recovery tests for unrelated
network changes. Physical Wi-Fi/storage boot remains separate Stage 09 evidence.

## Handoff

Record actual policies/actions, source reuse, scoped observations, remaining secret
or target inputs and which physical capabilities are still unverified.
