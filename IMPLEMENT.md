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

## Complete command catalog: initial contract draft

`[]` marks optional arguments; uppercase words are placeholders, not literal
values. Commands marked **Existing** retain their current backend behavior;
proposed options and presentation changes are explicitly noted. **New** means
the entire command is proposed. User/system variants operate on separate stores.

### Global options and common arguments

| Syntax | State | Meaning |
| --- | --- | --- |
| `folio --help` / `folio help COMMAND` | Existing | Show commands, arguments, examples, scope and prerequisites; deeper subcommand help is proposed |
| `folio --version` | New | Print CLI version/build identity without contacting subscribers |
| `folio --system COMMAND` | Existing | Select system scope; requires operator access for protected operations |
| `folio --json COMMAND` | Existing | Emit the stable machine result envelope on stdout |
| `folio --no-wait COMMAND` | Existing, limited | Return after durable acceptance for deployment/app tasks and VM build; not a universal command flag |
| `folio --environment NAME COMMAND` | Existing | Select the supported environment identity; never selects hardware |
| `folio --verbose COMMAND` | New | Add diagnostic context while keeping secrets and private data out of default output |
| `folio --color auto\|always\|never COMMAND` | New | Control human terminal styling; JSON always remains unstyled |

`PLAN_ID`, `TASK_ID`, `REVISION_ID` and `JOB_ID` are distinct identifiers. Show
them with their type and copyable next commands. Never substitute one for another.
`--request-id ID` belongs only to operations that support idempotent submission;
the same request must not create duplicate work.

### Manager: observation, planning and deployment

All commands in this table support user scope and an explicit `--system` form,
except `overview`, which intentionally summarizes both readable scopes.

| Full command | State | Function and effects |
| --- | --- | --- |
| `folio status` | Existing | Read desired/applied consistency, selected deployment and recovery health; improve human summary |
| `folio status TASK_ID` | Existing | Read one task's phase, recorded effects, result and error; does not resume it |
| `folio status [TASK_ID] --watch` | New option | Refresh the human view until completion or Ctrl-C; no task cancellation |
| `folio overview` | New | Read system/user health, installed target and active task summaries; show inaccessible scope explicitly |
| `folio diff [--module NAME]` | New | Read desired versus last recorded applied configuration; optional module filter, no changes |
| `folio plan [--source DIR] [--timeout-seconds N]` | Existing | Freeze source/configuration and create a retained plan; source defaults to current directory; timeout defaults to 1800, range 1–86400 seconds; no activation |
| `folio build PLAN_ID [--request-id ID]` | Existing | Submit a durable build from that immutable plan, wait by default; does not select a profile |
| `folio apply PLAN_ID [--request-id ID]` | Existing | Activate the built plan after stale-input checks, then verify effects; may change files/services |
| `folio tasks [--limit N] [--state STATE]` | New | List scoped tasks, newest first; proposed default limit 20 and state filter for active/succeeded/failed/interrupted |
| `folio logs TASK_ID [--tail N] [--follow]` | New | Read authorized task logs; proposed default last 100 lines; follow until completion/Ctrl-C, no execution |
| `folio history [--limit N]` | New | List applied/retained revisions, source/configuration identity and available rollback information; proposed default 20 |
| `folio rollback REVISION_ID [--rebuild]` | Existing | Restore a retained scoped configuration/closure; rebuild explicitly permits compatible reconstruction; system maintenance currently requires root |
| `folio cleanup` | Existing | Preview eligible deployment-record/root cleanup and protected objects; no removals |
| `folio cleanup --apply` | Existing | Remove only eligible unreferenced managed records/roots; not an unrestricted Nix GC; system maintenance currently requires root |
| `folio doctor [--module NAME]` | New | Read-only diagnosis of prerequisites, subscriber reachability, permissions and drift; optional module filter; no repair |
| `folio update [--source DIR] [--timeout-seconds N] [--yes]` | New | Review a new plan, build, apply and verify in one selected scope; retain all step IDs and outcomes |

