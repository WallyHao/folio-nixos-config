# Folio

Folio is a NixOS configuration framework built around module-owned YANG models
and sysrepo. One CLI manages system and user configuration; each module executes
its own operations. Root Nix composition lives in the manager module.

Status: foundation, durable user configuration, Foot deployment, root deployment
and system-owned power actions have passed isolated UEFI guest tests. A standalone
UEFI image and module-owned VM lifecycle are implemented. Later modules below
remain the implementation contract until their stages pass. No development-host
activation or physical installation has been performed. See [STRUCTURE.md](STRUCTURE.md)
for directory ownership.

## Foundation workflow

The root Flake reuses Sylphy's pinned Nixpkgs/Home Manager inputs. Packages include
`sysrepo-library` (3.7.11), `sysrepo-libyang` (3.13.6), `sysrepo-tools`,
`manager-normalizer`, `manager-input`, and `manager-bootstrap`. The minimal
`nixosConfigurations.portable` is a disposable storage fixture, not a physical
installation target. `homeConfigurations.folio` renders Foot using the adapted
Sylphy renderer and selected font/padding. Neither output queries live sysrepo.

```sh
nix develop
nix build --no-link .#checks.x86_64-linux.catalogue .#checks.x86_64-linux.foundation
bootstrap=$(nix build --no-link --print-out-paths .#manager-bootstrap)
# Within the development shell, initialize only a disposable user instance:
scratch=$(mktemp -d)
export XDG_STATE_HOME="$scratch/state" XDG_RUNTIME_DIR="$scratch/run"
mkdir -p "$XDG_RUNTIME_DIR"
folio-repository user init "$bootstrap/models/user" "$bootstrap/user.json"
folio-repository user cfg --export --module folio-environment --format json --defaults report-all
folio-prepare-input "$bootstrap/user.json" "$bootstrap" > "$scratch/folio-input.json"
```

`folio-repository` binds the documented persistent/runtime paths and distinct
system/user SHM prefixes. `init` installs models and initial data atomically through
sysrepo, preserves existing startup data, and refuses model/library identity
changes requiring an explicit future upgrade. `ctl`/`cfg` are maintenance wrappers;
direct edits do not implement the managed durable-commit protocol.

Frozen input format 1 contains scope, normalized RFC 7951 configuration, a
versioned read-only bootstrap system descriptor, model SHA-256 identities, pinned
tool versions, and configuration/descriptor digests. Digests cover compact JSON
with lexically sorted object keys plus one LF. libyang validates types and emits
defaults; only the schema's system-ordered module/user/group lists are sorted.
User-ordered arrays and RFC 7951 scalar encodings are preserved. A source snapshot
containing `folio-input.json` consumes that data through pure Nix and rejects
mismatched digests/model/tool identities. Resolved public preference values and
their origins are recorded and checked; absent user overrides inherit the system
descriptor's defaults. The provisioned system service publishes its compiled
descriptor; standalone bootstrap retains an explicit bootstrap origin.

For a separate root-identity/scope check, run
`bash modules/sysrepo/tests/scopes.sh "$bootstrap"` in the development shell.
It requires Linux user/mount namespaces and mounts private `/var/lib` and `/run`;
it does not initialize system state on the development host. Managed rollback
remains Stage 04.

## User configuration development

The `folio` package provides `config show/edit/import/export` and
`modules list/enable/disable` in user scope. Writes use sysrepocfg and the real
manager C subscriber. The Home Manager output installs `folio-manager.service`;
it initializes the repository before subscribing and reconciles interrupted
configuration commits first. Guest activation is covered by the user-deployment
check; the portable image provisions the initial product system services.

For isolated development, keep the scratch XDG paths from the foundation example
and run `folio-manager-subscriber user "$bootstrap"` in the development shell.
In another shell with the same XDG paths, use `folio --json config show`,
`folio config edit`, or `folio config import FILE`. Exported documents contain
desired RFC 7951 data, suitable for reviewing or importing; `show` returns the
configuration with its digest. Stop the development subscriber when finished.

