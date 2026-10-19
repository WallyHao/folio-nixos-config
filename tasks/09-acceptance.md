# Stage 09: Integrated acceptance and separate hardware validation

Dependencies: 08 (`0ce2277`). Status: VM milestone passed; laptop configuration built; physical acceptance deferred by owner.
Combined owner-requested delivery commit: `feat(manager): add laptop hardware targets and integrated acceptance`.
Later hardware milestone: `feat(system): validate portable hardware deployment`.

## Objective and deliverables

Provide honest reproducible end-to-end evidence and accurate root README. Reuse
module tests/fixtures rather than creating an exhaustive new test matrix. VM and
physical acceptance are separate milestones; do not claim either from build success.

## Ordered work

1. Review completion records and tracked implementation against root README,
   English CLI, catalogue/scopes, source reuse, exclusions and documentation
   limits. Correct stale examples and claims, retaining useful design boundaries.
2. Select existing focused checks for composition/models, real repositories,
   persistence, scopes/activation, rollback and app/desktop behavior. Consolidate
   rather than duplicate tests or introduce a new framework.
3. Run one integrated disposable lifecycle: user Foot update; passwordless authorized
   system update; persistence; one interrupted recovery; retained rollback;
   Zen/OBS reconcile; Niri/portals/capture; externally observed reboot/poweroff.
   Include unauthorized no-effect behavior. Reuse cached artifacts and prior
   focused fault tests instead of every fault in the expensive system scenario.
4. Check runtime for accidental toolchains, private checkout imports, credentials/
   state, automatic Flatpak updates and unrooted retained closures. Check source
   for forbidden architecture/layout or unauthorized extra documentation trees.
5. Run relevant final static/check set once on the integrated revision. After a
   fix rerun affected tests; repeat the broad scenario only if assumptions changed.
6. Record/commit passing VM milestone separately. If hardware is unavailable,
   physical acceptance stays pending; never claim guest success proves graphics,
   Wi-Fi, SSD boot, brightness or actual audio/Bluetooth behavior.
7. Before physical work, identify actual machine/disks and preserve existing data.
   Obtain target-specific authorization for destructive writes or activation not
   already approved. Prepare concrete target configuration and install plan first.
   Never repartition, reboot or shut down the development host as a test fixture.
8. On the authorized real target, observe boot/graphics/Wi-Fi/audio/Bluetooth/
   brightness/input/power as applicable, preserving recovery access. Report unknown
   evidence honestly. Commit that tested hardware milestone separately.
9. Update root README for delivered installation/use/recovery/limits, plus index
   and task records. Keep logs outside source, reference evidence locations, and
   create no extra report/docs trees or module README files.

## Bounded gates

VM gate: actual documented scoped workflows observed and selected regression set
passes. Hardware gate: named target and separately recorded physical observations.
If hardware remains unavailable, record the passing VM milestone and commit while
this stage stays in-progress/blocked as appropriate. Do not mark the full hardware
objective complete. Neither gate is satisfied by Nix build output alone.

## Final handoff

Report tested revision/commit, delivered scope, exact commands/evidence, substantial
Sylphy reuse, limitations and remaining hardware inputs. The root README must let
the next operator repeat the workflow that was actually verified.

## Receiving-agent execution plan (2026-10-19)

### 1. Establish the acceptance baseline

Read HANDOFF, INDEX, WORKFLOW, SYLPHY-REUSE and the Stage 06–08 evidence before
editing. Start from implementation commit `0ce2277` plus the handoff documentation
commit. Record the actual tested revision and any changes. Stage 08's gate is
passing; there is no unfinished Stage 08 bug or intentionally running guest.

Audit root README for stale planned/implemented claims, especially verification
and installation examples. Keep product prose there, test code in the owning
module's outer `tests/`, and progress/evidence in these task files. Preserve
STRUCTURE.md as reference and do not modify AGENTS.md.

### 2. Reuse existing fixtures and close integration gaps

