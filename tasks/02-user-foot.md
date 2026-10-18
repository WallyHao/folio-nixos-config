# Stage 02: User configuration to Foot deployment

Dependencies: 01.
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