Edits use private temporary documents and optimistic digest checks. Commits
serialize writers and durably record prepared/accepted/saved phases. Recovery
validates journal digests, restores prepared-only data, and rolls accepted data
forward into running/startup before consumers start. A failed save remains a
failure. JSON commands return one `{ status, data, error, taskId }` envelope;
missing write subscribers return exit 3, validation exit 2, conflicts exit 4.
Unimplemented rollback explicitly returns exit 3; unsupported scopes return exit 2.

Run `nix build --no-link .#checks.x86_64-linux.configuration` for the bounded
real-sysrepo commit/edit/conflict/failure/restart integration scenario.

## User build and deployment

The following workflow requires the provisioned `folio` account with
`HOME=/home/folio`, a running user manager subscriber and its initialized
repository. The portable UEFI image provides this disposable environment.

```sh
folio config edit
plan_id=$(folio --json plan --source /path/to/folio-checkout | jq -r .data.planId)
folio build "$plan_id"
folio apply "$plan_id"
folio --json status
```

Plans copy the root Flake/lock, module code and optional assets once, exclude
environment metadata/state/output paths, reject escaping symlinks and evaluate
only immutable store bytes. Each plan binds desired configuration, descriptor,
source identity, current profile and a bounded timeout. Build/apply submit durable
tasks to independent `folio-task-<id>.service` user units. `--no-wait` returns the
task ID; `--request-id ID` makes repeated identical submissions return that task.
Client exit or subscriber restart does not cancel the worker. Use
`folio status TASK_ID` to inspect the recorded outcome.

Build never publishes applied state. Apply rechecks stale inputs, enforces the
provisioned account/home and one standalone Home Manager profile, preserves first
adoptions with unique backups and rejects later changes to managed files. It
records profile effects before activation and verifies the actual selected
profile and generated files before success. Disabling terminal removes its
managed contribution while preserving application data. The profile is
`$XDG_STATE_HOME/nix/profiles/home-manager` (default `~/.local/state/...`). Plans,
tasks, successful builds and `current.json` live under the scoped `deployments/`;
explicit Nix GC roots retain source/worker/artifact closures. Cleanup and managed
rollback remain Stage 04; interrupted activation reports failure or interruption.

Status probes profile/configuration drift and actual startup persistence. The C
subscriber also publishes configuration/state and deployment plans/tasks through
the operational datastore, for example
`folio-repository user cfg --export --datastore operational --module folio-deployment --format json`.
Configuration health does not establish desktop or hardware health.

Run `nix build --no-link .#checks.x86_64-linux.user-deployment` for real isolated
user edit/build/apply, changed Foot output, adoption/conflict, disable/data
preservation and operational-state evidence. The development-shell command
`bash modules/manager/tests/build.sh . "$bootstrap"` separately checks immutable
source capture and a real user worker surviving subscriber exit; it builds into
isolated XDG roots and never activates on the development host.

## System deployment and disposable guests

The disposable system adapter provisions `folio`, the dedicated
`folio-operators` management group, an unprivileged `folio-builder` account and
separate root/user subscribers. Lingering starts the user subscriber without
selecting or applying a Home Manager generation. Root plans and builds evaluate
and build through `folio-builder`; only the recorded root worker selects the
system profile and runs the verified closure's fixed activation entry point.

An authorized operator can use `folio --system config show/edit/import/export`,
`modules list/enable/disable`, `plan`, `build`, `apply` and `status`. Saves change
desired data only. There is no
passwordless sudo rule or additional Nix trusted user.

The root repository and SHM directories use the provisioned operator group and
setgid mode 2770; root journals/plans remain private. Sysrepo checks the sender's
actual session user against module permissions. Its callback session user is the
subscriber identity, so it is not treated as an authenticated requester name.
This is the documented local administrative group boundary, not per-user NACM.

`/run/folio/public/system-descriptor.json` is root-owned, read-only compiled system
identity/defaults/capabilities data. Saving desired settings does not republish
them as applied. User snapshots bind this descriptor when available, including
its digest, registered home and preference origins. The configuration-commit RPC
carries `configuration-json` text and validates the document with libyang, keeping
singleton lists/leaf-lists intact across the pinned library's RPC transport.