Inspect these implemented checks before selecting or extending them:

| Check | Primary evidence to reuse |
| --- | --- |
| `catalogue`, `foundation`, `configuration` | Composition, real repositories, validation and durable commits |
| `user-deployment`, `system-deployment`, `system-scope` | Scoped Foot/root updates, unauthorized effects, persistence and observed power |
| `recovery` | Interrupted deployment, retained rollback and model migration |
| `applications`, `desktop` | Cached Zen/OBS reconciliation, Niri, Chinese input and actual portal capture |
| `tools`, `tools-deployment` | Developer tooling, model upgrade and preserved personal state |
| `network` | Actual connection effects, DNS/SOCKS traffic, scoped failures, SSH and firewall |

These names exist under `checks.x86_64-linux`; they are not evidence of a new
integrated pass. Extend the smallest suitable existing fixture (normally manager
system-deployment plus public module/resource composition). Cover the ordered
lifecycle in item 3 above on the same disposable deployment. Include current
network/tool contributions as composition checks, reusing focused behavioral
evidence where unchanged. Keep one representative interrupted recovery; do not
repeat every fault or create a second testing framework. Register any new check
only in manager composition, and document its exact command after it exists.

### 3. Run and retain the VM milestone

Run the relevant final bounded regression set once the integrated scenario is
ready; rerun affected cases after fixes. Existing command example (not executed
as Stage 09 acceptance yet):

```sh
nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths -L \
  .#checks.x86_64-linux.catalogue .#checks.x86_64-linux.foundation \
  .#checks.x86_64-linux.configuration
```

Use HANDOFF's application/desktop overrides and external cache/source markers.
Verify each path still exists before reuse; `/tmp` and unrooted store artifacts
are not guaranteed across machines or garbage collection. If absent, prepare a
fresh isolated public cache or recover historical source from Git; never use the
host's browser/profile data. Keep logs, images and runtime evidence outside Git.

Retain actual configuration health, request/task/plan identifiers as useful,
pre/post boot IDs, external shutdown observation, capture/input evidence and
cleanup outcome. Record the tested commit, exact commands, artifact paths,
reused prior evidence and limitations. Inspect the intended diff and commit the
passing VM milestone as `test(system): verify integrated folio deployment`.

### 4. Preserve known fixture constraints

- Use virtual DRM/software Mesa under the existing Xvfb supervisor. Nested Niri
  winit cannot supply GBM capture. Do not retry host GPU passthrough/EGL paths.
- Fresh Rime readiness requires completed `user.yaml` build metadata and actual
  input; a prism file alone is insufficient. OBS first-run dialogs appear late.
- Isolate interactive Zsh from the driver's controlling terminal with `setsid`
  and null stdin. Use bounded diagnostics and close the guest after inspection.
- Prebuilt guest closures must include the same QEMU/test modules as the frozen
  fixture Flake, and every raw test tool path. Otherwise offline rebuilds or
  missing executables can masquerade as production failures.
- Inspect SSH with `sshd -T -f /etc/ssh/sshd_config`; pinned diagnostic key casing
  must not affect assertions. Shared QEMU fixtures disable time sync explicitly;
  production enables it. This does not prove NTP synchronization.

### 5. Keep hardware work a separate pending milestone

Missing inputs: named target, inspected stable disk IDs/filesystems, existing-data
preservation/recovery plan, installation/activation authorization, out-of-band SSH
keys/network credentials and optional provider data. Prepare a concrete target
configuration and plan before requesting any required authorization. Do not infer
target hardware or device IDs from Sylphy or disposable image labels.

Physical storage boot, GPU/encoder, Wi-Fi, audio/Bluetooth, brightness, TUN routing,
real provider nodes and NTP remain unverified. Mark VM and hardware results
separately in this record/INDEX; a passing VM commit cannot complete Stage 09's
hardware objective. Do not wait for hardware to deliver the authorized VM work.

## Active execution (2026-10-19)

