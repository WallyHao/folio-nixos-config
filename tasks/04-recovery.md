# Stage 04: Fault recovery, migrations and managed rollback

Dependencies: 03. Status: in-progress.
Expected commit: `feat(manager): recover deployments and restore retained revisions`.

## Objective and deliverables

Complete interruption handling in both scopes, schema/data upgrades and offline
restore. Deliver rollback of retained closure plus matching desired configuration.
Own manager recovery/journals and sysrepo schema upgrade integration.

## Ordered work

1. Review actual Stage 02/03 effect boundaries and Sylphy adoption/profile helpers.
   Preserve working formats unless a necessary change has an explicit migration.
2. Harden atomic journal replacement and durable file/directory flushing. Prepared-
   only config records restore old data; accepted records roll forward. Reconcile
   startup/running before consumers. Save failure never means deployed success.
3. Recover interrupted effects by probing actual profiles/services and recorded
   before/after state. Never blindly rerun activation/destructive commands. Restore
   only recorded reversible effects; expose recovery-required if restoration fails.
4. Enforce per-scope/account mutation locks, future user-config before application
   lock ordering, no simultaneous cross-scope locks, preactivation revision checks
   and preservation of inputs referenced by active tasks.
5. Serialize schema upgrades, quiesce subscribers, export startup/running and model
   revisions, migrate an isolated copy, validate, install and restart. Retain old
   repository/closure pair and restore both on failure before resuming. No hot
   schema changes. Provide offline restore independent of the running manager.
6. Keep migrations module-owned and versioned by YANG revisions. Demonstrate a
   small additive revision and a meaning-changing data migration; no second API
   version scheme or generic application action router.
7. Implement rollback preflight and execution restoring retained closure, desired
   data and models together. Unsupported old protocols require rebuilding old
   source with the current protocol. Stop on mismatch; do not automatically
   reapply a later failed desired revision. Preserve mutable app data boundaries.
8. Maintain GC roots for current/previous success, active tasks and recovery records.
   Cleanup is explicit and excludes referenced inputs; no implicit boot pruning.
   Preserve unique unmanaged-file adoption backups and later conflict evidence.
9. Expose real rollback/recovery states and root README recovery/upgrade procedures.

## Bounded gate

Use a compact fault table: prepared-before-accept, accepted-before-startup,
activation interruption, failed migration and failed restoration. Cover distinct
boundaries, not every instruction. Prove rollback restores desired and actual
revision together and boot does not reapply failed desired data. Inspect GC roots
and cleanup selection without repetitive global GC. Use real isolated repositories
and one scoped system VM recovery case, reusing Stage 03 fixtures/closures.

## Handoff

Record journal/recovery entry points, backup/migration/offline restore commands,
fault evidence, lock order, retained generations and rollback limits. These are
prerequisites for application lifecycle work, not indefinitely deferred features.

## Execution baseline (2026-10-18)

- Stage 03 commit: `9c0e62a`; its system/VM gate passed before this stage started.
- Reviewed manager's prepared/accepted configuration journal, task dispatch,
  profile selection and activation boundaries, plus Sylphy's
  `manager/scripts/home-authority.py` and `manager/nix/adoption.nix` at reference
  revision `9cba023d90c4485b33a91e2d12724b6920580580`.
- Preserve the existing scoped mutation locks, unique adoption backups and rooted
  immutable inputs. Recovery must distinguish observable completed effects from
  ambiguous partial activation; build success is insufficient evidence.

## Effect reconciliation submilestone (2026-10-18)

- Added durable before/profile-selected/activation-returned checkpoints and
  retained revision records containing matching configuration, model/tool
  identities, bootstrap, source, artifact and previous deployment identity.
- Startup probes actual effects under the scoped mutation lock. It completes a
  verified successful publication without reactivation, or restores only the
  recorded profile while actual effects still match the before closure. Ambiguous
  effects/restoration failure remain recovery-required, visible in status and
  operational state, and block subsequent apply. No destructive retry is inferred.
- Hardened atomic replacement to report close errors before rename and clean up
  closed temporary files on failure; new revision directories are flushed before
  publishing records. Existing unique adoption backups and GC roots are retained.
- Real scoped VM command passed:
  `nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths path:.#checks.x86_64-linux.recovery`.
  Evidence `/nix/store/93fici1da0gkams85a38bgkq2xpnpsk0-vm-test-run-folio-deployment-recovery`;
  log `/tmp/folio-recovery-effects-gate2.log`. Covered publication interruption,
  actual denied user-profile restoration, visible degraded state/apply rejection,
  successful later profile-only reconciliation and root profile restoration without
  reboot or changing the running UTC system/user generation. Reused the Stage 03
  UEFI fixture and its power/authorization assertions.
- Service readiness uses actual RPC availability after startup reconciliation;
  systemd's active state alone does not imply that subscriptions are ready.
- After the atomic-close hardening, reran the affected real-repository gate:
  `nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths path:.#checks.x86_64-linux.configuration`.
  Passed: `/nix/store/djfi89fs8dsj1hwf31s9ygphjr2f7pyr-folio-configuration-integration`;
  log `/tmp/folio-recovery-atomic-gate.log`. This includes denied durable writes
  and both prepared-only and accepted-before-startup recovery. The scoped VM
  evidence above covers unchanged activation/reconciliation behavior.
- Remaining Stage 04 gate: explicit managed rollback, offline paired repository/
  closure backup/restore, additive and meaning-changing migrations, failed
  migration/restore evidence and explicit reference-aware cleanup. Stage remains
  in progress; none of these commands are claimed implemented yet.
- Submilestone subject: `fix(manager): reconcile interrupted deployment effects`.
