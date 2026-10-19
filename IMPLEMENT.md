# CLI and TUI Implementation Proposal

Status: initial discussion draft, 2026-10-19. Proposed commands below are not
implemented unless explicitly marked existing. Agree on the command contract
before implementing new behavior. This file is the owner-requested implementation
plan; README.md remains the product usage documentation.

## Goals and boundaries

- Make manager operations understandable without knowing YANG, sysrepo, Nix
  output paths or internal journals.
- Preserve separate desired configuration, frozen plans, builds, activation and
  observed health. A successful save or build must not imply successful activation.
- Keep module-owned commands/subscribers. Manager supplies common CLI facilities
  and deployment orchestration, not a generic router for module effects.
- Provide one stable machine contract for scripts and future TUI/GUI clients.
- Target the unified `folio` installation; retain `portable` for disposable tests.
  Hardware follows the disk, so routine use needs no per-machine target selector.

## Development tools

Recommended CLI baseline: keep Bash, jq and sysrepocfg, packaged through the root
Flake's existing `writeShellApplication` adapters. Keep privileged subscriptions
and operations in their current C/libsysrepo/libyang and fixed Shell backends.
Do not introduce a Rust/Go CLI rewrite or another package/dependency manager.

Use common Bash presentation helpers for summaries, tables and terminal progress.
Share transport, exit codes and formatting conventions through public resources;
each module still owns its help, parsing and domain behavior. Avoid a new general
CLI framework merely to register a few commands.

Use the existing Nix development shell, ShellCheck, Bash syntax checks, jq/libyang
validation and focused repository/guest fixtures. Test outcomes and failure
boundaries rather than snapshots of colors or spinner frames. Keep tests under
the owning module's outer `tests/`.

TUI toolkit is not selected yet. A small Bash + `dialog` prototype is a candidate
for menus/forms; it must demonstrate readable task output, resizing and error
handling before adoption. A continuously updating dashboard may justify a richer
toolkit later. TUI dependencies and implementation are outside the initial phase.

## Shared interaction contract

- Human output by default; replace successful raw JSON dumps with useful summaries.
- Preserve `--json`: one result envelope on stdout with `status`, `data`, `error`
  and `taskId`. Send progress/diagnostics to stderr. No ANSI escapes in JSON.
- Keep exit codes: success 0, failure 1, invalid 2, unavailable 3, conflict 4.
- Keep existing user scope by default and `--system` for system mutations.
  Show scope prominently; never elevate silently or mix scopes in one transaction.
- Preserve durable task IDs, request idempotency and `--no-wait`. Ctrl-C stops
  waiting, not the accepted backend task; explain how to inspect that task.
- Add coherent `--verbose` and color controls; disable animations when redirected.
  Respect `NO_COLOR`. Stable JSON, not human table layout, is the scripting API.
- Errors explain the failed phase, actual effects/unknowns, task ID and a useful
  next command. Never claim no changes unless the recorded effects establish it.
- Only report restart/reboot requirements supported by actual deployment facts;
  otherwise state that the requirement is unknown.

## Phase 1: manager CLI first

| Command | Current state | Initial implementation scope |
| --- | --- | --- |
| `folio --help`, command `--help` | Existing | Consistent examples, scope, prerequisites and related commands |
| `folio status [TASK_ID]` | Existing | Human health summary, pending changes, task phase and actionable failures |
| `folio config show` | Existing | Readable module-oriented view; preserve complete JSON output |
| `folio config edit` | Existing | Clear validation/conflict diagnostics and saved-versus-applied result |
| `folio config import/export FILE` | Existing | Explicit scope and outcome; retain round-trip RFC 7951 data |
| `folio modules list/enable/disable` | Existing | Show desired selection separately from applied contribution/prerequisites |
| `folio plan --source DIR` | Existing | Explain scope, target, source, configuration changes and plan identity |
| `folio build PLAN_ID` | Existing | Phase progress, bounded log access, final artifact/task summary |
| `folio apply PLAN_ID` | Existing | Stale-plan errors, activation/verification progress and actual outcome |
| `folio rollback REVISION_ID` | Existing | Explain selected revision and restoration result; preserve scoped authorization |
| `folio cleanup [--apply]` | Existing | Readable preview, protected records and actual removals |
| `folio diff` | Proposed | Desired configuration versus recorded applied configuration; unknown if no baseline |
| `folio tasks [--limit N]` | Proposed | Scoped recent/active tasks, phase, result and timestamps |
| `folio logs TASK_ID [--follow]` | Proposed | Authorized bounded log access, with sensitive data handling |
| `folio history [--limit N]` | Proposed | Applied/retained revisions and rollback availability |
| `folio doctor` | Proposed | Read-only checks for services, permissions, repository/profile drift and prerequisites |