Run `nix build --no-link .#checks.x86_64-linux.system-scope` to verify real
operator/non-operator access, isolated desired stores, durable root commits,
read-only actual descriptors and user plan binding in a disposable guest.
Run `nix build --no-link .#checks.x86_64-linux.system-deployment` for actual UEFI
boot, unprivileged system builds, root activation, changed timezone, unchanged
user generation, unauthorized/payload rejection and externally observed power.

```sh
# On a KVM-capable development machine; this launches only a disposable guest.
image=$(nix build --no-link --print-out-paths .#vm-image)
"$image/bin/run-folio-vm" portable
# Inside the guest, as the provisioned folio account:
folio --system config edit
plan_id=$(folio --json --system plan --source /etc/folio/source | jq -r .data.planId)
folio --system build "$plan_id"
folio --system apply "$plan_id"
folio --system system reboot
```

The image includes its immutable source at `/etc/folio/source` and locked inputs
in the guest store. No live repository is read during evaluation. The prototype
`folio` password is `kl;'`. Boot uses
systemd-boot, EFI and labeled disposable disks; physical installation is pending.
Power commands return durable **acceptance**, never a claim of completed reboot
or shutdown. Completion requires outside observation.

The VM module owns `folio vm build JOB_ID IMMUTABLE_SOURCE`, `start`, `stop`,
`status` and `cleanup`. Enable/apply its user contribution before using its RPC
commands; system provisioning supplies the KVM group, while start probes actual
device access. Build waits by default; `--no-wait` returns its stable job ID.
The image's launcher works before a Folio user service has been installed.
`folio-vm-tool status|stop|cleanup portable` controls that bootstrap job from the
`vm-tools` package. Each job has a private qcow2 overlay, EFI variables and QMP
socket under `$XDG_STATE_HOME/folio/vm/jobs/`. Networking uses QEMU user mode.
Stop requests ACPI shutdown and waits a bounded time; it never kills a guest to
claim success. Cleanup refuses active jobs and archives metadata/build/serial
logs under `folio/vm/logs/` before removing its disposable disk and GC roots.

## Development handoff

Implementation follows [tasks/INDEX.md](tasks/INDEX.md), which defines ordered
stages, dependencies, acceptance gates, and AGENT handoff requirements. Read
[tasks/WORKFLOW.md](tasks/WORKFLOW.md) and
[tasks/SYLPHY-REUSE.md](tasks/SYLPHY-REUSE.md) before implementing a stage.

Development, comments, CLI help and messages, task records, and commit messages
must be in English. Reuse existing Sylphy implementations and preferences where
applicable, adapting them to Folio's module and identity contracts. Batch related
changes and run targeted checks during development. Run the relevant acceptance
gate at each coherent stage boundary, then commit on `main` using an English
Conventional Commit message. Do not run the complete suite after every small edit.

Product documentation is maintained only in this root README for now. Task files
are implementation work records; existing STRUCTURE.md remains a layout reference.
Module READMEs and additional documentation trees shown in the planned layout are
deferred until their scope is confirmed.

## Initial environment

- Environment: `portable`; platform: `x86_64-linux`.
- Account: `folio`; home: `/home/folio`; prototype password: `kl;'`.
- Emacs is the editor, including Org and Org-roam. Neovim and Panel are excluded.
- Reuse Sylphy's Everforest dark/hard palette, Maple Mono NF CN, GoogleDot cursor,
  desktop geometry, and applicable application preferences. Adapt identity and paths.
- Preserve existing application data; do not copy browser logins, credentials,
  or private network data into source or build inputs.
- Hardware/storage definitions must name the actual deployment target. VM disks
  are disposable fixtures, never assumed to describe a physical installation.

## Ownership and scope

The manager owns environment/user identity, module selection, shared preferences,
configuration revisions, build inputs, and deployment records. Application models
and their callbacks belong to the corresponding module. Sysrepo owns modeled
storage, validation, and subscription dispatch.

Modules do not import one another's private implementation. Public YANG imports
and capability requirements are allowed. The Nix composition supplies public
resources explicitly. No runtime discovers and calls another module's private
scripts. Manager build/deploy callbacks do not dispatch arbitrary module actions.

