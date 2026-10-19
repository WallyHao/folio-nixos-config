# Stage 08: Remaining network and system capabilities

Dependencies: 07. Status: complete (2026-10-19).
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

## Implementation record (2026-10-19)

- Stage 07 completed in `d09467b` after tools and real profile gates. Stage 06
  remains complete in `6cec01f`. Both left a clean worktree at their commits.
- Inspected Sylphy NetworkManager, Mihomo local socket/provider rendering,
  firewall, OpenSSH, locale/time/TTY/journald/zram/Nix policy and selected public
  host settings at `9cba023d90c4485b33a91e2d12724b6920580580`. No provider contents,
  credentials, host hardware identifiers or private network records were read.
- Added system-owned network YANG, C subscriber, Bash/jq client, bounded native
  connection/proxy actions and actual status. NetworkManager owns DNS policy;
  Mihomo uses loopback and a private Unix controller. Optional provider YAML is a
  runtime systemd credential. OpenSSH uses public-key authentication; firewall
  remains enabled by default. No manager routing of network operations.
- Extended system policy with an exact retained 2026-10-18 model and hash-bound
  additive 2026-10-19 migration. Guest storage labels are separate from explicit
  physical device identifiers. Physical settings require disabling the public
  prototype password; no real target configuration or installation is claimed.
- NixOS output evaluation, network package/C builds and actual system-model
  normalization passed: `/tmp/folio-stage08-eval.log`,
  `/tmp/folio-stage08-components2.log`, `/tmp/folio-stage08-system-normalized.json`.
- The network/system guest reuses shared system-update instrumentation and a
  documented synthetic source carrying the exact prior system model. It does not
  claim to boot an unchanged historical release. Public `nixosModules.portable`
  provides composition without private module imports. QEMU uses its virtual RTC;
  the shared guest explicitly disables time sync and cannot attest NTP health.
- Guest evaluation passed (`/tmp/folio-stage08-network-eval3.log`). The pinned
  OpenSSH option requires a scalar AuthorizedKeysFile setting.
- Gate 1 failed before upgrade because raw test tool paths were absent from the
  guest closure; added explicit runtime/client/bootstrap/input dependencies.
  Gate 2 reached upgrade but its prebuilt closures lacked the generated Flake's
  QEMU/test modules, causing offline rebuild attempts. Aligned prebuilt and live
  compositions. Gate 3 passed upgrade, delivery, network operations, actual DNS/
  proxy HTTP, key SSH and firewall blocking, then failed its final SSH policy
  assertion: `sshd -T` did not read the service's explicit configuration path.
  Corrected the assertion to use `-f /etc/ssh/sshd_config` and retain its output.
  Gate 4 confirmed all three SSH restrictions but exposed the pinned OpenSSH's
  capitalized diagnostic keys. Made the assertion case-insensitive while retaining
  raw evidence. Gate 5 passed (`/tmp/folio-stage08-network-gate5.log`, exit 0).
- Actual libyang normalization accepted explicit physical fixture storage with
  prototype passwords disabled, and rejected missing root devices, physical
  prototype passwords, unstable `/dev/sda` paths and non-IP DNS. Fixture data and rejection logs are under
  `/tmp/folio-stage08-{physical,storage,dns}-*`; no disk was accessed.
  Physical storage/boot, Wi-Fi, TUN routing,
  real provider nodes and NTP synchronization remain unverified.

## Current reproduction commands

```sh
nix eval --raw --no-update-lock-file .#checks.x86_64-linux.network.drvPath
nix eval --json --no-update-lock-file .#nixosConfigurations.portable.config.services.timesyncd.enable
nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths -L .#checks.x86_64-linux.network
git diff --check
```

The first command evaluates the paired model and guest compositions. The second
returned `true` for production policy; the guest deliberately uses its virtual RTC.
The network check uses local DNS/HTTP fixtures, runtime-generated SSH keys and a
network namespace peer, without real provider/network credentials or host changes.

## Acceptance and delivery

- Full gate output:
  `/nix/store/fwhq9dab4gc7914aayklcpcihv3g207p-vm-test-run-folio-network-system`.
  Script: 56.24 seconds; cleanup: 0.17 seconds. No surviving QEMU/test driver.
- Final bounded catalogue/foundation checks also passed, including actual isolated
  repository initialization and preservation (`/tmp/folio-stage08-static-final.log`).
  Command: `nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths
  -L .#checks.x86_64-linux.catalogue .#checks.x86_64-linux.foundation`.
- Passed real paired system-model upgrade, operator config/plan/build/apply,
  timezone and descriptor changes, active zstd zram and journal limits.
- Real NetworkManager connect/disconnect changed the guest interface address.
  Missing profiles, unauthorized users, malformed interfaces and user scope
  failed without removing that address. Local DNS resolution and HTTP through
  Mihomo SOCKS succeeded; live mode remained separate from desired rule mode.
  Missing proxy nodes and a stopped backend returned unavailable.
- An isolated peer authenticated with an ephemeral SSH key; inbound HTTP to an
  unopened port was blocked. `folio-ssh-policy.txt` proves password/interactive
  authentication and root login are disabled. `network-status.json` retains
  actual observations and explicitly marks physical acceptance unverified.
- Reused unchanged Stage 06/07 GUI, input, application and developer-tools
  evidence; no broad rerun for network-only changes. The shared guest fixture's
  explicit time-sync override preserves its existing virtual-RTC contract.
- Commit subject: `feat(network): complete modeled connectivity and system policy`.
  Report the resulting SHA after commit; do not amend for self-reference.
- Next: Stage 09 integrated guest acceptance, with physical capabilities recorded
  separately. No host activation, real disk writes or credential import occurred.
