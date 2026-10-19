# Unified CLI Implementation Tasks

Status: planned, 2026-10-19. No unified CLI implementation is claimed here.
IMPLEMENT.md defines the agreed public command direction. This document defines
the technical approach, dependencies, execution order and acceptance evidence.
README.md remains documentation for behavior actually delivered.

## 1. Baseline and authorized scope

Implementation baseline: `ff518d5`. The unified physical target is `folio`;
`portable` remains the disposable guest target. Existing scoped configuration,
immutable plan/build/apply, task journals, recovery and rollback already work.
Config editor drafts and exports already use two-space indented JSON.

This work changes the interface and introduces a durable cross-scope coordinator.
Reuse working scoped workers, model normalization, atomic writes and GC roots.
Do not rewrite module backends, directly activate from the CLI, or treat a database
commit as activation. Implement the shared Python CLI/TUI project in
modules/panel/; retain sysrepocfg transport as appropriate, C/libsysrepo/libyang
subscriptions and existing fixed Shell runtime helpers. Root composition remains
in modules/manager/src/outputs.nix. Frontend migration does not authorize a
backend rewrite.

The current machine may still run a retired installed target. Normal apply must
not silently migrate hardware targets. Establish a supported bootstrap/version
transition separately before claiming the new CLI works on that installation.
All development activation/power tests use disposable guests. No host activation,
EFI changes, physical disk writes, credential reads, Git push or system restart
is authorized by this implementation plan.

## 2. Public contract

Deliver only these everyday commands:

```text
folio --help
folio help COMMAND
folio --version
folio panel
folio status [CHANGE_ID]
folio config show
folio config edit
folio config import FILE
folio config export FILE
folio modules [NAME]
folio apply [-m COMMENT]
folio history
folio rollback CHANGE_ID [-m COMMENT]
folio --json COMMAND
```

No public plan/build/task-ID workflow, scope-selection flags, logs command,
overview/tasks/diff/doctor/update/reset/cleanup, setting shortcuts or module
enable/disable shortcuts. No new network/device/app/VM CLI design or GUI.
Panel TUI design is tracked separately below; it is not implemented yet.
Retain necessary low-level maintenance privately; removing everyday commands
must not destroy recovery capabilities or historical immutable workers.

### Proposed detailed decisions

- A real apply requires a nonempty Unicode comment. `-m` supplies it; otherwise
  prompt on a terminal. Whitespace-only comments fail. Proposed limit: 1024 UTF-8
  bytes. Escape control characters when displaying; never interpret comment text.
- Generate `c-` plus a random UUID as the authoritative change ID. Display and
  accept the full ID initially; defer prefix matching and renumbering.
- Rollback's default comment identifies the target ID/comment; `-m` overrides it.
- JSON mutations require a supplied comment or rollback's generated comment;
  they never read a comment from stdin. Privileged noninteractive work requires
  pre-established sudo authorization and must fail rather than hang for input.
- Preserve exit codes 0/1/2/3/4 and the final result envelope. Put the change ID
  in `data.changeId`; retain internal `taskId` compatibility without requiring
  ordinary users to manage it. Progress is stderr, never mixed into JSON stdout.
- Source selection: use the current directory only when it is a recognized Folio
  root with Flake/lock/modules; otherwise use the installed immutable source.
  A recognized but invalid checkout fails rather than silently falling back.
  Show source and installed target before effects. No parent-directory search,
  Git pull, lock refresh, arbitrary target selection or implicit network update.

These defaults make implementation actionable; amend them explicitly if later
discussion changes the contract. Do not add new public options to avoid resolving
internal design questions.

## 3. Ownership and file layout

| Area | Owner/location | Responsibility |
| --- | --- | --- |
| Command routing/help/rendering | panel/cli/ | Shared Python project, CLI, editor, progress and Textual TUI |
| Client protocol layer | panel/cli/ | Shared typed requests/results, errors and transport; no direct datastore writes |
| Frontend packaging | panel/src/ | Nix packaging and lazy Textual loading for the CLI |
| Change protocol | manager/model/ | Typed submissions, status/history, outcomes and versioning |
| Coordinator | manager/runtime/ | Persistent orchestration, checkpoints, recovery and child references |
| Privileged entry | manager/runtime/ | Fixed sudo submission and operation-bound root authorization |
| Packaging/services | manager/src/ | Explicit dependencies, system/user workers and permitted entry points |
| Behavioral tests | manager/tests/ | Scoped integration, authorization, faults and unified lifecycle |

Paths are relative to modules/. Exact new filenames should follow existing local
patterns. Do not create a second Python project, nested Flake, host/home tree or
parallel generic module action router. CLI/TUI share one panel project and client
layer; capability backends remain with their owners. Update root README only after behavior
exists. IMPLEMENT.md and TASK.md are the owner's requested planning exceptions.

