# Stage 03: System deployment and disposable UEFI guest

Dependencies: 02.
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
