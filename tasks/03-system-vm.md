# Stage 03: System deployment and disposable UEFI guest

Dependencies: 02. Status: complete.
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

## Completed deployment and VM gate (2026-10-18)

- Prior provisioning commit: `010dff7`. Implemented system plan/build/apply using
  the existing immutable plans, durable tasks and per-scope mutation lock.
  Evaluation/build run as `folio-builder`; only the fixed root worker activates
  the recorded, metadata-verified closure. Source, worker and before/after closures
  remain rooted. User selection is independent of system activation.
- System owns its timezone model and root power subscriber. Delayed power requests
  persist prepared/accepted records, bind request IDs to actions, reject changed
  duplicates and report acceptance separately from externally observed completion.
- VM owns its YANG/RPC, C subscriber, Bash client, asynchronous build worker and
  direct QEMU/KVM/OVMF lifecycle. Added a standalone bootable qcow2 output and
  bootstrap launcher, private overlays/EFI variables/QMP sockets, user networking,
  bounded shutdown, active-job cleanup rejection and archived failure/serial logs.
  The image provides `/etc/folio/source` and pinned inputs, without host mounts.
- Reused Sylphy's image/provisioning/profile patterns inspected at revision
  `9cba023d90c4485b33a91e2d12724b6920580580`; retained Folio's independent
  repositories, direct QEMU and C/Bash implementation. No reference-tree changes.
- Passing final guest command:
  `nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths path:.#checks.x86_64-linux.system-deployment`.
  Evidence: `/nix/store/56la33g302kc9nfjc9fzhbb7y4axp28r-vm-test-run-folio-system-deployment`;
  log `/tmp/folio-stage03-release3.log`. Actual UTC activation, non-root builder,
  operator authorization, rejected arbitrary payloads, both repositories after
  reboot and unchanged Foot font/user profile passed. The offline fixture imports
  its seed from the same frozen source, including an internal symlink; no runtime
  substitutes or hidden development-directory imports are required.
- Boot IDs: `57c109a4-068f-4898-a662-6b642f2bc3a6` before reboot and
  `8ff00ce8-443f-4c9f-ac6a-1dfb2b6c55ef` afterward. Selected system:
  `/nix/store/b6ikdzdm6xsrzfvjr7rbnshq7sqi9wxz-nixos-system-portable-test`;
  unchanged user generation:
  `/nix/store/0p4yzm2yh35gh5izq0w3zzjr3vq3jfaa-home-manager-generation`.
  QMP observed RESET/SHUTDOWN and QEMU exited with status 0.
- Separate actual VM lifecycle command: `bash modules/vm/tests/lifecycle.sh
  BOOTSTRAP REPOSITORY CLI VM_SUBSCRIBER VM_TOOLS IMMUTABLE_SOURCE`, using outputs
  from `manager-bootstrap`, `sysrepo-tools`, `folio`, `vm-subscriber`, `vm-tools`.
  Passed with source `/nix/store/i7ywynb3967sxjl5qviwdfr2nzk1bbhi-folio-vm-source.v6o0Jo`;
  retained evidence `/tmp/folio-vm-lifecycle.clhezc`, log
  `/tmp/folio-vm-lifecycle.log`. Subscriber restart did not cancel the image build;
  the UEFI guest reached login, cleanup refused a running guest, ACPI shutdown
  produced `phase=stopped, exitCode=0`, and explicit cleanup archived serial logs.
- Final image build: `nix build --no-link --no-update-lock-file --max-jobs 2
  --print-out-paths path:.#vm-image` produced
  `/nix/store/vi0iha821incrk5df3a19gj5pssdqyh2-folio-uefi-image`;
  log `/tmp/folio-vm-image-release.log`.
- Affected configuration/foundation checks passed in the final batch before the
  fixture-only import correction: `/nix/store/l2f363hpg7an61kb0f7akiwi1dw0bs2a-folio-configuration-integration`
  and `/nix/store/nldqlcj6jkyarf8fb7c8f3cr1g4wxl4q-folio-foundation`.
  Changed transport polling was exercised by actual Home Manager service restart;
  schema identities are compared to bootstrap identities rather than a fixed count.
  C builds use `-Wall -Wextra -Werror`; packaged Bash and lifecycle-test ShellCheck
  passed. Prior Stage 02 adoption/disable checks remain relevant and unchanged.
- Prototype account password remains `kl;'`; storage is exclusively disposable
  labeled guest disks. No host activation, host power action, push or physical
  installation. Hardware acceptance and retained-revision recovery remain pending.
- Commit subject: `feat(system): enable authorized vm system deployment`.
  Next: Stage 04, using retained plans/current records, old closures/models and
  the scoped guest fixture for recovery, migration and managed rollback.
