# Stage 09: Integrated acceptance and separate hardware validation

Dependencies: 08.
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
