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

## 14. Panel TUI implementation plan (pending)

Use `modules/panel/` for one Python project, with `folio` as the CLI entry and
`folio panel` launching Textual. Keep Nix implementation under src/, client code
under cli/ and behavioral tests under tests/. No scaffolding is needed before
implementation. TUI uses the shared client layer; manager keeps all change and
authorization ownership. Other modules keep domain execution.

The owner selected English-only authored UI and bordered sections, superseding
the earlier borderless preference. Use standard Textual borders/containers and
widgets. Avoid excessive nesting, preserve clear keyboard focus, and test compact
terminal sizes, resizing, keyboard input and asynchronous backend failure.

The owner's priority is routine connectivity and device control. The first
release has exactly four English pages, in this order:

| Page | Priority | Purpose |
| --- | --- | --- |
| Wi-Fi | First; default landing page | Scan, select, connect and manage saved wireless networks |
| Proxy | Second | Observe Mihomo and select/test existing nodes and runtime mode |
| Display & Audio | Third | Adjust supported backlight, output volume, mute and default output device |
| Device | Fourth | Read the actual current machine's identity, hardware and runtime information |

This supersedes Overview/Settings/Network & Devices/History. Do not implement
generic configuration editing, apply, change-history or rollback pages in this
first panel release; those remain CLI workflows. No app-management or VM pages.

### 14.1 Shared interaction and module boundaries

- Use visible tab navigation and bordered sections, with one clear primary action
  per selection. Keyboard operation must work without a mouse. Preserve focus
  across refreshes and avoid excessive nested borders.
- Every authored label, hint, error and status is English. SSIDs, node names,
  device names and other user/external data preserve Unicode without translation.
  Escape terminal controls and disable markup interpretation of external strings.
- Show observed state, loading, unavailable, authorization failure and backend
  failure distinctly. Refresh on active pages without blocking input; do not
  fabricate availability from enabled configuration or replace errors with zeros.
- Runtime controls act immediately after applicable authorization/confirmation;
  verify the observed result. No Nix build, standard-change comment or global
  Apply button. Runtime selections are outside configuration rollback.
- Saved Wi-Fi profiles are NetworkManager-managed operational data. Mihomo's
  stored node selection is application state. Neither creates a second Folio
  desired-configuration authority or enters immutable builds/history snapshots.
- Panel remains unprivileged. Typed clients call network/devices-owned APIs;
  extend those backends where capabilities are missing. No direct sysrepo edits,
  shell-interpolated requests, arbitrary privileged command execution or parsing
  human CLI output. A new public network/device CLI is not required.
- Do not collect sudo passwords in widgets. Wi-Fi password entry is a distinct
  feature: send network secrets only through an explicitly designed secure
  NetworkManager credential path, as described below.
- Bound background work, stale results and refresh frequency. On close, cancel
  UI polling/probes; do not imply a submitted native connection/control operation
  was canceled. On reopen, query actual backend state.

### 14.2 Wi-Fi page

Display adapter selection when multiple wireless adapters exist, Wi-Fi radio
state, current SSID/connectivity, signal strength and assigned IP information.
List nearby networks with SSID, signal, security and saved/connected markers.
Track stable adapter/AP/profile identities; duplicate SSIDs must not cause an
operation on an unrelated saved profile or access point after list refresh.

Actions:

1. Wi-Fi radio on/off, with observed software/hardware block explanations.
2. **Refresh**: bounded scan of the selected adapter; entering the page can request
   an initial scan. Do not repeatedly scan on every UI redraw.
3. **Connect**: reuse a compatible saved profile/credential when available.
4. For a new supported personal network, ask for a masked password with an
   explicit show/hide toggle; provide open-network handling without a password.
5. **Disconnect**: disconnect the selected active connection; explain connectivity
   loss and confirm when it can disrupt the current session.
6. **Forget Network**: confirm before deleting the specifically selected saved
   profile. Make any active-connection impact explicit.
7. **Hidden Network**: enter SSID and supported security/credential details.

Show Connecting, Connected, Failed and Disconnected from native results. Keep a
usable retry path for wrong credentials, disappearing APs and timeouts. Missing
wireless hardware displays **No Wi-Fi Adapter**, not an empty successful scan.
Do not promise Internet access solely because association or IP assignment worked.