## 4. Unified configuration document

Propose an explicit versioned envelope:

```json
{
  "format": 1,
  "system": { "folio-environment:environment": {} },
  "user": { "folio-environment:environment": {} }
}
```

The empty objects above show structure only; they are not valid complete input.
Each section carries a complete scoped RFC 7951 document. Do not combine YANG
namespaces or collapse system-owned identity into user preferences.

`show`, `edit`, `import` and `export` use this view. Export excludes optimistic
edit tokens so backups remain portable. Editing captures both starting digests
out of band, opens a mode-0600 two-space-indented document and validates both
sections before writes. Import replaces the supplied complete pair, not a silent
merge. Reject unknown envelope versions, omitted sections and mismatched scope,
UID/home/environment/model identities. No credential/application-state export.

Use the existing repositories as configuration authority. Do not introduce a
second database or local draft that quietly becomes another desired-state store.
Saving configurations still has no application effects.

Before a paired save, acquire locks in one documented order, recheck both digests,
and durably journal the intended pair and preimages. Write via existing scoped
commit/permission mechanisms, record each outcome and acknowledge only after
both durable saves. On failure attempt a guarded compensation; if compensation
cannot be verified, report partial state and retain recovery data. Never overwrite
an intervening writer. A coordinator lock alone does not exclude old direct
writers: enforce the protocol at backend mutation boundaries.

Existing operator-group access may permit saving system intent; it must not
authorize activation under the new password policy. An account unable to read or
write a scope gets an explicit access error, not an invented empty configuration.
Define reader/editor access in the migration tests before exposing unified views.

## 5. Standard change records

A standard change is a durable workflow, not an SQL transaction across profiles.
Propose per-owner coordinator records under the existing private user state root,
with corresponding root-private system records/receipts. Root must never trust
editable user history as proof of authorization, artifact identity or completion.
Public projections expose only authorized summary fields.

Retain the following versioned fields:

- ID, owner UID/account, environment/target, creation/update timestamps, comment,
  operation kind (apply/rollback), optional rollback target and schema version.
- Before/desired/verified-after references for both scopes: normalized data and
  digests, descriptor/model identities, immutable source and selected closures.
- Changed/unchanged/unknown classification for each scope and its reasons.
- Parent phase, ordered scoped step IDs, internal plans/tasks, durable request
  identities, authorization receipts and effect checkpoints.
- Result, errors, per-scope verified state, recovery information, log locations,
  runtime-versus-selected boot identity and supported reboot requirements.
- Retention roots, baseline provenance and rollback availability/reason.

Keep references to private snapshots rather than secrets in public summaries.
Use the existing atomic-write/fsync primitives. Comments are data, not shell
arguments assembled into executable text. No successful record for a no-op.
Failed/denied/partial attempts after acceptance retain their comment and outcome.

For first use, inspect installed metadata and actual profiles. Establish an
observed baseline only when identities can be verified; never claim an unknown
legacy configuration is restorable. Retain unchanged scope references when valid.
Absence of a baseline is not proof of no pending work.

## 6. Intelligent apply

1. Discover the calling owner, installed target, both desired snapshots, public
   descriptor and actual selected profiles. Recover or report unresolved earlier
   work before accepting conflicting effects.
2. Capture recognized source once using existing exclusions/symlink checks.
   Freeze each scope with its proper configuration/model/descriptor identities.
   Record starting digests/profiles for stale-state checks.
3. Classify work using normalized data, source identities, Nix evaluation and
   actual applied state. Account for drift and interrupted effects, not only
   database digests. User-only changes must not require system authorization.
4. If no pending changes/effects exist, report a no-op without requesting a
   comment/password or allocating a successful history row.
5. Obtain/validate comment, allocate a durable change and pin preimages/source.
   Seal candidate system work at the root boundary when needed. Show a short
   reason for each scope's classification; never guess impact from filenames.
6. Build through unprivileged workers with bounded waits, retained logs and
   durable child task identities. Cache reuse is normal and does not imply a
   missing operation. Record validation/build failures before activation.
7. Recheck digests, selected profiles, descriptor and target before effects.
   Reject stale candidates instead of silently incorporating later edits.
8. Apply system work through its authorized fixed worker, verify and record its
   selected closure/descriptor. Then prepare final user work against that actual
   descriptor, build/apply as necessary and verify the user profile/files.
9. Verify resulting desired persistence and actual scoped health, publish the
   final endpoint and current-change pointer, retaining all rollback roots.
   Report success/partial/failure with the change ID and log paths.

Existing closures embed complete source snapshots. A source edit can change a
system derivation even when it only appears related to a user module. Initially
use conservative Nix-backed classification and explain it; do not promise perfect
minimal impact detection. Identical effective output still requires reconciling
changed model/source/desired provenance where applicable. Defer optimizations
that omit source dependencies until they are proven not to miss system effects.