- Starting revision: `90494f0` (implementation `0ce2277` plus handoff docs), clean
  worktree. Existing AGENTS.md is preserved. No physical target is assumed.
- Extended manager system-deployment with an `integrated-release` variant. Shared
  desktop guest instrumentation and the existing GUI/input/capture script were
  extracted into their owning outer tests and reused, preserving the software
  Mesa/Xvfb path. The frozen fixture uses matching instrumentation.
- The combined scenario covers user and authorized root updates, one interrupted
  publication replay, a second actual user deployment and retained rollback,
  cached apps, current network/tools, desktop/input/capture, unauthorized effects
  and observed reboot/poweroff with persisted scope state.
- Initial evaluation exposed missing `folioInput` in raw module composition.
  Manager now supplies a default null value; prepared inputs still override it.
  This is under integrated validation, not yet a passing release claim.
- Public cache/plan store paths from HANDOFF exist and are reused. Initial gate
  log: `/tmp/folio-stage09-integrated1.log`. No Stage 09 pass/commit yet.

- The owner selected another physical machine, then explicitly deferred physical
  acceptance. Complete the VM milestone without waiting for hardware inputs.
- Gate 1 passed user/root deployment but app cache copy exhausted the auto-sized
  UEFI partition. The integrated fixture now enables partition/filesystem growth
  to the disposable overlay capacity; production storage policy is unchanged.
  Gate 2 is `/tmp/folio-stage09-integrated2.log`. Missing external app cache/plans
  now fail before boot instead of silently omitting integrated app/capture checks.
- Catalogue/foundation/configuration passed in `/tmp/folio-stage09-static1.log`.
  CLI runtime closure audit had 184 paths and no compiler/toolchain matches.

### Owner-requested hardware target preparation

The owner subsequently requested selectable laptop/desktop hardware composition,
prioritizing the current laptop while keeping physical acceptance deferred.
Read-only discovery: Lenovo Legion Y7000 IRX9, i7-13650HX, Intel Raptor Lake UHD
00:02.0 and NVIDIA RTX 4060 Mobile 01:00.0, iwlwifi, r8169, UEFI. Current storage
is a USB Btrfs installation, not the internal NVMe. No disk or activation changes
were performed.

Manager-owned targets compose public system storage and devices hardware exports
over shared defaults. `nixosConfigurations.laptop` selects the inspected hardware
and current USB UUID/subvolume layout. Source-versioned hardware target metadata
is frozen in plans, including ordinary checkouts without that manifest. Conflicting
source targets are rejected. Desktop remains unavailable until its inventory is
known. The physical account has no prototype password and remains locked pending
explicit credential/recovery provisioning before installation.

Validation in progress: full laptop build passed in `/tmp/folio-laptop-build.log`;
frozen prepared-system evaluation preserved PRIME PCI IDs, open driver, Intel
microcode and all USB Btrfs mounts in `/tmp/folio-laptop-frozen-eval.json`.
User-deployment gate reached successful target retention/conflict assertions but
its older minimal fixture lacked the dconf activation service required by current
shared appearance. The fixture now enables dconf; rerun and final-source laptop
build are in `/tmp/folio-target-checks2.log`.

Integrated gate 3 passed both updates, cached apps, interrupted recovery, actual
second deployment and retained rollback. It then failed an incorrect SSH-enabled
test assumption: the shared desired policy intentionally disables SSH. The test
now observes that disabled service; Stage 08 retains enabled/key-auth evidence.
Gate 4 includes the hardware-target retention changes and is running in
`/tmp/folio-stage09-integrated4.log`. No integrated pass is claimed yet.

The final-source target checks and laptop build passed in
`/tmp/folio-target-checks2.log` (exit 0), including the real user-deployment gate's
new target-retention/conflict cases. Gate 4 also passed cold Chinese input but
found a test-only missing raw OBS helper path in the guest. The shared desktop
fixture now explicitly installs that helper under `/etc/folio-test/`; all frozen
root closures carry it. Gate 5: `/tmp/folio-stage09-integrated5.log`. This fixture
correction is isolated from physical driver/storage behavior; final static/laptop
build refresh is `/tmp/folio-target-final-build.log`.

