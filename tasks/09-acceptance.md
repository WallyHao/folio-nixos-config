# Stage 09: Integrated acceptance and separate hardware validation

Dependencies: 08 (`0ce2277`). Status: pending.
VM milestone commit: `test(system): verify integrated folio deployment`.
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