First-release authentication scope: open networks and supported WPA personal
networks. Enterprise/802.1X, certificate enrollment and captive-portal login are
deferred; recognize them and explain unsupported authentication. Check supported
security modes against the pinned NetworkManager APIs before exposing choices.

Credential design is a prerequisite: use NetworkManager's native secret-agent/
credential mechanisms, with a narrow authenticated channel and explicit storage
policy. No passwords in argv, environment variables, normal RPC diagnostics,
temporary configuration files, Folio desired data, change records or Nix store.
Keep UI secret buffers short-lived and clear them when forms close. Do not claim
perfect memory erasure in Python. Test log/snapshot exclusion using disposable
credentials. No manual reading or copying of existing real network secrets.

Existing network backend covers observations and activation of existing UUIDs;
scan/radio/profile creation/forget/secret handling require real new capabilities.
Choose pinned libnm/D-Bus/native integration through network-owned resources;
do not implement connection management inside generic manager callbacks.

### 14.3 Proxy page

Display actual Mihomo availability, runtime Rule/Global/Direct mode, proxy groups,
selected group/node and available nodes. Support existing selectable groups while
clearly identifying the owned default PROXY group; do not assume every returned
group permits manual selection. Keep node identity separate from display markup.

Actions: **Refresh**, **Select Node**, runtime mode selection, **Test Latency** for
one node and **Test All** for the selected group's eligible nodes. Verify mode/node
changes through fresh observations; do not modify desired policy or provider files.

Delay tests use an explicit module-owned test target, timeouts and bounded
concurrency. Do not start bulk tests automatically on every page visit/refresh.
Associate results with node identity and test time. Show **Not Tested**,
**Testing**, measured milliseconds, **Timeout** and other errors separately.
Latency is reachability to that test target, not universal Internet health.

Use the existing private Unix controller through the network backend; do not
expose an unauthenticated TCP controller or weaken socket permissions. Extend
network-owned typed operations for node/group inventory and delay tests. Show
useful disabled states for stopped Mihomo, missing providers and stale nodes.
Subscription import/edit/refresh policy and rule editing are deferred.

### 14.4 Display & Audio page

Audio: display available output devices, current default, volume percent and mute.
Provide default-output selection, volume slider/keyboard adjustments and mute.
Clearly define volume/mute as applying to the currently selected default output.
Switching default output must not promise migration of existing streams unless
the backend explicitly implements and verifies that behavior.

Brightness: list supported backlight devices when needed, show actual percentage,
and support slider/keyboard adjustment. Missing backlight on a desktop/external
display shows a reason and disabled control. DDC/CI monitor brightness requires
separate capability/permission testing and is not silently included in this release.

Debounce/coalesce slider requests, bound changes and verify returned state; do not
spawn a backend process for every pointer event. Avoid increasing audio volume
past the supported 100-percent limit. Handle device disappearance and unavailable
PipeWire/backlight permissions without losing navigation.

Reuse device-owned volume/mute/brightness operations; add output enumeration and
default-output selection there. Do not persist live sliders as Folio desired data.

### 14.5 Device page

Read-only information: machine/vendor/model, CPU, memory capacity/current usage,
GPU models and active drivers, connected display outputs, network/audio adapters,
OS/kernel version, uptime and installed Folio target. Show battery state when
present; omit battery-only sections on machines without a battery.

GPU utilization/temperature is optional only when a supported native query is
available. Missing metrics are **Unavailable**, not inferred from configuration.
Keep discovered PCI/DRM IDs tied to actual devices; do not hardcode card numbers.
Use devices-owned observation APIs and public manager metadata where appropriate.
Refresh expensive metrics only while visible and with bounded native calls.
Do not expose hardware editing, disk writes or reboot controls here.

### 14.6 Ordered panel milestones

Panel work depends on its typed client/authorization contracts, not completion of
the entire manager history/rollback UI. It can be developed in bounded milestones
without expanding the agreed everyday CLI command list.

- [x] P0: audit native APIs and existing network/devices backends; define missing
  typed operations, credential channel and permissions before writing controls.
- [x] P1: create the shared Python panel package and English bordered four-page
  shell, lazy TUI import, unavailable/error states and keyboard/resize behavior.
- [ ] P2: implement Wi-Fi first: inventory/scan, saved/new/hidden connections,
  secrets, radio, disconnect and confirmed profile deletion.
- [ ] P3: implement Mihomo inventory, group/node selection, runtime modes and
  bounded latency tests, including unavailable and stale-node handling.
