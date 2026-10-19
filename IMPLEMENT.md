# CLI Implementation Proposal

Status: discussion draft, revised 2026-10-19. This revision supersedes the
previous explicit user/system plan/build/apply command proposal. Unified command
forms below are not implemented yet. The existing editor/export JSON readability
fix is implemented separately. README remains actual product documentation.

See [TASK.md](TASK.md) for the detailed technical plan, ordered milestones,
authorization/recovery design and acceptance matrix.

## Accepted direction

- One everyday `apply` entry detects user/system/source changes and performs the
  necessary scoped work internally. Do not ask users to classify change scope.
- Every accepted apply workflow is a standard change with a unique change ID,
  comment and recorded before/after system and user state.
- Rollback targets a standard change, restoring its successful final state.
- Keep logs, but provide their locations rather than a log-viewing CLI.
- Keep plans, task IDs, scoped repositories and privileged workers internally.
  Unified interaction does not make separate backend effects atomic.
- Implement CLI and TUI in one Python project owned by `modules/panel/`.
  The entry is `folio`; `folio panel` opens the Textual TUI. Share a typed client
  layer, not human-output parsing. Keep C/libsysrepo/libyang and existing Shell
  backends; migrate frontend adapters without rewriting proven runtime logic.
- All authored CLI/TUI labels, help, prompts, errors and progress are English.
  User-entered comments and application data retain Unicode, including Chinese.
- Use bordered TUI sections, visible keyboard focus and compact layout. This
  supersedes the earlier borderless preference. TUI implementation remains planned.
- Editor drafts and exported configuration use two-space indented JSON with a
  trailing newline. Canonical compact JSON remains internal to digests/transport;
  whitespace-only editing must not change configuration meaning.

## Everyday CLI: complete list

`[]` denotes optional arguments. `CHANGE_ID` uniquely identifies a standard
change. Comments may be Chinese or English and need not be unique.

| Complete command | Function |
| --- | --- |
| `folio --help` | Show the short command list and common edit/apply/history/rollback workflows |
| `folio help COMMAND` | Explain a command, arguments, authorization requirements and examples |
| `folio --version` | Show CLI version/build identity without contacting subscribers |
| `folio panel` | Open the planned bordered English-language Textual settings/status interface |
| `folio status` | Summarize configuration health, pending changes, current standard change and partial recovery state |
| `folio status CHANGE_ID` | Show a change's comment, before/after references, step results, actual effects, rollback availability and log locations |
| `folio config show` | Read the current desired configuration, clearly separating system/user ownership in the display |
| `folio config edit` | Open an editor for configuration changes, validate and report exactly what was saved; do not activate |
| `folio config import FILE` | Validate/import a configuration backup, with explicit system/user ownership; do not activate |
| `folio config export FILE` | Export a restorable configuration backup with explicit system/user sections, excluding secrets, runtime data and application profiles |
| `folio modules [NAME]` | List module descriptions, desired/applied state and prerequisites; with NAME, show that module's settings/help |
| `folio apply [-m COMMENT]` | Detect applicable changes, freeze inputs, build, authorize privileged effects, apply and verify; record one standard change |
| `folio history` | List standard changes with ID, time, comment, outcome and current/rollback availability indicators |
| `folio rollback CHANGE_ID [-m COMMENT]` | Restore system/user configuration to the selected change's successful final state, authorizing privileged work as needed; record a new change |

`folio --json COMMAND` remains the machine interface for supported noninteractive
commands, including future clients. Preserve one final result envelope and keep
progress on stderr. JSON mutations must provide their comment and cannot prompt
on redirected input. Missing authorization fails explicitly without partial work
being disguised as success. No unrestricted privileged frontend is introduced.

## Apply and authorization contract

`apply` compares both scoped desired stores and relevant source with recorded
applied state. Source edits matter even if database values did not change. Nix
reuses cached artifacts; a system configuration build does not imply recompiling
all software. No pending effects means a no-op, without a new successful change
or unnecessary authorization prompt.

A real change requires a nonempty comment. With `-m`, use the supplied comment;
otherwise prompt on a terminal. Noninteractive use without a comment is invalid.
Allow Unicode comments; escape control characters in displays and never use
comments as filenames, shell code or unique identifiers. Preserve the comment on
failed/partial changes so an operator can understand attempted work.

Resolve source explicitly and show its identity before effects. The default
source-selection rule still needs agreement; do not guess a different checkout,
pull Git or refresh a lock automatically. A future explicit source override can
be considered separately, rather than adding it to this minimal command list.

