# Stage 04: Fault recovery, migrations and managed rollback

Dependencies: 03. Status: complete.
Expected commit: `feat(manager): recover deployments and restore retained revisions`.

## Completion (2026-10-18)

- Completed module-owned revision migration, retained-revision rollback, explicit
  reference-aware cleanup and offline recovery status. Preceding submilestones
  are recorded below; `54beb78` is the paired repository recovery baseline.
- Terminal retains its exact original `2026-10-18` model and an additive
  `2026-10-19` model; `2026-10-20` changes opacity units from percent to decimal
  fraction. The registry binds both ends' model hashes and immutable transforms.
  Foot consumes the migrated alpha. No installed schema was edited in place.
- `folio rollback REVISION_ID [--rebuild]` checks immutable source/configuration,
  account, model, tool and closure identities, then restores desired data/models
  and actual closure together. Unsupported protocols require explicit compatible
  rebuilding with current manager/repository code and the retained models/adapters/
  lock. Mismatched identities fail before installation. Failed newer desired data
  is retained in the before snapshot, never implicitly reapplied after rollback.
- `folio cleanup [--apply]` previews by default, takes queue before mutation locks,
  and removes only eligible deployment records/known root links. It preserves
  current/previous success, active/locked tasks, all backup/recovery/upgrade
  references, adoption backups and mutable data. Repository backups and historical
  maintenance revisions are retained conservatively; no automatic/global GC.
- `status` exposes keyed maintenance phases and can inspect readable scoped
  journals when the subscriber/repository is unavailable. Pending maintenance
  blocks configuration commits/apply and degrades observed health. System offline
  rollback/cleanup require root; they do not introduce a new passwordless root
  execution surface.
- Actual isolated commands passed:
  - `bash modules/terminal/tests/migrations.sh /nix/store/k6y5d2ylrbyhpf14as6dpmmv2cmrw6da-folio-bootstrap /nix/store/q3ynp2sjibls6c9y4w2grijfaw7a52fs-folio-terminal-schema-history /nix/store/lc5zb32lw5kihmaawarm86b3d1mp710s-folio-repository /nix/store/1zcqk4acna252s7ay7rpf12xz95n0ry1-folio-repository-maintain`.
    Evidence `/tmp/folio-terminal-migrations.Zt4f9d`; log
    `/tmp/folio-stage04-migrations.log`. Real schema 18 -> 19 adds percent 100;
    after a real committed value of 75, 19 -> 20 yields `"0.75"` in startup and
    running. Retained data/models restore back to 18 without a reverse transform.
  - `bash modules/sysrepo/tests/maintenance.sh /nix/store/k6y5d2ylrbyhpf14as6dpmmv2cmrw6da-folio-bootstrap /nix/store/lc5zb32lw5kihmaawarm86b3d1mp710s-folio-repository /nix/store/1zcqk4acna252s7ay7rpf12xz95n0ry1-folio-repository-maintain /nix/store/6h3nyza152z83p5mddj7r19k8hay1m27-folio-manager-runtime`.
    Evidence `/tmp/folio-repository-maintenance.ZLsAkq` (see log for exact case);
    log `/tmp/folio-stage04-maintenance.log`. Reused the compact fault table with
    current models: failed migration/restoration, revision/hash refusal, stale
    inputs, active consumers, retries and missing live repository.
  - `bash modules/manager/tests/cleanup.sh /nix/store/6h3nyza152z83p5mddj7r19k8hay1m27-folio-manager-runtime /nix/store/k6y5d2ylrbyhpf14as6dpmmv2cmrw6da-folio-bootstrap`.
    Evidence `/tmp/folio-cleanup.69FDCM`; log `/tmp/folio-stage04-cleanup.log`.
    Verified preview/application, actual indirect roots, a held task lock, current/
    previous success, active work, backups and unresolved recovery protections.
- Affected common gate passed:
  `nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths path:.#manager-runtime path:.#folio path:.#checks.x86_64-linux.foundation path:.#checks.x86_64-linux.configuration`.
  Log `/tmp/folio-stage04-common-gate.log`; foundation
  `/nix/store/ailpqj3xb25g3a1kd35bb3pkjrcsk3rb-folio-foundation`, configuration
  `/nix/store/cpfrrb0m98jny0z2d04sq2xxxn1fl6rf-folio-configuration-integration`.
  This includes the prepared-only/accepted journal fault boundaries; no full
  flake or desktop suite was run.
- Final scoped guest gate passed:
  `nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths path:.#checks.x86_64-linux.recovery`.
  Output `/nix/store/jl782y0ysgvbjikq6qzi7jb3krv8kmiw-vm-test-run-folio-deployment-recovery`;
  logs `/tmp/folio-stage04-complete-gate2.log` and
  `/tmp/folio-stage04-complete-expanded.log`. Booted with original terminal schema
  18, upgraded through the real migration chain to 20 with matching activated
  Foot closure, rejected unsupported retained protocol without changes, rebuilt
  and rolled back old source/models/configuration after a later desired value 24,
  and verified desired/actual 18 after real reboot. Also proved offline root
  recovery status, failed root restore/retry, healthy paired installation, user
  restore, profile-only reconciliation, authorization and clean external shutdown.
- The first guest iteration reached successful rollback but exposed read-only
  directories in its temporary compatibility source during final cleanup. The
  copy is now made writable before use; the affected guest gate above passed.
- Reused Sylphy's Foot renderer and existing Folio guest/adoption/profile fixtures;
  reference remains `9cba023d90c4485b33a91e2d12724b6920580580`. No reference,
  development-host activation or physical target was modified.
- Commit subject: `feat(manager): recover deployments and restore retained revisions`.
  Next: Stage 05 applications. It must register its own subscribers/migrations,
  respect configuration-before-application locks and preserve the recovery roots.

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

