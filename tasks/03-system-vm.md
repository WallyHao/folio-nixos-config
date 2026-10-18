# Stage 03: System deployment and disposable UEFI guest

Dependencies: 02. Status: in-progress.
Expected commit: `feat(system): enable authorized vm system deployment`.

## Objective and deliverables

Provision a disposable portable guest and demonstrate authorized folio system
updates without sudo passwords. Own manager/sysrepo system integration, minimum
system/network/device prerequisites and vm model/commands/direct QEMU lifecycle.

## Ordered work

1. Inspect Sylphy account/system policies, VM/image and profile helpers. Reuse
   relevant pieces with Folio identity. Use QEMU/KVM/OVMF, temporary disks and user
   networking; no libvirt dependency, host disks, bridge changes or host shutdown.
2. Define explicit guest storage/boot, account/home/groups/shell, locale/time/TTY
   and Nix basics. Provision README's prototype password without copying unrelated
   secrets. Select valid initial NixOS/Home Manager stateVersion values.
3. Provision system repository, root manager, dedicated operator group and known
   unprivileged builder. Authorize by actual library/session identity plus local
   access policy, never JSON usernames. No blanket passwordless sudo or addition
   of folio to Nix trusted-users; first provisioning is explicitly privileged.
4. Reuse manager-local snapshots/task machinery. Root worker accepts immutable
   recorded environment/plan/closure identities and fixed activation path. Reject
   arbitrary payloads, executable paths and mutable artifacts. Keep active old
   workers/closures rooted across manager upgrades.
5. Publish real versioned read-only system identity/defaults/capabilities descriptor.
   Bind user plans to its digest, reject mismatches, and ensure system apply does
   not publish another Home Manager generation or alter its selected profile.
6. Implement vm build/start/stop/status through its own interfaces, stable IDs,
   bounded waits, logs, explicit cleanup and disposable disks. No generated images
   in source; preserve useful failure logs outside the checkout.
7. Implement system-owned reboot/poweroff. Acceptance is distinct from completion,
   which needs outside observation. Unsupported scopes fail before effects.
8. Where needed, combined updates are CLI sequences of independently submitted
   system/user/app operations, stopping on failure and reporting partial success.
   No manager application dispatch or simultaneous cross-scope locks.
9. Update root README with real guest provisioning/update commands and permissions.

## Bounded gate

Reuse one disposable UEFI guest to verify boot; both repositories/services;
authorized folio system update without sudo prompt; actual changed system setting;
unchanged user generation; desired persistence. Reject unauthorized requests and
arbitrary activation payloads with no effect. Observe reboot via changed boot ID
and clean guest poweroff externally. No physical-host tests. Missing virtualization
is a blocker for this gate, not permission to use the host or claim success.

## Handoff

Record provision/launch commands, builder/operator identity, permissions, descriptor,
profile evidence, boot IDs, power observations and retained logs. Physical target
storage/installation remains pending.

## System configuration submilestone (2026-10-18)

- Prerequisite user-deployment commit: `359aea1`.
- Added actual root/user service provisioning through the existing manager/system
  adapters, a dedicated `folio-operators` group and an unprivileged `folio-builder`
  account. Registered user lingering starts the user repository/subscriber without
  publishing a Home Manager generation. Prototype account policy remains owned by
  system, consuming manager-provided user records rather than copied host hardware.
- Root repository/SHM paths are fixed and use setgid 2770 for the provisioned group;
  control journals/plans remain root-private. Shared-library root and ordinary-user
  instances use the same pinned package. No sudo bypass or Nix trusted user added.
- Verified pinned sysrepo `_sr_session_start`/`sr_session_get_user`: implicit callback
  sessions identify the subscriber, not the requesting process. Authorization uses
  the sender library's real session-user module permission checks plus kernel
  repository/SHM permissions, the documented coarse local administrative boundary.
  Root startup verifies module owner/group/mode; no caller identity is fabricated
  from JSON or client-controlled originator data.
- Root config/module-selection/status commands are available. Privileged system
  plan/build/apply callbacks remain unregistered until their workers/targets pass
  the remaining gate. Root desired writes have no application side effects.
- Published root-owned read-only compiled system descriptor under
  `/run/folio/public/system-descriptor.json`. User plans prefer that publication,
  validate ownership/permissions and bind its exact digest, identity/defaults and
  origins. Saving different desired defaults does not publish them as applied.
- Real system singleton user/group data exposed an opaque anydata RPC round-trip
  shape loss in the pinned library. The commit RPC now carries `configuration-json`
  text, preserving RFC 7951 list/leaf-list shape until authoritative libyang
  validation. Existing development repositories require explicit schema handling;
  initialization never hot-replaces their model identity.
- Passing commands:
  - `nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths path:.#checks.x86_64-linux.system-scope path:.#checks.x86_64-linux.configuration`
  - `nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths path:.#checks.x86_64-linux.user-deployment path:.#checks.x86_64-linux.foundation path:.#checks.x86_64-linux.system-scope`
  - Final provisioning check: `nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths path:.#checks.x86_64-linux.system-scope`.
- Final scope evidence:
  `/nix/store/gzkp5iljsy210ik4rg25mqibc1r1flxv-vm-test-run-folio-system-configuration`.
  The actual product adapters provision both services; real operator access,
  non-operator denial, no passwordless sudo/trusted-user grant, separate stores,
  root saved-data restart, unchanged user desired data, compiled-vs-desired
  descriptor separation and user frozen-plan binding all passed.
- User activation regression:
  `/nix/store/p3kp8bnawn8cycr6ahfzd23i8xxzfy6m-vm-test-run-folio-user-deployment`;
  foundation `/nix/store/7z032h4pqiwa8x3xr0nlkh83an1cgdic-folio-foundation`;
  configuration `/nix/store/9mw239i91g5cn80agrafx16i3klvxg9q-folio-configuration-integration`.
  Logs: `/tmp/folio-system-provisioning.log` and
  `/tmp/folio-system-scope-regression.log`; full Nix logs remain available.
- Reuse: reviewed Sylphy VM assembly/image and provisioning/account patterns;
  retained Folio's C/Bash, independent profiles and direct-QEMU/UEFI requirement.
  No reference files or physical storage were changed.
- Submilestone subject: `feat(manager): provision isolated system configuration services`.
- Remaining: unprivileged system build/root activation workers, UEFI image and
  module-owned VM lifecycle, system-owned accepted power requests with external
  observation, changed actual system setting and preserved selected user generation.
  Stage 03 remains in progress; no system update or UEFI/power gate is claimed.