There is one module directory per capability, with optional system and user
adapters. There are no top-level host/home trees. A user adapter can require a
system capability; missing prerequisites produce a finding, not silent enablement
or privilege escalation.

System and user module selections are separate. Defaults are:

| Module | System contribution | User contribution |
| --- | --- | --- |
| manager | System configuration and deployment service | CLI and user configuration/deployment service |
| sysrepo | System repository initialization and models | User repository initialization and models |
| system | Boot, storage, accounts, locale, time, console, logging, zram, Nix | None |
| network | Connectivity, proxy, DNS, firewall, SSH | Preferences and command adapters where needed |
| devices | Device access, Bluetooth, power policy | Audio session, device controls and observed state |
| vm | KVM access where supported | VM build, launch, stop and disposable state |
| desktop | Niri session availability and portal prerequisites | Niri preferences, Waybar, Mako, launcher and clipboard |
| appearance | System/console appearance where applicable | Fonts, cursor, GTK and shared resources |
| input | Required input infrastructure where applicable | Fcitx5/Rime configuration and session integration |
| terminal | Login shell registration | Foot, Zsh, prompt, tools and Typst |
| git | None by default | Git/GitHub CLI |
| emacs | None | Emacs, Org, Org-roam |
| codex | None | Codex |
| applications | Flatpak support | Flatpak apps and their configuration |

The concrete adapter owns the NixOS/Home Manager options. In particular, audio
device setup and user audio services are not configured independently by two
adapters. System-provided user services are reported as system contributions.

## Nix interface

Only the root has `flake.nix` and `flake.lock`. It declares inputs and calls
`modules/manager/src/outputs.nix`. That file constructs outputs without querying
sysrepo and explicitly enumerates the module catalogue. Directory presence does
not enable a module. An unknown module or unsupported scope is an error.

Each `default.nix` is a function receiving `pkgs` and `lib`. The manager entry
may additionally receive `cliCommands`, the collected public command map; this
is build-time data, not other modules' implementations. Collection uses Nix
laziness so the manager's own command declarations do not depend on its CLI build.

| Optional output | Type and meaning |
| --- | --- |
| `packages` | Attribute set of named derivations; defaults to `{}`. |
| `models` | `{ system = [ paths ]; user = [ paths ]; }`; lists default empty. Include model import closure. |
| `commands` | Attribute set of command roots to `{ path; scopes; }`; scopes are `system` and/or `user`. Defaults to `{}`. |
| `nixosModule` | `null` or a context-to-NixOS-module constructor. |
| `homeManagerModule` | `null` or a context-to-Home-Manager-module constructor. |

Adapter context is `{ identity, globals, settings, capabilities }`: identity
contains environment, platform, scope and optional account; globals are resolved
public preferences; settings are only this module's normalized configuration;
capabilities are published prerequisite facts. Nix supplies standard module
arguments normally. Constructors do not access a mutable repository.

The manager's bootstrap output file does not call its own public entry back
through itself. Internal Nix files are ordinary imports, never independent Flakes.
Duplicate public command roots, conflicting YANG names/revisions, unknown data,
and unsatisfied prerequisites fail explicitly.

Install the available catalogue's applicable models and command adapters even
when a capability is disabled; do not start its application service until selected.
Introduce a new module's model through a validated schema upgrade before accepting
configuration that uses its new nodes. Model availability is not activation.

Initial root outputs are `packages.<platform>.<module>-<component>`,
`packages.<platform>.folio`, `nixosConfigurations.portable`,
`homeConfigurations.folio`, `devShells.<platform>.default`, and
`checks.<platform>.*` when checks exist. Standalone outputs use packaged bootstrap
data unless a prepared source snapshot supplies a frozen configuration file.
No impure live-database evaluation is required.

## Models and data

YANG 1.1 models use names `folio-<capability>`, namespace
`urn:folio:<capability>`, dated revisions, and kebab-case node names. JSON uses
RFC 7951 encoding. Defaults, ranges, enumerations, references within one data
tree, and structural constraints belong in YANG. Nix evaluation checks package
and adapter constraints; runtime probes check actual effects.

The manager defines the shared roots; modules augment their own configuration
and state branches. The conceptual tree in each scoped repository is:

```text
folio-environment:environment
├── name                         portable
├── platform                     x86_64-linux
├── scope                        system | user
├── account                      user scope identity
├── users                        system-owned account records
├── preferences                  shared defaults or user overrides
├── modules[name]
│   ├── enabled
│   └── <module-owned settings>
├── configuration                revision/hash and persistence state (observed)
└── state                        applied revision and health (observed)

folio-deployment:deployment
├── plan / build / apply / rollback actions
└── tasks[id]                    observed task records
```

Module-specific schema structure is defined locally. A disabled module's data
may remain stored; its configured services and packages are removed on apply.
Disabling a module does not delete its application data.

System user records contain name, UID, home, groups, and login shell policy.
User repositories cannot create accounts or redefine their system identity.
Public system identity/defaults are exported as a versioned read-only descriptor;
user plans bind its digest. No cross-repository `leafref` or two-way data sync is
assumed. References across scopes are validated against this descriptor.
Declared capabilities and observed health are separate fields; a declaration
alone does not prove that a prerequisite service or device is working.

Public preferences include palette roles, font family/sizes, language and input
defaults. The system owns machine-wide defaults; users own personal overrides;
module-specific overrides win last. The resolved values and origins enter the
snapshot. Identity and privilege fields are not overridable preferences.

## Datastores and persistence

There are two independent repository instances, using separate shared-memory
prefixes and runtime directories:

| Scope | Persistent root | Runtime root |
| --- | --- | --- |
| System | `/var/lib/folio/` | `/run/folio/` |
| User | `$XDG_STATE_HOME/folio/` | `$XDG_RUNTIME_DIR/folio/` |

Each persistent root contains `sysrepo/`, `configuration/`, `deployments/`, and
`backups/`. User state defaults to `~/.local/state/folio`. Wrappers bind repository
and shared-memory settings; application clients do not select arbitrary paths.
The fixed sysrepo package must support both root and user repository ownership.

`candidate` holds drafts, `running` holds accepted desired data, `startup` holds
persisted desired data, and `operational` reports actual state. None of these
datastores substitutes for a deployment journal.

The supported CLI edits a private temporary RFC 7951 document. It submits a
manager configuration-commit operation with an expected base digest; it does not
leave a shared candidate open while the user edits. One commit lock per scope
serializes writers. Concurrent stale edits fail with a conflict.

Commit protocol: validate and save a prepared journal with before/after data;
update running; persist an accepted journal marker; synchronize startup; then
report saved. Journal writes use atomic replacement and durable file/directory
flushes. On restart, an accepted record rolls forward; a prepared-only record
restores the previous data. Reconcile both datastores before starting consumers.
Callbacks validate configuration but do not apply external side effects during
this protocol. Applying changes is a separate operation after durable acceptance.

Direct sysrepocfg datastore edits are maintenance operations outside this
persistence protocol. Read/export and RPC submission still use sysrepocfg.
Configuration save failure is reported; it is not called a successful deployment.

Initial defaults are generated from versioned module defaults and the chosen
environment identity. Import them only into a new repository. Boot and ordinary
rebuild never overwrite an existing desired configuration. Import/export is
explicit; exported JSON is a backup/review artifact, not a second live authority.

## Execution and passwordless updates

CLI runtime dependencies are Bash, jq and sysrepocfg. Subscribers use C with
libsysrepo/libyang. Fixed store-path Shell programs may implement command-oriented
operations, receiving JSON on stdin and returning modeled JSON. No `eval` or
request-supplied executable paths are used. Compilers and headers stay in build
or development dependencies, not the installed user environment.

Each module owns its subscriptions. A module may run separate system and user
subscribers, only when needed. No generic manager action router is introduced.
Module-private helpers remain local; shared code is extracted only for actual
reuse. Systemd supervises subscribers and separate long-running workers.

User builds/activation execute as the account using standalone Home Manager.
They use the ordinary Nix daemon permissions. System activation executes in a
preinstalled root manager service. `folio` is an explicitly authorized prototype
operator via a dedicated management group and scoped repository permissions.
This is administrative authority granted at installation, not absence of privilege.
It does not depend on a blanket passwordless sudo rule or adding the account to
Nix `trusted-users`.

