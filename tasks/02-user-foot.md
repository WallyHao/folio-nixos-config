# Stage 02: User configuration to Foot deployment

Dependencies: 01. Status: complete.
Expected commit: `feat(manager): deploy frozen user foot configuration`.

## Objective and deliverables

Deliver CLI -> sysrepocfg -> real C subscriber -> durable desired configuration
-> immutable plan/build -> standalone Home Manager apply -> observed Foot state.
Own manager CLI/runtime/user integration and terminal's Foot model/adapter.

## Ordered work

1. Inspect/adapt Sylphy Foot rendering, selected preferences/theme and profile
   authority/adoption helpers. Do not design a new terminal/theme implementation.
2. Compose public scoped command adapters with immutable packaged paths. Implement
   English global help/errors, typed jq requests, isolated subshells, NO_COLOR,
   --environment, --system, --json and task --no-wait. Publish config show/edit/
   import/export, modules list/enable/disable, plan/build/apply/status only with
   corresponding behavior. Incomplete rollback remains explicitly unavailable.
3. Implement real manager C subscriptions, transport/error checks and scope checks.
   JSON stdout contains one { status, data, error, taskId } envelope; progress goes
   to stderr. Exit codes are 0 success, 1 operation failure, 2 invalid usage/model,
   3 unavailable service/evidence, 4 conflict. RPC success is not task success.
4. Implement private-document optimistic editing with expected base digest and a
   commit lock. Durably prepare before/after journal, update running, durably
   accept, sync startup, then report saved. Implement basic prepared/accepted
   restart reconciliation now; Stage 04 expands faults, not basic correctness.
5. Freeze source once before validation, accepted config, system descriptor,
   model closure, tool identities and lock file. Exclude state/secrets/outputs,
   reject escaping symlinks and build only copied bytes. Record resolved public
   preferences and origins with normalized digests.
6. Implement immutable plans/build results and stale-plan checks, rechecking before
   activation. One account-owned Home Manager profile is authoritative. Preserve
   unmanaged files with unique adoption backups; later unexpected edits conflict.
   A successful build alone must never change observed applied state.
7. Implement durable task queue/IDs, phases, bounded recorded timeouts, request-ID/
   input idempotency, before/after evidence and per-account mutation locks. Persist
   before external effects. Systemd workers outlive CLI/subscriber. Root current/
   previous successful closures plus active worker/input closures against GC.
8. Apply a changed Foot setting and report actual profile/config and applied
   revision/health. Disable removes managed contributions, preserving app data.
   Interrupting the client stops waiting, not the submitted task.
9. Update root README with runnable user workflow, prerequisites and limitations.

## Bounded gate

Use isolated real repositories and disposable user activation state. One compact
integration scenario covers edit/plan/build/apply and changed Foot value; conflict;
stale plan; missing subscriber; modeled backend failure; JSON/exit semantics;
accepted config across restart. Verify editing holds no shared candidate open,
client exit preserves work, and duplicate submissions return the same task.
Reuse closures/fixtures; no desktop boot after each CLI edit or host activation.

## Handoff

Record working commands, derivations, service/worker names, profile/journal layout,
digests/locks and actual observed Foot evidence. Record unavailable evidence honestly.

## Configuration submilestone (2026-10-18)

- Prerequisite foundation commit: `a5bded7`.
- Implemented actual Bash/jq/sysrepocfg CLI config and module-selection commands,
  collected public command adapters, real user C RPC subscription and owner/session
  checks, bounded fixed-path operation execution, and Home Manager user service.
- Configuration writes use private drafts, an expected digest and a mutation
  lock. Atomic record replacement fsyncs file and directory. Prepared-only records
  restore before-data; accepted records roll after-data into running/startup before
  subscriptions start. Recovery validates journal digests and fails closed.
- Reused inspected Sylphy home-authority principles (owned state, serialized
  profile authority and durable journals), adapting implementation to C/Bash rather
  than importing its Python or Rust manager. Source reference remains 9cba023d.
- Passing check: `nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths path:.#checks.x86_64-linux.configuration`.
  Evidence: `/nix/store/vc0hi0gw55jrycyjkr9n9iv55cwn3z6p-folio-configuration-integration`.
  Real sysrepo/C callbacks cover commit persistence, private concurrent editing,
  conflict/invalid-scope/unknown-module results, actual denied journal writes,
  missing subscribers, accepted roll-forward and prepared rollback on restart.
- Pure prepared-input rendering/digest checks pass after service composition was
  added. Package build runs ShellCheck; C builds with `-Wall -Wextra -Werror`.
- Configuration maintenance tests use isolated XDG roots. No host activation or
  product system service was started. The Home Manager service is evaluated but
  its live activation remains part of the remaining stage gate.