- [ ] P4: implement audio output selection/volume/mute and available backlights;
  add the read-only device page with capability-dependent metrics.
- [ ] P5: run backend integration and headless UI tests, then bounded real-device
  acceptance on named authorized machines; update README and record limitations.

### 14.7 Panel acceptance requirements

| Area | Required evidence |
| --- | --- |
| Wi-Fi | Real scan, saved and new personal-network connection, wrong-password failure, hidden SSID, radio, confirmed forget and adapter disappearance |
| Credentials | Disposable secret absent from logs, argv, exports, snapshots and store outputs; native credential storage policy verified |
| Proxy | Actual group/node inventory and selection, runtime mode changes, measured/timeout states, stopped backend and bounded bulk tests |
| Audio | Actual default-output change, volume/mute observations and disconnected-output handling |
| Brightness | Actual supported backlight change or explicit unavailable evidence; desktop slider never pretends to work |
| Device | Observations match actual adapters/drivers; missing sensors/battery are represented accurately |
| UI | English authored strings, Unicode external names, borders/focus, keyboard-only navigation, resize, busy/error states and stale-response handling |
| Permissions | Unprivileged UI, denied operations fail before effects, no controller permission weakening or secret exposure |
| Configuration separation | Runtime actions do not mutate Folio desired data or trigger apply/build/standard-change comments |

Use Textual headless tests for interaction, not as proof of real Wi-Fi, proxy,
audio or backlight effects. Real backend integration and authorized hardware
evidence are required for those claims. Do not disconnect the development host
or alter its real saved profiles merely to run automated tests. The implementation
status and evidence below distinguish the prototype from completed acceptance.

## 15. Historical pause handoff (2026-10-19)

Work was paused at the owner's request at base commit `0e8e27d`. Implementation
changes were uncommitted; no milestone was declared complete. No build, test
driver or QEMU guest remained running. The development host was not activated,
disconnected or subjected to audio, brightness or saved-profile mutations.

### Implemented working tree

- `modules/panel/`: shared Python/Textual package, `folio panel`, four English
  bordered pages, Wi-Fi as the default page, confirmation/password dialogs,
  keyboard controls, debounced sliders and bounded background operations.
  Existing CLI commands still delegate to the manager CLI. Smart apply,
  unified change history and rollback are not implemented by this prototype.
- `modules/network/`: native libnm Wi-Fi helper with JSON stdin credentials;
  Mihomo group, selection and delay operations through a new
  `folio-network-panel` YANG RPC and the private controller socket.
- `modules/devices/`: native audio/default-output and backlight controls,
  plus observed device information. Unsupported controls report unavailable.
- Manager composition installs the panel wrapper. Headless tests and an
  isolated VM integration fixture cover the new interfaces. Production network
  authorization has not been relaxed.

### Validation evidence

- Textual headless interaction tests: **5 passed**; see
  `/tmp/folio-panel-ui-tests.log` and `/tmp/folio-panel-gate8.log`.
- Frontend build passed; output and log are recorded in
  `/tmp/folio-panel-final-path` and `/tmp/folio-panel-final-build.log`.
- An earlier system build and configuration integration check passed; see
  `/tmp/folio-panel-system-build.log`. These must be refreshed against the final
  source after remaining fixes; they are not a completed release gate.
- Latest isolated VM run passed real WPA Wi-Fi scan, new connection with DHCP,
  disconnect, saved-profile reconnect, forget and radio toggling. Its regular-file
  check found no fixture password in Folio repository/runtime data. This is
  partial credential evidence, not full argv/log/export acceptance.
- `git diff --check` passed before this handoff. UI screenshots in
  `/tmp/folio-panel-*.svg` and `.png` use synthetic data, not physical acceptance.

### Current blocker and unverified behavior

The VM check fails at the first proxy RPC, before reaching proxy operations:

```text
/run/current-system/sw/bin/folio-repository: line 46:
/var/lib/folio/repository.lock: Permission denied
```

The minimal fixture initializes the repository as root without reproducing the
production operator-group provisioning. Inspect the repository wrapper and init
contract, then fix fixture ownership/modes for `folio-operators`; do not bypass
authorization or make repository state world-accessible. Evidence:
`/tmp/folio-panel-gate8.log`.

Proxy integration and real audio tests were **not reached**. Wrong-password and
hidden-network paths, complete credential exposure checks, physical backlight
behavior and final hardware acceptance remain pending. Existing installations
also need the new YANG model and subscriber upgrade before panel RPCs can work.