The system manager validates the requested environment, operation and recorded
input, then uses a known unprivileged build identity and a fixed activation
worker. The root worker consumes immutable plan/artifact identities. Only the
recorded NixOS closure is eligible for activation; arbitrary shell payloads or
mutable activation paths are rejected. This prototype trusts the authorized
operator's selected source code as system administration input.

The first installation provisions accounts, groups, repositories and root
services with installation privileges. Later user installs and system updates
require no sudo password. Updating runtime schema/services follows the same
scope: user upgrades as the user, system upgrades through the installed service.
Repository groups grant coarse local access; this is a single-operator prototype,
not a hostile multi-user security boundary. Do not trust a username supplied in
JSON as authentication. System handlers use library/session identity and the
provisioned access policy; they do not assume NETCONF/NACM is automatically in
the direct sysrepocfg path.

## CLI contract

```text
folio config show|edit|import|export [--system]
folio modules list|enable|disable NAME [--system]
folio plan|build|apply|rollback [--system]
folio status [--system]
folio applications list|install|update|remove|reconcile ...
folio --system system reboot|poweroff
folio vm build|start|stop|status ...
```

Environment defaults to the installed `portable` identity; `--environment`
selects another registered environment. User scope defaults to the current
account. `--system` explicitly selects system configuration/deployment. System-only
power commands declare their scope and do not silently reinterpret a user command.
Unsupported scopes fail before side effects. Nested subcommands are owned by
their module's command adapter.

Module selection edits desired data; `apply` applies it. Flatpak install/remove
commands first persist the new application selection, then submit their own
application task. A failed installation leaves visible desired/actual drift.
Updates have explicit resolution plans; automatic updates are initially disabled.
`apply` without a scope flag updates the user Nix/Home Manager profile. Application
installation and manifest materialization are explicit applications operations;
their pending state is visible after a configuration-only update.

CLI defaults to waiting for a task result, with `--no-wait` returning its ID.
Interrupting the CLI stops waiting, not the durable task. `--json` emits one
result envelope: `{ status, data, error, taskId }`; progress goes to stderr.
Exit codes: 0 success, 1 operation failure, 2 usage/model validation error,
3 unavailable service/evidence, 4 conflict. Missing subscribers are unavailable,
not successful no-ops. A successful RPC transport is not proof of task success.
Short RPCs default to a 30-second timeout; long operations acknowledge a durable
task instead of blocking that callback. Build/task timeouts are configurable and
recorded in the plan. Retrying a task submission with the same request ID and
input digest returns the original task, not a duplicate deployment.

## Build and deployment protocol

One immutable input contains normalized configuration, required public system
descriptor, YANG models/imports, source bytes and `flake.lock`. Hash normalized
libyang JSON with deterministic object ordering; preserve YANG list semantics
and RFC 7951 number encoding. Record the tool/model identities used. Sources
are copied once before validation; exclude runtime state, credentials and outputs.
Reject escaping symlinks. The editable working directory is not a running build's
input. Git metadata is not required for a local prototype snapshot.

Plans record scope, environment, owner, input digest, prior deployment, proposed
effects, prerequisites and artifacts. Builds have no activation side effects.
Configuration changes after planning produce a stale-plan conflict on apply.
Successful closures and retained rollback closures have explicit Nix GC roots.
Retain at least the current and previous successful deployment; older records
are pruned only through explicit cleanup. Cleanup preserves all closures and
snapshots referenced by active tasks or retained recovery records.

Task phases are `queued`, `validating`, `building`, `activating`, `verifying`,
`succeeded`, `failed`, or `interrupted`. Persist the current phase before each
external effect. Records include before/after profile paths, observed results,
errors and timestamps. Return a task ID only after durable queue submission.
Systemd workers outlive their subscriber and requesting terminal. Manager upgrades
leave the old worker/closure rooted until its task finishes.

There is one mutation lock per scope/account, and an applications lock for Flatpak
changes. Apply and application operations take user-configuration before application
locks when both are needed; no reverse lock order. Cross-scope work takes no
simultaneous scope locks. Check revisions again before activation.