The pre-system user candidate may be used for validation, but never activated
against a descriptor different from the final frozen one. Define which validation
failures can be found before system activation; later user build failure remains
a real partial outcome. No claim of cross-scope atomicity.

## 7. Sudo and backend authorization

Introduce one narrow root-owned packaged submission entry, not a shell launched
with arbitrary arguments. The ordinary CLI uses sudo only for actual system work;
sudo handles password entry/cache and no password is read by Folio. Root derives
the caller from trusted sudo/session credentials, never supplied JSON owner data.

The entry validates and seals the exact candidate/action/owner/change identity
into root-private state and starts a fixed system worker. Evaluate/build source
as folio-builder, never as root. Restrict accepted paths/artifacts and reuse
existing worker/profile validation. No arbitrary executable, environment or unit
name may be selected by a request.

Bind approval to the exact operation and immutable inputs. A frontend `sudo -v`
is insufficient. The trusted worker consumes only its authorized operation;
reuse of a caller/change token with different inputs fails. Authorize before
root-only candidate mutation and recheck at activation. Root-level record sealing
can happen before builds; avoid an arbitrary root execution path for preparation.

Audit every old system submit/apply/rollback path, direct RPC and queued worker.
An operator-group member must not bypass password policy through a legacy route.
Recovery may finish already accepted work after reboot but cannot turn an
unapproved candidate into approved work. Document native OS administration as
outside Folio's authorization policy.

Test denial, cache reuse, missing terminal, forged caller, token replay, altered
source/artifact and old-interface bypass. No passwordless sudo policy should be
added merely to make integration tests pass; use isolated test authentication.

## 8. Durable orchestration and recovery

Suggested parent phases:

```text
accepted -> validating -> authorizing -> building-system -> applying-system
         -> preparing-user -> building-user -> applying-user -> verifying
         -> succeeded
```

Skip irrelevant steps explicitly. Terminal outcomes include failed, denied,
interrupted and partial; record outcome separately from the last effect phase.
Individual builds/authorization can be reordered only with durable preconditions.

Persist intent before each submission/effect and completion after verification.
Parent restart discovers an existing child via its persisted idempotency key;
never duplicate activation because a submit reply was lost. Use deterministic
lock ordering and bounded acquisition. A detached user/system service owns the
workflow; CLI exit or Ctrl-C does not own its lifetime.

On restart, reconcile scoped receipts, actual profiles, configuration digests and
checkpoints. Complete only verifiably finished publications, resume only approved
safe work, otherwise retain a recoverable partial/interrupted state. Do not replay
arbitrary operations or silently restore older personal files. Failed system work
prevents dependent user activation. Failed later user work leaves system success
visible. Retain a global-success endpoint separately from per-scope actual state.

## 9. Unified rollback

`rollback CHANGE_ID` restores the successful final state of that row, not the
state before that row. Allocate a new standard change with generated/custom
comment; preserve later history and make the rollback itself reversible.

Validate owner/target/model compatibility, desired snapshots, retained closures,
descriptor coherence and current drift before effects. Reject failed/partial
rows as ordinary rollback endpoints. Missing roots/metadata mean unavailable,
not an automatic fetch/rebuild of a different result.

Compute which scopes actually differ. Request system authorization only for
system effects. Reuse scoped maintenance to restore desired data and closures,
ordering system before dependent user state, with the same partial-result and
recovery checkpoints as apply. Preserve actual current state before rollback.
Reject uncommitted desired changes that would be overwritten unless a separately
agreed preservation/recovery flow makes them safe; never silently discard them.

Do not restore documents, browser databases, passwords/keyrings, application
runtime state or physical disk content. Selected boot configuration can differ
from the currently running kernel. Explain a known reboot requirement without
performing a reboot or claiming the running kernel has changed.

## 10. User output and logs

All authored CLI/TUI content is English: labels, help, prompts, errors, shortcuts
and progress. Preserve Unicode user comments/data without forced translation.

Default output should show scope decisions, comment, bounded phase progress,
actual outcome, full change ID and useful follow-up commands. Do not show raw
JSON as a successful human summary. Non-TTY output stays readable without live
spinners. No new watch/color/verbose options.

Keep full build/activation diagnostics in owned log files/journals; display paths
and required access. Do not publish sensitive root logs to make them clickable.
`status CHANGE_ID` explains per-scope effects and unavailable rollback conditions;
`history` shows time, comment, result and current endpoint. No log-viewing command.
History truncation/retention must be explicit, never silently delete roots.

## 11. Ordered implementation milestones

All items start pending. Commit coherent passing milestones with explicit paths.

- [ ] M0: freeze document format, source rules, change schema and authorization
  design; audit legacy entry points and record the first-deployment procedure.