## Delivered VM and laptop-preparation milestone (2026-10-19)

Gate 5 passed (exit 0):

```sh
nix build -L --no-link --no-update-lock-file --max-jobs 2 --print-out-paths --impure --expr '
  let f = builtins.getFlake (toString ./.);
      pathFrom = p: builtins.storePath (builtins.replaceStrings ["\n"] [""] (builtins.readFile p));
  in f.checks.x86_64-linux.integrated-release.override {
    cache = pathFrom /tmp/folio-stage05-cache-store;
    plans = pathFrom /tmp/folio-stage05-plans-store;
  }'
nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths \
  .#checks.x86_64-linux.catalogue .#checks.x86_64-linux.foundation \
  .#checks.x86_64-linux.configuration \
  .#nixosConfigurations.laptop.config.system.build.toplevel
```

Integrated output:
`/nix/store/fdankxaxdz0y1acq1wkag5dsfvdmf6mm-vm-test-run-folio-integrated-release`.
Guest scenario completed in 173.59 seconds; cleanup completed in 0.00 seconds,
with no remaining test guest. Evidence includes `desktop.png`, `obs-frame2.png`,
`rime-input.txt` (actual Chinese input), `release-ssh.txt`, `release-status.json`
(healthy after reboot) and `release-boot.json`. Before/after boot IDs were
`c6ad9ca1-d425-4f66-835a-976b8f8bd8f8` and
`10de245a-9cc3-4dfc-bab4-e944a20400b3`. The test externally observed QMP RESET,
then SHUTDOWN and process exit 0. Earlier gate failures are retained above and
are not counted as passes.

The final static/laptop command passed in `/tmp/folio-target-final-build.log`.
Laptop closure:
`/nix/store/d7hddg5y197y92vc5ma14mn4mqf7acs4-nixos-system-portable-26.11.20261011.7fd4004`.
The affected real-user deployment gate also passed, including frozen target
retention and source-target rejection:
`nix build --no-link --no-update-lock-file --max-jobs 2 .#checks.x86_64-linux.user-deployment`
(batched with the selected checks and laptop build in
`/tmp/folio-target-checks2.log`). Its closure was
`/nix/store/bai5x04q6hp2jhhh8l826fhihwsx4amy-vm-test-run-folio-user-deployment`.
The only subsequent source changes were the isolated shared desktop test helper
correction, covered by integrated gate 5 and the final static/laptop refresh.

Readonly reference inspected: `../sylphy-nixos-config`, revision
`9cba023d90c4485b33a91e2d12724b6920580580`, including
`host/portable/hardware.nix`. Reused the existing Btrfs subvolume/mount policy,
replacing reference labels with freshly observed current USB UUIDs. Existing
Folio desktop/software fixtures and focused Stage 04–08 gates supply the broader
recovery/migration, app lifecycle, tools removal, DNS/proxy/key-only SSH evidence;
those full matrices were not rerun. CLI runtime closure audit found 184 paths
and no gcc-wrapper/rustc/cargo/clang-wrapper/pkg-config names.

AGENTS.md and STRUCTURE.md are unchanged. One root Flake/lock and module-owned
src/cli/runtime/model/tests remain intact; no separate host/home trees, private
host profiles, source credentials or automatic app-update policy were introduced.
Root README now documents targets, immutable selection, commands and limitations.
Commit subject: `feat(manager): add laptop hardware targets and integrated acceptance`.

Remaining boundary: physical boot/graphics/encoder, Wi-Fi, audio/Bluetooth,
brightness, suspend/battery, external displays, NTP and real provider/TUN behavior
are not established by these VM/build results. No physical installation or
development-host activation occurred. Desktop inventory, intended disk choice,
credentials/recovery and explicit target authorization are future prerequisites.