### Resume order and reproduction

1. Review the working diff and fix the VM repository permission fixture.
2. Run the isolated network/proxy/audio gate and fix observed backend failures:

   ```sh
   nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths -L \
     .#checks.x86_64-linux.panel-network .#checks.x86_64-linux.panel
   ```

3. Complete missing failure/security cases, then refresh affected package,
   system and configuration checks against the final source.
4. Update README and this acceptance record with actual results and limitations.
   Review explicit paths before making an implementation commit. Physical
   mutation tests require a separately authorized device/session.

Temporary logs and screenshots are local evidence and are not tracked artifacts.

## 16. Resumed prototype implementation (2026-10-19)

This section supersedes section 15's blocker and progress. The owner requested
implementation to resume. The four-page prototype and native module interfaces
are implemented; physical acceptance and the separate unified CLI milestones
remain outstanding. P0/P1 are complete. P2–P4 have implemented controls and guest
evidence; their full acceptance matrix and P5 hardware gate are not complete.

### Fixes and implementation boundaries

- Reproduced production root/operator-group provisioning in the isolated VM.
  This resolves the repository-lock permission failure without relaxing policy.
- Closed Mihomo HTTP connections explicitly, matched the integration RPC timeout
  to the frontend, and exercised the installed asynchronous client against real
  sysrepo and the root subscriber.
- Added wrong-password failure and hidden-network connection checks against a
  real WPA access point in mac80211_hwsim. Expired activation requests attempt
  bounded native cancellation; saved profiles remain available for explicit retry.
- Cleared stale Wi-Fi/proxy/audio controls when services disappear, rendered
  unsupported sliders as Unavailable, and rejected running the TUI as root.
- Verified native default-output changes, volume and mute with actual PipeWire
  null sinks; removed outputs become invalid selections. PipeWire may create a
  fallback sink, so tests do not mistake it for a surviving removed output.
- Added the frontend to the development shell. Existing manager CLI/backend
  behavior is retained through delegation. README documents launch, permissions,
  runtime/configuration separation and the paired model-upgrade requirement.

### Evidence and reproduction

The native controls gate passed in `/tmp/folio-panel-gate13.log`, including Wi-Fi,
wrong-password/hidden-network behavior, real Mihomo controls and unavailable
latency/backend states, denied operator access, and native audio/device checks.
The final run in `/tmp/folio-panel-gate14.log` also **passed**, including six
headless UI tests, credential absence from backend replies, Folio exports,
relevant service journals and frontend files, and adapter-disappearance UI
coverage. Native connection permissions and root-owned mode-0600 credential
files were checked. All test guests shut down after completion.

Final check outputs:
`/nix/store/6a1cq860rchqsjzhvbpdav5z7p7vwic4-vm-test-run-folio-panel-native-controls`
and `/nix/store/14qnghc278sk9hivk9gcjlm2lcr3hsxx-folio-panel-interaction-tests`.

```sh
nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths -L \
  .#checks.x86_64-linux.panel-network .#checks.x86_64-linux.panel
nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths -L \
  .#nixosConfigurations.folio.config.system.build.toplevel \
  .#checks.x86_64-linux.configuration .#checks.x86_64-linux.catalogue
git diff --check
```

The second build command passed against the current implementation:
`/tmp/folio-panel-final-system2.log`. Its system output is
`/nix/store/jfhdshb2dbhn7f12fx4q80g1yzb8y6wi-nixos-system-sylphy-portable-26.11.20261011.7fd4004`.
Python source passes Ruff checks and formatting. Headless tests verify interaction
only; native guest checks use disposable credentials, a real NetworkManager/WPA
stack, Mihomo and PipeWire, not physical peripherals.

### Remaining acceptance and next work

1. Verify physical Wi-Fi/native authorization and audio in an appropriate desktop
   session, plus a supported real backlight where available. No development-host
   activation or live hardware mutation has been performed in this implementation.
2. Complete positive external-node latency and bounded bulk-stop acceptance with
   an authorized provider; current native evidence covers actual node selection
   and failed/unavailable latency, not performance of a real provider.
3. Extend hotplug and credential checks as needed: the UI covers adapter/backend
   disappearance; physical hotplug, live process-argument inspection and the full
   snapshot/security matrix are not established by the current guest evidence.