## Offline paired maintenance submilestone (2026-10-18)

- Continued the incoming uncommitted sysrepo maintenance implementation rather
  than replacing it. Added kernel connection-lock inspection, a scoped repository
  lock shared by all registered subscribers/clients, and the schema transaction
  barrier. The public catalogue publishes subscriber and migration registries.
- Repository primitives snapshot raw data/models, normalized startup/running
  exports, configuration/deployment journals and GC roots. Candidate preparation
  validates isolated real repositories and retains failed candidates on retry.
  Changed schemas without a revision are rejected; migration edges bind exact
  model hashes and must advance revisions monotonically. Closure binding checks
  bootstrap/configuration identity and the scoped account before installation.
- Added `folio-manager-maintain SCOPE BOOTSTRAP snapshot|upgrade|restore ID
  [FROZEN_SOURCE]`, independent of manager RPC availability. It rejects active
  tasks/VM jobs and unresolved recovery, takes the scoped mutation lock, stops
  registered consumers and journals their prior active state. Runtime service
  conditions retain quiescence across NixOS activation; runtime masks alone did
  not override the generated `/etc/systemd/system` units in the real guest.
- Upgrade builds immutable candidate source/bootstrap/closure as the scoped user
  or unprivileged `folio-builder`. It checks frozen input and migrated data before
  installation, activates/verifies the paired closure and publishes a rooted
  maintenance revision. A failed installation/activation attempts paired restore;
  failed restoration leaves its barrier and consumer conditions for explicit
  retry. Consumers restart only after releasing the mutation lock; actual status
  RPC readiness is required when the manager was previously active.
- Reviewed Sylphy adoption/profile authority again at
  `9cba023d90c4485b33a91e2d12724b6920580580`; retained Folio's existing profile,
  unique adoption backups and recorded closure verification instead of copying
  the reference's manager architecture.
- Isolated primitive command passed:
  `bash modules/sysrepo/tests/maintenance.sh /nix/store/11ffiizjcz07ixan9vpsv6yzbd5p5ncc-folio-bootstrap /nix/store/lc5zb32lw5kihmaawarm86b3d1mp710s-folio-repository /nix/store/qpwwzclv90lxvkxxx3xpvc3yl5am9v2z-folio-repository-maintain /nix/store/6f3nm8f6x7qsfyzw2ljvw1chylrcqw8f-folio-manager-runtime`.
  Evidence: `/tmp/folio-repository-maintenance.KLXUpp`. Covered a real occupied
  subscriber, stale snapshot refusal, same-revision schema refusal, a failing
  hash-bound test migration, explicit preparation retry/evidence retention,
  invalid closure refusal, denied restore and the missing-live-directory boundary.
  The closure fixture deliberately refuses activation; this is repository/binding
  evidence only. Later engine changes adjust the system candidate umask/primary group;
  system coverage belongs to the scoped guest gate below.
- Affected shared-lock checks passed in one batch:
  `nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths path:.#checks.x86_64-linux.foundation path:.#checks.x86_64-linux.configuration path:.#checks.x86_64-linux.catalogue`.
  Outputs: `/nix/store/p3z0zymk9335sj5g1h65xmsfnix2w6d6-folio-foundation`,
  `/nix/store/g7r0kj5g2x14fjvlzxrigv2lnsln75a4-folio-configuration-integration`,
  `/nix/store/8nhk87cpdy591c0ngmz5bjj728ihb4s9-folio-catalogue-contract`.
  Later C diagnostic changes affect only root permission errors; the new system
  candidate permissions and coordinator are covered by the guest gate, without another
  full suite repetition.
- Stage remains **in progress**. Production migration transforms, a successful
  additive/meaning-changing schema transition, general retained-revision rollback
  (including old-protocol rebuild), and explicit reference-aware cleanup remain.
  The current production migration registry is empty. No application/desktop
  stage or physical hardware acceptance is claimed.
- Scoped guest gate passed:
  `nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths path:.#checks.x86_64-linux.recovery`.
  Output `/nix/store/6rxa51zzrs5d1ids8f6f4cpj4dr126rk-vm-test-run-folio-deployment-recovery`;
  build log `/tmp/folio-recovery-paired-gate7.log`, expanded log
  `/tmp/folio-paired-passed7.log`. Proved root/user snapshot restore of matching
  desired data and actual closure, retained root failure barrier and successful
  explicit retry, unchanged boot ID, real manager RPC readiness, rooted backups
  and root candidate installation/healthy publication followed by paired restore.
  The candidate has unchanged production models: this is not evidence of a
  successful schema transformation. Existing interruption/authorization/reboot/
  clean-poweroff assertions also passed in the same bounded fixture.
- Failed focused gate iterations exposed premature service restart, wrong root
  datastore group and absent optional services. The root JSON datastore uses the
  caller's primary group for replacement files: candidate commands now use
  `setpriv --regid folio-operators --keep-groups`, matching the provisioned service.
  Consumer stopping skips an optional not-found unit while retaining its activation
  condition. Added explicit root permission diagnostics and RPC readiness checks.
- After that guest gate, factored the already-tested snapshot closure identity
  check into a helper and reused it immediately before explicit/automatic restore
  activation, so a mismatched retained artifact cannot be activated. The final
  package passed ShellCheck/build via
  `nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths path:.#manager-runtime`;
  output `/nix/store/r6qvqkzai04nyybs8sy13bcnwmn75jxj-folio-manager-runtime`,
  log `/tmp/folio-maintenance-runtime-identity.log`. Reused the guest's positive
  snapshot identity and failed-missing-closure cases instead of repeating its
  complete fixture for this additional identical validation.
- Submilestone subject: `feat(manager): coordinate offline paired repository recovery`.