Proposed `update` approval rule: interactive use displays the plan and asks before
build/activation; noninteractive use requires `--yes`. This option accepts the
displayed workflow, not stale plans, invalid configurations, hardware changes or
unrelated destructive actions. It does not refresh inputs, pull Git, update
Flatpaks, cross scopes or reboot. `--no-wait update` is deferred until a durable
parent-workflow contract exists; reject it rather than spawning an orphan shell.

Watching/following is initially human-output only; reject combinations with
`--json` until the stream protocol is specified. Empty history is distinct from
unavailable history; no applied baseline makes `diff` unknown, not empty.

### Configuration and module selection

These commands operate in user scope by default; add `--system` for system data.
Writes below commit desired data only, without deploying or controlling hardware.

| Full command | State | Function and effects |
| --- | --- | --- |
| `folio config show` | Existing | Read the full desired configuration and digest; human view groups settings by module |
| `folio config edit` | Existing | Edit a private temporary document using the configured editor; validate and durably commit with conflict checks |
| `folio config import FILE` | Existing | Validate and commit a complete scoped RFC 7951 document; not a partial merge |
| `folio config export FILE` | Existing | Write a repeatable desired-data document to a file; no repository mutation |
| `folio config get PATH` | New | Read one setting with its effective value and known origin/default information |
| `folio config set PATH VALUE [--json-value]` | New | Schema-aware single-setting commit; normal mode parses an unambiguous scalar, JSON mode accepts an explicit typed scalar/list/object |
| `folio config reset PATH` | New | Remove an optional explicit override; report resolved inheritance/defaults, reject mandatory/identity paths |
| `folio modules list` | Existing | Read module selection; enhance output with available/applied/prerequisite distinctions |
| `folio modules info NAME` | New | Read a module's description, supported scopes, settings, available commands and prerequisites |
| `folio modules enable NAME` | Existing | Commit enabled selection; no install, activation or hardware action |
| `folio modules disable NAME` | Existing | Commit disabled selection; personal data is not deleted by this command |

Provisional user-facing paths: `preferences.font-size` for a global preference,
`modules.NAME.SETTING` for a named module. Resolve module list keys and YANG
namespaces internally; never require array positions. Restrict the first version
to unambiguous supported paths and reject unsupported compound/list edits.
Example proposals: `folio config set preferences.font-size 18` and
`folio config get preferences.font-size`. Path grammar and scalar coercion still
need agreement; ambiguous conversion must fail rather than silently change type.
Reset requires reliable override provenance, not deletion of a normalized default
followed by a claim that inheritance has been restored.

### Network: system scope only

All commands require the network capability and authorized system access. Runtime
controls are separate from desired policy. No command prints connection secrets.

| Full command | State | Function and effects |
| --- | --- | --- |
| `folio --system network status` | Existing | Read actual interfaces/connectivity and proxy availability/mode/node |
| `folio --system network connections` | New | List saved connection names, UUIDs, types and active state without credentials |
| `folio --system network connect UUID INTERFACE` | Existing | Activate an existing NetworkManager profile on an interface; can change connectivity |
| `folio --system network disconnect INTERFACE` | Existing | Disconnect that interface; may interrupt remote access |
| `folio --system network proxy-nodes` | New | List available nodes and current selection in the owned proxy group |
| `folio --system network proxy-mode rule\|direct\|global` | Existing | Change the live proxy mode and return observed state; desired policy remains unchanged |
| `folio --system network proxy-select NODE` | Existing | Select an available live proxy node; no desired-policy commit |

### Devices: user/session scope only