One account-owned Home Manager profile is authoritative. Boot preserves its
selection; system-only apply does not publish another Home generation. A combined
update is a CLI sequence of separately submitted system, user and applications
operations, each bound to its own plan. Stop on failure and report partial success;
the manager service does not dispatch application RPCs.

Recovery probes actual profiles/services after an interrupted side effect. It
does not blindly re-run activation or destructive commands. Preserve conflicting
unmanaged regular files with unique backups before adoption; later unexpected
edits are reported as conflicts. Activation failure retains before/after evidence.
Attempt restoration only for recorded reversible effects; report recovery-required
when it fails. Application-owned mutable data is outside generation rollback.

Managed rollback restores the target scope's retained closure and matching desired
configuration, including required models. Do not automatically reapply a newer
failed desired revision. If data/schema restoration cannot complete, stop and
report the mismatch. Rebuild an old source with the current protocol when an old
closure does not support managed rollback.

## Model upgrades

Use YANG revisions for schema changes, not a second per-module API-version system.
Treat additive optional fields separately from renamed/removed fields or changed
types. Modules own explicit migrations when existing data changes meaning.

Serialize configuration and deployment mutations; quiesce affected subscribers;
export startup/running data and capture model revisions; migrate an isolated copy;
validate with the new schema; then install schema/data and restart subscribers.
Preserve the old repository backup and closure. Failed migrations restore that
pair before resuming. Do not hot-replace schemas while callbacks or deployments
are active. Recovery tooling can restore offline without the manager running.

## Flatpak and application configuration

All Flatpak applications belong to `applications`. Install as the user with
`--user`; initialize Flathub explicitly from its official repository descriptor.
The bootstrap app set is Zen (`app.zen_browser.zen`) and OBS
(`com.obsproject.Studio`). Typst stays in `terminal` through Nix.

The application model records ID, remote, branch, architecture, enabled state,
version policy, optional requested commit, configuration settings and managed
permission overrides. Observed data records installed full refs/commits, runtime
and extension refs, configuration digest and health. Ownership is keyed by
installation scope plus full ref, not display name.

Default version policy is explicit refresh of the stable branch. A normal
reconcile preserves an already resolved commit; only update/initial install
resolves a newer commit. Plans record the resolved application and dependency
commits. A pinned app uses its requested commit. `flatpak pin` is not used as
application version locking. No timers silently update managed applications.

Preparation downloads required refs without activating them, captures the actual
resolved commits, and revalidates the plan before deployment. If a remote or
local ref changes, replan rather than silently deploying different bytes. Deploy
from prepared local content, checking the resulting commits. No online Flatpak
operation occurs during Nix evaluation or a Nix derivation build.

Serialize mutations and apply per application, recording before/after state.
There is no atomic transaction across all apps or across Flatpak and Home Manager.
On failure, preserve completed results and allow idempotent resume. If an existing
installation was not Folio-owned, explicit adoption is required before modifying
it. Removal preserves user data; unrelated apps/remotes/overrides are left alone.

Record previous refs/commits for rollback. Preflight verifies that old applications,
dependencies and extensions remain available locally or remotely. If not, report
rollback-unavailable before changing anything. Version records are not an archive;
indefinite offline Flatpak rollback is not promised. NixOS rollback alone does not
restore Flatpak versions. Shared runtime changes are tracked and may affect
unmanaged apps; do not prune or downgrade shared runtimes automatically.

Nix generates a manifest of managed application files. User activation publishes
the manifest and roots its immutable sources. The applications runtime materializes
files as regular files using temporary files and atomic replacement, with content
hashes and unique first-adoption backups. Do not expose the whole Nix store merely
to resolve Home Manager symlinks inside a Flatpak sandbox. Reject path traversal,
unexpected symlink destinations and conflicting managed ownership. Keep immutable
generated sources and the manifest rooted for rollback.

Reconciliation order is prerequisites, prepared app installation, managed files,
and verification. If a profile does not exist yet, report `configuration-pending`;
do not guess a profile or overwrite its registry. Retry after profile selection
or creation. Configuration changes requiring restart report `restart-required`
without killing the app or discarding user work.
Refuse file deployment when the manifest's desired configuration digest is stale;
build/apply the current user configuration first. This prevents new desired
settings from being reported as applied using an old manifest. Query Flatpak
using explicit machine-oriented columns and fixed locale, not translated progress
text. SDKs and flatpak-builder are not installed merely to run applications.