4. Existing installations need paired schema/subscriber deployment. Do not bypass
   repository model-identity checks or initialize over a live older repository.
5. Resume M0–M7 separately for intelligent apply, standard changes/comments,
   unified configuration/history and rollback. They are not shipped by this panel.

## 17. Agents capability and terminal-owned Git (2026-10-19)

Owner request: replace the standalone `codex` module with `agents`, choose the
official DeepSeek Harness, and consolidate Git/GitHub CLI into `terminal`.

### Delivered structure and configuration

- `modules/agents/` owns `folio-agents`, Codex packaging/theme/completion and the
  official dsh package. `folio-agents:agents.codex` has independent `enabled`,
  `theme` and `shell-completion` switches; `.dsh.enabled` selects dsh.
- dsh is pinned to `0.2.1-rc.2`; `src/dsh/package-lock.json` pins dependencies.
  Nix builds node-pty and Sharp against Nix libraries, fixes native library paths
  and provides Node/pnpm for plugin operations. An explicit Node internal-module
  path replaces upstream machine-code probing, which fails with Nix's Node build.
  No install-time network scripts, mutable profile templates, tokens or sessions
  are embedded in managed user configuration.
- `folio-terminal:terminal.git` owns Git enablement, identity, branch/pull
  preferences and optional GitHub CLI. The standalone `modules/git/` and
  `modules/codex/` directories and catalogue selections are removed.
- Fresh defaults select `agents` with Codex and dsh enabled. Existing migrated
  selections retain their previous enabled/disabled state; dsh starts disabled
  until selected. Disabling `terminal.git` leaves the terminal selection intact.

### Upgrade and preservation contract

`folio-codex` becomes `folio-agents`; `folio-git` is absorbed by the new
`folio-terminal` revision `2026-10-22`. Original models remain byte-identical in
the owning modules' schema-history exports. Terminal revision `2026-10-21` is
archived so its existing migration hash does not change retroactively.

Repository maintenance now accepts an explicit hash-bound `toModule` replacement
declaration. Unknown removal, missing replacement models, stale hashes, ambiguous
edges and invalid revision progression fail before installation. Each migrated
document is validated against the target models. Conflicting old/new settings
and enabled legacy Git with a disabled terminal fail instead of overwriting data.
Retained rollback restores the complete previous model/data identity.

Codex/dsh authentication and sessions, GitHub credentials, repository-local Git
settings, notes and other private state remain application owned. No host
activation, live repository migration or external model request was performed.

### Validation and reproduction

The real isolated model replacement/retained restore check passed, including a
wrong-source-hash rejection with unchanged live data:
`/tmp/folio-agents-migration-final.log`, output
`/nix/store/i4y77mi0mx2v9qkh89f478gifm7q79qv-vm-test-run-folio-agents-terminal-migration`.
The final package/profile gate **passed** in `/tmp/folio-agents-final-gate.log`:
agents startup/native/plugin-manager checks, real profile delivery/removal of
Codex/dsh and terminal-owned Git, private-state preservation, developer tools,
foundation, configuration integration, catalogue and the physical-target system
build. All guests shut down after completion. Notable outputs:

- Agents runtime: `/nix/store/a1wcq25m4ycmhi0synf6bfrqc1jb2k3v-folio-agents-runtime`.
- Profile lifecycle: `/nix/store/3b6afmvmci54rrfkwl70v095bbdw7rcy-vm-test-run-folio-tools-deployment`.
- System build: `/nix/store/xq5psb7ppqnfswa68fykjh2ic6wj3h22-nixos-system-sylphy-portable-26.11.20261011.7fd4004`.

```sh
nix build --no-link --no-update-lock-file --keep-going --max-jobs 2 --print-out-paths -L \
  .#checks.x86_64-linux.agents .#checks.x86_64-linux.agents-migration \
  .#checks.x86_64-linux.tools .#checks.x86_64-linux.tools-deployment \
  .#checks.x86_64-linux.foundation .#checks.x86_64-linux.configuration \
  .#checks.x86_64-linux.catalogue \
  .#nixosConfigurations.folio.config.system.build.toplevel
git diff --check
```

The agents runtime check exercises headless profile startup, native PTY/FFI/image
library loading, plugin-manager availability and migration selection/conflict
cases without credentials. DeepSeek inference and arbitrary third-party plugin
compatibility require separate runtime evidence and are not claimed by this gate.