| Full command | State | Function and effects |
| --- | --- | --- |
| `folio devices status` | Existing | Read actual audio, backlight, power-profile and device availability |
| `folio devices volume LEVEL` | Existing | Set default audio output volume to 0–100 percent |
| `folio devices volume +DELTA` / `folio devices volume -DELTA` | Existing | Adjust default output volume by 1–20 percentage points |
| `folio devices mute` | Existing | Toggle default output mute; report observed result |
| `folio devices brightness LEVEL` | Existing | Set supported backlight brightness to 0–100 percent; unavailable on unsupported hardware |
| `folio devices brightness +DELTA` / `folio devices brightness -DELTA` | Existing | Adjust supported backlight by 1–20 percentage points |
| `folio devices profile balanced\|power-saver\|performance` | Existing | Change the available live power profile; unavailable profiles fail explicitly |

### Applications: user scope only

`APP` is `zen`, `obs` or `all`, defaulting to `all`. The existing adapter accepts
`--offline`, `--adopt-files` and `--request-id ID`; document their applicable
behavior per operation and reject meaningless combinations in the improved CLI.
`--offline` forbids fetching; `--adopt-files` explicitly permits supported regular
file adoption. Neither option authorizes replacing browser profiles or credentials.

| Full command | State | Function and effects |
| --- | --- | --- |
| `folio apps list [APP]` | Existing | Read desired/observed app state and supported configuration delivery |
| `folio apps init [APP]` | Existing | Add the user Flathub remote if absent and verify origin/signatures; requires online mode, never replaces an existing remote |
| `folio apps install [APP]` | Existing | Commit selected intent, then submit installation; distinguish saved intent from failed realization |
| `folio apps update [APP]` | Existing | Explicitly update selected managed apps; separate from Nix system/user deployment |
| `folio apps remove [APP]` | Existing | Commit deselection and remove the owned app contribution; preserve personal application data |
| `folio apps reconcile [APP]` | Existing | Align owned installed refs/configuration with recorded desired state and report conflicts |
| `folio apps adopt [APP]` | Existing | Explicitly adopt supported existing installation state; explain file-adoption requirements |
| `folio apps prepare [APP]` | Existing | Prepare retained Flatpak transaction/content for selected apps against the applied user manifest; may fetch unless offline |
| `folio apps status TASK_ID [APP]` | Existing | Read the recorded app task result/phase |
| `folio apps resume TASK_ID [APP]` | Existing | Resume a supported interrupted app task after validating its retained state |
| `folio apps rollback REVISION_ID [APP]` | Existing | Restore a supported retained app revision using available retained content |

### Disposable VMs: user scope only

| Full command | State | Function and effects |
| --- | --- | --- |
| `folio vm build JOB_ID SOURCE` | Existing | Build a guest from an immutable store snapshot; retain job metadata; supports `--no-wait` |
| `folio vm start JOB_ID` | Existing | Start the prepared disposable guest, without host disks/bridge changes |
| `folio vm stop JOB_ID` | Existing | Stop the owned guest job, not the host |
| `folio vm status JOB_ID` | Existing | Read job/build/process state and available log locations |
| `folio vm cleanup JOB_ID` | Existing | Refuse active jobs, archive supported metadata/logs and remove owned disposable state/roots |

### System power and future TUI entry

| Full command | State | Function and effects |
| --- | --- | --- |
| `folio --system system reboot [--request-id ID]` | Existing | Accept and schedule an authorized reboot of the actual running machine; acceptance is not observed completion |
| `folio --system system poweroff [--request-id ID]` | Existing | Accept and schedule authorized shutdown of the actual machine; not implicitly limited to a guest |
| `folio tui` | New, later phase | Open the user-scope interactive client with overview/modules/diff/tasks pages |
| `folio --system tui` | New, later phase | Open system-scope views using the same operator checks; no unrestricted root UI |

Account/keyring migration helpers remain explicit maintenance tools documented in
README. They are not automatic steps of `update`, `doctor` or hardware selection.
Changing installed hardware targets, editing Flake inputs and arbitrary task
cancellation are outside this initial command set.

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