Zen manages an explicitly selected profile's supported preference file and owned
CSS resources, adapted from Sylphy. Do not overwrite `prefs.js`, browser databases,
session data, logins, or arbitrary existing CSS. Theme files use a Folio-owned
namespace; existing entry files require explicit adoption or a supported include.
The initial three-workspace layout is a one-time seed when supported, not a
continuous overwrite of mutable workspace state.

OBS installation, desktop integration and declared permissions are managed.
Scenes, recording profiles, accounts and mutable preferences stay app-owned.
Only supported external theme/configuration interfaces are used; GTK theming
alone does not establish OBS/Qt theming parity. Report unsupported appearance
features rather than overwriting OBS state. Screen capture is verified through
desktop portals and PipeWire. Devices and desktop retain those host capabilities.

## Operations and VM policy

Manager owns build/deploy/rollback; network owns connection/proxy actions;
devices owns audio/Bluetooth/brightness; desktop owns exposed session actions;
applications owns Flatpak lifecycle; system owns reboot/poweroff; vm owns guest
lifecycle. Other modules need operations only when a concrete public action exists.
Read-only state providers may have runtime without an operations directory.

Power requests acknowledge acceptance and then schedule the power operation.
They are never reported as completed before external observation. Commands are
tested only against disposable guests, never by powering off the development host.

Use QEMU/KVM directly with OVMF for UEFI tests; libvirt is not an initial dependency.
Use user-mode networking and temporary disk images by default. No host disk
passthrough, bridge changes or automatic reboot of the host. Guest jobs use stable
IDs, logs and explicit cleanup. VM access is granted at initial system provisioning.

## Verification

Four levels: static checks, module tests, integration tests, and complete-system
tests. All tests live under the owning module's outer `tests/`; those directories
remain empty until implementation. This specifies acceptance boundaries, not
test files or a mandated test framework.

- Static: Nix/Shell syntax, shell lint, YANG import/type/constraint validation.
- Module: request translation, configuration rendering, scope checks, modeled
  errors and ownership behavior without changing the host.
- Integration: real isolated sysrepo, actual CLI and subscribers, persistence,
  missing subscribers, conflicts, migrations and controlled backend failures.
- System: disposable VM boot, both scopes, passwordless updates, persistence,
  interrupted deployment, rollback, desktop/Flatpak integration and power actions.

Nix build success does not prove activation or health. Reboot tests observe a
changed boot ID and restored services; shutdown tests observe clean guest exit
from outside. Unauthorized operations must leave the guest running. Bound all
waits; report unavailable evidence as unknown. Graphics/Wi-Fi/physical SSD boot
need separate hardware acceptance, not claims based on VM success.

## Implementation order

1. Root Flake, manager entries, fixed sysrepo/libyang and bootstrap data.
2. User repository, Foot configuration snapshot/build/apply, CLI and C subscriber.
3. System repository, root deployment service and passwordless VM system updates.
4. Persistence recovery, schema migration and managed rollback.
5. Flatpak Zen/OBS installation, managed regular-file delivery and observed state.
6. Remaining module migration and actual hardware acceptance.

## Upstream references

- [Sysrepo API, permissions, instances and datastores](https://github.com/sysrepo/sysrepo)
- [YANG 1.1](https://www.rfc-editor.org/rfc/rfc7950.html)
- [YANG JSON encoding](https://www.rfc-editor.org/rfc/rfc7951.html)
- [Standalone Home Manager](https://nix-community.github.io/home-manager/installation/standalone.html)
- [Flatpak command reference](https://docs.flatpak.org/en/latest/flatpak-command-reference.html)
- [Flatpak desktop integration](https://docs.flatpak.org/en/latest/desktop-integration.html)
- [Zen Linux installation](https://docs.zen-browser.app/guides/install-linux)
- [OBS Linux installation](https://obsproject.com/kb/linux-installation)
