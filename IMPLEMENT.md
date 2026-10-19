# CLI Implementation Proposal

Status: reduced discussion draft, 2026-10-19. This revision incorporates the
owner's exclusions. Existing means the command is implemented; new means a
proposal requiring implementation. No CLI behavior is changed by this document.
README.md remains the product usage documentation.

## Scope and tools

Focus on manager configuration, module selection, explicit deployment, task
inspection and recovery. Keep Bash, jq and sysrepocfg for CLI adapters and the
existing C/libsysrepo/libyang subscribers. Use shared presentation/transport
helpers while preserving module ownership and the current authorization model.
No CLI rewrite or new frontend framework is planned.

Improve human-readable output first. Keep stable JSON envelopes and exit codes
for scripts. Configuration saves, plans, builds, activation and observed health
remain distinct. There is no combined update command or automatic reboot.

## Common syntax

`[]` denotes optional arguments. Uppercase identifiers are placeholders. User
scope is the default; `--system` selects system scope. IDs for plans, tasks and
revisions are distinct. Global options precede the command in examples.

| Syntax | State | Function |
| --- | --- | --- |
| `folio --help` | Existing | List commands and common workflows |
| `folio help COMMAND` | Existing | Explain arguments, scope, prerequisites and examples |
| `folio --version` | New | Show CLI version/build identity without contacting subscribers |
| `folio --system COMMAND` | Existing | Operate on system configuration/tasks with required authorization |
| `folio --json COMMAND` | Existing | Emit one stable result envelope on stdout; progress goes to stderr |
| `folio --verbose COMMAND` | New | Show additional diagnostic detail, excluding secrets |
| `folio --no-wait COMMAND` | Existing, limited | Return the task ID after durable build/apply acceptance; do not cancel accepted work when the client exits |
| `folio --environment NAME COMMAND` | Existing | Select the supported environment identity; this is not hardware selection |

Human output should identify scope, phase, result, recorded effects, IDs and the
next useful command. Use terminal detection for styling; no color-control flag.
Preserve exit codes 0 success, 1 failure, 2 invalid, 3 unavailable, 4 conflict.
Ctrl-C stops waiting, not the backend task. Do not claim no effects or a reboot
requirement unless the recorded deployment facts establish it.

## State and task inspection

| Complete command | State | Function and effects |
| --- | --- | --- |
| `folio overview` | New | Summarize readable system/user health, installed target and active tasks; explicitly mark inaccessible scopes |
| `folio status` | Existing | Read selected-scope desired/applied consistency, deployment and recovery health |
| `folio status TASK_ID` | Existing | Read one task's phase, recorded effects, result and error; do not resume it |
| `folio tasks [--limit N] [--state STATE]` | New | List recent tasks, newest first; proposed default 20; filter active/succeeded/failed/interrupted |
| `folio logs TASK_ID [--tail N] [--follow]` | New | Read authorized task logs; proposed default last 100 lines; optionally follow until completion/Ctrl-C |
| `folio history [--limit N]` | New | List applied/retained revisions, configuration/source identity and available rollback information; proposed default 20 |

System task/log/history access needs an authorized backend API where absent.
Never expose private root journals or use arbitrary sudo commands from the
frontend. Log following is initially human-output only; a JSON stream protocol
is outside this scope. Empty results and unavailable information are distinct.

## Configuration and module selection

All writes in this section commit desired data only; they do not install,
activate or change live hardware. Add `--system` for system configuration.

| Complete command | State | Function and effects |
| --- | --- | --- |
| `folio config show` | Existing | Read complete desired configuration and its digest, grouped for human output |
| `folio config edit` | Existing | Edit a private temporary document, validate and commit with concurrency checks |
| `folio config import FILE` | Existing | Validate and commit a complete scoped RFC 7951 document; not a partial merge |
| `folio config export FILE` | Existing | Export repeatable desired-data JSON to a file without repository mutation |
| `folio config get PATH` | New | Read a setting, its effective value and known origin/default information |
| `folio config set PATH VALUE [--json-value]` | New | Validate and commit one setting; normal mode parses an unambiguous scalar, JSON mode accepts an explicit typed value |
| `folio modules list` | Existing | Show desired selection, applied contribution and prerequisite availability |
| `folio modules info NAME` | New | Describe a module, its scopes, settings, commands and prerequisites |
| `folio modules enable NAME` | Existing | Save enabled selection; deployment remains a separate step |
| `folio modules disable NAME` | Existing | Save disabled selection; do not delete personal data |

Provisional paths: `preferences.font-size` and `modules.NAME.SETTING`. Resolve
module list keys and namespaces internally; do not require array positions.
Reject unsupported compound paths or ambiguous value conversions. Example:
`folio config set preferences.font-size 18`. Path grammar and type conversion
still require discussion. No reset command is included.

## Explicit deployment and recovery

These commands support user and system scope. Build/apply wait by default;
`--no-wait` returns after durable acceptance. No implicit Git pull, lock refresh,
application update, target change or reboot occurs.

| Complete command | State | Function and effects |
| --- | --- | --- |
| `folio plan [--source DIR] [--timeout-seconds N]` | Existing | Freeze source/configuration and retain a plan; source defaults to current directory; timeout defaults to 1800 seconds, range 1–86400; show scope, target and plan ID |
| `folio build PLAN_ID [--request-id ID]` | Existing | Build the immutable plan with progress and a final artifact/task summary; do not select a profile |
| `folio apply PLAN_ID [--request-id ID]` | Existing | Reject stale inputs, activate a built plan and verify actual effects; may change files/services |
| `folio rollback REVISION_ID [--rebuild]` | Existing | Restore a retained scoped configuration/closure; explicit rebuild permits compatible reconstruction; system maintenance currently requires root |
| `folio cleanup` | Existing | Preview eligible cleanup and protected objects without removing anything |
| `folio cleanup --apply` | Existing | Remove only eligible unreferenced managed records/roots; system maintenance currently requires root; not unrestricted Nix GC |

Preserve the request-ID idempotency contract. A failed activation may have partial
effects; show the recorded recovery state and task ID. Plans should explain known
changes without promising a complete package/service impact analysis.

## Explicit system power

| Complete command | State | Function and effects |
| --- | --- | --- |
| `folio --system system reboot [--request-id ID]` | Existing | Accept and schedule an authorized reboot of the actual machine |
| `folio --system system poweroff [--request-id ID]` | Existing | Accept and schedule authorized shutdown of the actual machine |

Show the affected machine/scope. Acceptance does not prove completed reboot or
shutdown. These operations are never implicit in configuration/deployment commands.

## Excluded and deferred work

Excluded from this CLI proposal: color-control flags, status watching, diff,
doctor, convenience update and config reset. Do not replace them with aliases.

Network/device CLI design, application CLI work and VM CLI work are deferred.
Existing implementations are not removed by this planning revision. TUI and GUI
implementation/toolkit selection are deferred; no TUI entry command is included.
Migration/keyring helpers remain separate maintenance tools documented in README.
Hardware-target switching, task cancellation and automatic repairs are outside
this initial command set.

## Delivery order and validation

1. Agree on this command list and the remaining configuration path/value syntax.
2. Improve existing manager human output/help while retaining JSON/exit behavior.
3. Add authorized tasks/logs/history APIs and read-only overview.
4. Add module information and schema-aware configuration get/set.

Use ShellCheck, Bash syntax checks, affected Nix outputs and focused real-sysrepo
or disposable guest fixtures. Verify pipes, missing subscribers, permissions,
conflicts, task waiting and partial failures. Do not rerun hardware/GUI matrices
for presentation-only changes. Update README when behavior actually exists.