Build/evaluate as an unprivileged account. System effects require a controlled
privileged entry point and backend-enforced authorization; user-only changes do
not prompt for sudo. Current operator-group RPC access does not require a password,
so this needs a real authorization redesign, not a cosmetic frontend `sudo -v`.
Sudo may reuse valid cached authorization. Do not run arbitrary source evaluation
as root or expose private journals to make the UI convenient.

When both scopes change, apply system state before preparing the final user
snapshot against the resulting system descriptor. Record every step. System
success followed by user failure is a partial change, not atomic success or
an implicit full rollback. Report the actual state and recovery information.
No implicit Flatpak update, hardware-target transition, reboot or destructive
repair belongs in `apply`.

## Standard change and rollback contract

Retain ID, timestamps, comment, operation kind, before/after desired snapshots,
source/model identities, system/user closure references, step/task references,
authorization outcome, logs and final outcome. Retain both scopes' state even
when only one changed; record an unchanged scope without rebuilding it needlessly.
Pin the closures/sources required for advertised rollback availability.

`rollback CHANGE_ID` means restore the selected successful final state, not undo
that row's own edits. Reject failed/partial rows as final-state rollback targets
unless a separately validated recovery operation establishes a usable endpoint.
Rollback creates a new history entry; do not erase later records. Its default
comment is generated from the target ID/comment, with `-m` allowing replacement.

Restore desired data as well as applicable closures; do not merely switch a boot
entry. Plan recovery before privileged effects and record partial failures.
Missing retained inputs mean rollback unavailable, not fabricated restoration.
Personal documents, application databases, credentials and arbitrary runtime
controls are outside configuration rollback. Driver/kernel restoration may need
a later reboot; report known requirements without rebooting automatically.

## Configuration editing details still open

Hide scope selection from the everyday command line while retaining explicit
system/user ownership in editor/export data. The unified view is not a new
configuration authority. Define versioned import/export mapping to the existing
scoped YANG repositories, concurrency checks and authorization before coding.
Saving multiple stores is not inherently atomic; never silently save half a
configuration and report full success. Keep a failed edit recoverable.

Decide backup replacement/merge semantics, source selection, retention policy,
change-ID format and interrupted-workflow recovery before implementation. Do not
add separate configuration-only history until its relationship to standard
apply changes is agreed.

## Excluded from the everyday interface

No standalone plan/build commands or user-managed plan/task IDs; no --system or
--environment selection for daily use. Existing internal/scoped mechanisms can
remain during migration until the unified workflow is actually implemented.

No logs/tasks/overview/diff/doctor/update/reset/cleanup commands, config get/set,
module enable/disable shortcuts, status watch, color flag, verbose flag or public
request-ID options. Advanced cleanup and migration helpers remain maintenance
operations, with protected recovery generations retained.

Network, device, application and VM CLI design is deferred. System reboot/poweroff
are not part of this minimal daily interface; use the operating system facilities.
TUI design is now in discussion under the panel module; implementation is not
started. GUI work remains deferred. This proposal does not remove existing
implemented commands or disable their backend capabilities.

## Panel technology and interaction direction

Use Python + Textual for layout, widgets, borders, keyboard/mouse input and
background refresh. CLI imports must not eagerly load Textual. Package the single
Python project through Nix, with no independent dependency lock or manual pip step.
Panel owns navigation/rendering; capability modules retain their actual operations.
Routine network/device controls in TUI do not require new public CLI commands.

Candidate English pages: Overview, Settings, Network & Devices, History.
Their exact contents are still proposals. Clearly distinguish immediate runtime
controls from saved configuration awaiting unified apply. Reuse the same change,
comment, authorization and rollback APIs. Never collect sudo passwords in a
custom widget or run the entire TUI as root.

Borders and layouts are built-in framework features; use standard containers and
widgets rather than hand-drawing a terminal renderer. Verify focus, resize/small
terminals, asynchronous failures and detached-task behavior before delivery.
References: [borders](https://textual.textualize.io/styles/border/),
[layout](https://textual.textualize.io/guide/layout/),
[testing](https://textual.textualize.io/guide/testing/).

## Delivery order and verification

1. Agree on the minimal command list and remaining data/source/auth decisions.
2. Implement standard change records and authorized history/status reads.
3. Implement unified configuration views/import/export with scoped validation.
4. Implement intelligent apply, partial recovery and backend-enforced authorization.
5. Implement unified rollback and concise human output; preserve JSON contracts.

Use focused real-sysrepo and disposable guest tests. Cover user-only/system-only/
combined/no-op/source-only changes, comments, denied authorization, stale inputs,
partial application, interrupted recovery and rollback. Keep logs outside source.
Verify retained rollback roots and no unintended personal-data restoration.
Do not claim this draft's command forms already work in the current CLI.