- [ ] M1: add versioned manager change model/records, locks, receipts, GC roots,
  baseline establishment and authorized status/history projections.
- [ ] M2: implement unified show/edit/import/export with readable JSON, paired
  validation, concurrency control, durable save recovery and accurate errors.
- [ ] M3: implement fixed privileged submission, operation-bound approval and
  legacy-route restrictions; prove ordinary operators cannot bypass it.
- [ ] M4: implement intelligent apply, comments, no-op detection, source-only
  handling and durable parent/child orchestration using existing scoped workers.
- [ ] M5: implement standard-change rollback and partial/restart recovery.
- [ ] M6: replace public help/routing with the minimal command set, add module
  list/details and version output in the panel Python project, update README and
  migrate old clients safely. Verify shared client contracts and no Textual load
  for ordinary CLI invocations.
- [ ] M7: run one integrated disposable lifecycle, record actual evidence and
  limitations, commit the delivered milestone and document safe installation.

M2 and M4 depend on M1; M4 system effects depend on M3; M5 depends on M4; M6
must not remove the only working recovery path before M5 passes. Backend model
changes require exact prior revisions/hashes and explicit tested migrations;
do not silently replace installed schemas. Old immutable closures retain their
own workers. Test startup/bootstrap compatibility before defaulting to new CLI.

## 12. Required acceptance matrix

| Case | Required observation |
| --- | --- |
| User-only edit | No sudo; user changes applied; system identity unchanged |
| System-only edit | Exact authorized system step; no needless user activation |
| Both scopes | One parent record, ordered verified steps and final coherent descriptor |
| No-op/format-only edit | No successful extra history row, no authorization, stable configuration meaning |
| Source-only edit | Actual changed derivations/provenance detected without database edits |
| Stale candidate | Concurrent edits/profile changes rejected without overwriting later work |
| Comments | Unicode, repeated comments and hostile text remain safe data; empty input rejected |
| Paired save failure | No false success; guarded compensation or explicit recoverable partial state |
| Authorization failure | No unapproved effects through new or legacy paths |
| Build failure | Logs retained; no activation; meaningful failed change |
| Partial apply | System success/user failure accurately recorded and recoverable |
| Client/subscriber/worker restart | Accepted work survives; no duplicate child/effect submission |
| Rollback and rollback-again | Desired data and both applicable closures restored; history retained |
| Missing retained content | Explicit unavailable result, no invented rollback |
| Personal data | Sentinels in documents/app data/password state preserved |
| JSON/pipes | One final envelope, stable exit codes, progress separate, no hidden prompts |
| First deployment/upgrade | Known baseline, explicit model migration and usable recovery path |

Use existing configuration/recovery/system guest fixtures and module-owned tests.
No mocks for activation or permission claims. Batch related edits, use affected
checks, then one bounded final lifecycle. Do not run the entire desktop/hardware
matrix after presentation edits. Never claim a proposed output name passed.

## 13. Evidence and remaining decisions

During implementation append tested revision, exact commands, output/log paths,
results, fault recovery evidence, source reuse and limitations here. Keep runtime
logs/images outside Git. Update checklist status only with actual evidence.

Remaining decisions before coding: exact sudo entry API/policy; identity/location
of the first trusted cross-scope baseline; paired-save lock protocol and old-writer
compatibility; source-default acceptance; retention limits/pruning maintenance;
scope-read permissions and history visibility; first rollout from old targets.
Resolve these with code inspection and disposable prototypes. Seek clarification
only for material product/security choices that existing authorization does not
settle; do independent work meanwhile. No live-system rollout is part of this task.

## 14. Panel TUI design direction (not implementation)

Use `modules/panel/` for one Python project, with `folio` as the CLI entry and
`folio panel` launching Textual. Keep Nix implementation under src/, client code
under cli/ and behavioral tests under tests/. No scaffolding is needed before
implementation. TUI uses the shared client layer; manager keeps all change and
authorization ownership. Other modules keep domain execution.

The owner selected English-only authored UI and bordered sections, superseding
the earlier borderless preference. Use standard Textual borders/containers and
widgets. Avoid excessive nesting, preserve clear keyboard focus, and test compact
terminal sizes, resizing, keyboard input and asynchronous backend failure.

Candidate pages are Overview, Settings, Network & Devices, History. Contents and
save/apply behavior need detailed agreement before implementation. Runtime knobs
must report actual effects; persistent settings enter the unified configuration
and apply workflow. No direct sysrepo mutation, independent desired-state store,
custom password capture or privileged UI process. CLI/TUI must share typed APIs
without parsing each other's human output. Closing panel does not cancel accepted
work. A separate bounded TUI milestone follows the core API work; no prototype or
visual acceptance pass is claimed by these documents.
