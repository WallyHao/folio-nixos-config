# Stage 04: Fault recovery, migrations and managed rollback

Dependencies: 03.
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