First milestone: improve the existing commands before adding the proposed ones.
Configuration diff is not automatically a full package/service impact analysis.
Initial plans must describe only effects that can actually be established.

System task logs are private today. Add an authorized backend read interface for
tasks/history/logs where needed; do not make root journals world-readable or
have a frontend invoke arbitrary sudo commands. Design a separate versioned
stream contract before advertising JSON log streaming.

## Phase 2: everyday configuration and update workflow

| Command | Proposal and limits |
| --- | --- |
| `folio config get PATH` | Read a documented configuration path without editing a whole document |
| `folio config set PATH VALUE` | Schema-aware typed update through the existing durable commit protocol |
| `folio config reset PATH` | Remove an override and show the resolved inherited/default value, where supported |
| `folio modules info NAME` | Explain scope, settings, commands and prerequisites |
| `folio update [--source DIR]` | Plan, build and apply in the selected scope, retaining every underlying task/plan |
| `folio overview` | Read-only system/user summary; report inaccessible scopes explicitly |

Path syntax, value encoding and reset semantics need discussion before coding.
Use schema validation; do not invent an untyped second configuration store.
Editing/selecting modules alone never activates them.

Prefer a separate `update` convenience command over changing existing
`apply PLAN_ID` semantics. Show its plan before effects; decide interactive
confirmation/noninteractive behavior explicitly. No implicit Flake lock refresh,
Git pull, application update or automatic reboot. Application reconciliation is a
separate workflow; a multi-scope sequence cannot promise atomic rollback.

`doctor` must not repair state. A future repair command needs explicit operations
and preconditions rather than deleting state or resetting personal profiles.

## Phase 3: useful module CLI improvements

| Owner | Existing capability | Initial usability work / proposed additions |
| --- | --- | --- |
| network | System status, connect/disconnect, proxy mode/node | Readable status; list existing connection profiles and proxy nodes so users need not guess UUIDs/names |
| devices | Status, volume/mute, brightness, power profile | Clear units, ranges and availability; distinguish observed hardware from configured support |
| applications | List/init/install/update/remove/reconcile/adopt/prepare/resume/rollback/status | Show app IDs/versions, tasks and pending reconciliation; explain file adoption/conflicts |
| vm | Build/start/stop/status/cleanup | Explain job IDs, frozen-source prerequisites, logs and cleanup protection |
| system | Reboot/poweroff | Explicit machine/scope and accepted-versus-observed completion |
| appearance/input/terminal and other preference modules | Modeled settings and delivered configuration | First use common config access; add owned shortcuts only for meaningful frequent operations |

Network profile provisioning/secrets, Bluetooth pairing and compute environment
management are separate feature decisions, not implied by a nicer status screen.
Do not expose wrappers for unavailable backend behavior. Display unsupported or
missing hardware honestly, preserving existing error codes.

## TUI scope for later discussion

Candidate entry: `folio tui`. Initial pages: overview, modules, configuration
diff, deployment review, tasks/logs and retained history. Include visible scope,
keyboard navigation, help, empty/error states and prerequisite explanations.
Keep network/device/application pages owned by their capabilities.

The TUI must consume stable JSON/backend APIs and submit the same validated
operations as CLI. It must not parse human output, modify sysrepo directly,
store another desired configuration, or run as an unrestricted root process.
Closing it must not cancel accepted work. Module metadata can support navigation
and simple controls; YANG alone cannot specify a complete usable interface.

GUI remains a future client for visual workflows such as display layout/theme
preview. No GUI framework selection or implementation is included yet.

## Delivery order and acceptance

1. Agree on CLI tools, command names, scope and human-output examples.
2. Deliver manager presentation and errors while preserving JSON/exit contracts.
3. Add read-only diff/tasks/history/logs/doctor APIs with authorized access tests.
4. Agree on typed configuration access and convenience update; implement in batches.
5. Improve selected module commands, then validate a narrow TUI prototype.

Reuse focused real-sysrepo and disposable activation/recovery tests. Verify pipe
behavior, missing services, unauthorized calls, conflicts and interrupted waiting.
Run one representative real update/failure scenario for the integrated workflow;
do not rerun every hardware/GUI matrix for presentation-only changes. Record
actual commands/results and update README only when features exist.

## Discussion decisions still open

- Is the existing Bash CLI baseline acceptable? Which Phase 1 additions matter most?
- Should `update` stop for plan approval in a terminal, and how should scripts opt in?
- What path/value syntax makes individual settings understandable and unambiguous?
- What information belongs in the short status summary versus verbose diagnostics?
- Should TUI begin with guided menus or a continuously updating dashboard?

No CLI/TUI behavior has been changed by this proposal.