- Submilestone subject: `feat(manager): persist user configuration through sysrepo`.
- Remaining: immutable source capture/plans, durable independent workers/tasks,
  managed profile/adoption/apply, observed Foot state and the full Stage 02 gate.
  Deployment/status/rollback CLI commands explicitly report unavailable.

## Stage completion record (2026-10-18)

- Configuration submilestone: `9add07f`. Completed immutable source capture and
  plans, independent durable build/apply workers, actual standalone Home Manager
  activation, profile/file verification and operational data publication.
- Public commands now include user `plan`, `build`, `apply`, `status`; rollback
  remains unavailable. Fixed manager-owned RPC handlers do not route app actions.
  JSON stdout is one envelope, editor/progress output uses stderr, and missing
  subscribers/invalid scopes/conflicts/backend failures preserve documented exits.
- Plans copy allowed source roots before validation, exclude environment metadata/
  state/output paths, reject escaping symlinks, add frozen RFC 7951 input and bind
  source/configuration/descriptor identities. Public preference values and origins
  are validated against the descriptor plus explicit user overrides.
- Tasks are durably queued before acknowledgement. Request-ID-derived stable task
  IDs and serialized queue records prevent duplicate effects across retries/crashes.
  `folio-task-<id>.service` transient user units run immutable recorded workers;
  recorded timeouts bound builds/activation. Active source/worker/artifact closures
  and successful previous closures remain explicitly rooted for future cleanup.
- Profile authority is `$XDG_STATE_HOME/nix/profiles/home-manager`; scoped
  `deployments/{plans,tasks,builds,roots}/` and `current.json` retain actual evidence.
  Apply serializes configuration mutations, rechecks stale config/descriptor/
  profile inputs, validates account/home/artifact identity, journals profile
  effects before activation, uses unique adoption backups, rejects later managed
  edits and verifies actual linked files. Build alone never publishes applied state.
- The C subscriber provides real `environment/configuration`, `environment/state`
  and deployment plans/tasks in operational data. Saved state compares running
  and startup; out-of-protocol maintenance edits are not reported as persisted.
- Actual passing commands:
  - `nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths path:.#checks.x86_64-linux.catalogue path:.#checks.x86_64-linux.foundation path:.#checks.x86_64-linux.configuration path:.#checks.x86_64-linux.user-deployment`
  - Final affected checks: `nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths path:.#checks.x86_64-linux.configuration path:.#checks.x86_64-linux.user-deployment`
  - Development-shell `modules/manager/tests/prepared.sh` and
    `modules/sysrepo/tests/scopes.sh`; Nixfmt, ShellCheck and `git diff --check`.
- Final evidence: `/nix/store/3vhilhaxq9fhs8zl9q4ggapnmavr1n6d-folio-configuration-integration`
  and `/nix/store/sl9h1m1a1mzvhppas5hhjy2vl0kg0c2n-vm-test-run-folio-user-deployment`.
  Logs are available with `nix log`; `/tmp/folio-stage02-final.log` records the
  final command. The guest verified actual Foot size 18, first-adoption backup,
  later conflict without overwriting edits, profile/operational-state evidence,
  disable removal, application-data preservation and persisted selection restart.
- Independent build evidence: `/tmp/folio-build-test.UOr7F1/`, source snapshot
  `/nix/store/igxpfi60481xw3gva0165l1735gwasm6-folio-input`. The real user worker
  built immutable source after poisoning the editable Foot renderer and stopping
  the subscriber. Duplicate requests returned the same task, build left applied
  state empty and stale apply was rejected. Later shared state-provider changes
  were covered by the final real guest gate; source capture/idempotency code was
  unchanged apart from narrowing output-name exclusion and returning timeout data.
- Reuse: Sylphy Foot renderer/selected preferences from Stage 01; inspected
  home-authority/adoption/publication and VM provisioning tests. Adapted ownership,
  journal, backup and guest-fixture principles without porting its private Python/
  Rust manager or its system-owned Home publication behavior.
- An initial guest dependency seed accidentally included derivation closures;
  that build was interrupted and corrected to actual output/runtime closures.
  No broad garbage collection or reference checkout modification was performed.
- Limits: no system-scope activation, product VM lifecycle, migration executor or
  managed rollback yet. Interrupted activation is reported for Stage 04 recovery;
  no automatic destructive retry is claimed. No development-host activation.
- Commit subject: `feat(manager): deploy frozen user foot configuration`.
- Next: Stage 03 extends the same scoped repositories, immutable plans/workers and
  profile authority with authorized root service, unprivileged builder, real system
  descriptor and disposable UEFI guest. It must preserve the selected user profile.
