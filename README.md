# Folio

**Model-driven NixOS configuration, with reviewed deployments and recoverable operations.**

Folio combines NixOS and standalone Home Manager with YANG models and sysrepo.
One CLI manages machine policy, personal preferences and application operations;
each capability owns its schema, implementation and lifecycle.

The design connects three distinct concerns: validated desired configuration,
immutable build inputs, and verified runtime effects. Saving a setting records
intent. A reviewed deployment builds and activates that intent. Status and
recovery records describe what actually happened.

## What makes Folio different

| Feature | Practical benefit |
| --- | --- |
| **Module-owned architecture** | Schemas, packages, commands, runtime and tests live with the capability they implement. Public contracts keep composition explicit. |
| **Typed, durable configuration** | YANG/libyang validate values and constraints. Optimistic commits detect concurrent edits; failed editor saves retain private drafts. |
| **Pure Nix evaluation** | Builds consume normalized, frozen configuration with source, model, tool and descriptor identities. Evaluation never queries live sysrepo. |
| **Coordinated system and user deployment** | One reviewed plan binds both targets, applies the system first and checks stale inputs before activation. |
| **Persistent operations and recovery** | Independent systemd workers survive client exit. Durable journals expose partial results, explicit resume and retained rollback. |
| **Shared appearance with visible inheritance** | System defaults, personal overrides and module settings resolve consistently; public preference origins remain inspectable. |
| **Explicit application ownership** | Native apps follow Nix generations. Flatpak apps use a separate recorded lifecycle, explicit adoption and data-preserving removal. |
| **Local desktop controls** | The browser panel uses module backends for networking, devices, software, settings and diagnostics, with no cloud service or external frontend assets. |

Folio currently targets `x86_64-linux`. Its desktop combines Niri, Everforest,
Maple Mono NF CN, Fcitx5/Rime, Foot and Zsh. A dedicated `folio` target supports the
existing USB installation; `portable` provides a disposable UEFI test environment.
The physical target is specific to that installation, rather than a general installer.

## Contents

- [Daily use](#daily-use)
- [Reviewed deployment](#reviewed-deployment)
- [Architecture and configuration](#architecture-and-configuration)
- [Module catalogue](#module-catalogue)
- [Desktop and developer environment](#desktop-and-developer-environment)
- [Applications](#applications)
- [Local web panel](#local-web-panel)
- [Hardware targets and virtual machines](#hardware-targets-and-virtual-machines)
- [Recovery and model upgrades](#recovery-and-model-upgrades)
- [Legacy migration reference](#legacy-migration-reference)
- [Development and verification](#development-and-verification)

## Daily use

These commands assume a provisioned installation with initialized repositories
and running manager subscribers. Run them as the provisioned desktop account.
System configuration also requires membership in `folio-operators`.

```sh
folio modules list
folio config show
folio config get /preferences/font-size
folio config set /preferences/font-size 18
folio config set /preferences/appearance '"light"'
folio config unset /preferences/font-size
folio doctor
folio panel
```

Field paths use `/preferences/FIELD` or `/modules/NAME/SETTING`; values are JSON.
`unset` removes an override so the applicable default can take effect. Use
`folio config edit` for a complete document, or `config export FILE` and
`config import FILE` for explicit review and transfer.

All supported configuration writes share validation, optimistic conflict checks
and durable persistence. `config import FILE --expected-digest DIGEST` protects
an external editor from overwriting newer changes. Failed editor saves retain a
private draft under `$XDG_STATE_HOME/folio/drafts/` and print its recovery command.
Identity fields cannot be changed through the single-field interface.

Saving configuration and enabling a module change desired state. Deploy those
changes explicitly:

```sh
folio plan --source /path/to/folio-nixos-config
folio build PLAN_ID
folio apply PLAN_ID
```

`folio doctor` is read-only. It inspects service availability, prerequisites,
configuration persistence, deployment drift and interrupted work, and reports
concrete next commands. `folio history` and `folio status` provide the underlying
records. History remains partially readable when one scope is unavailable.

### CLI conventions

| Interface | Contract |
| --- | --- |
| Unscoped `plan`, `build`, `apply`, `rollback` | Reviewed system/user workflow. |
| `--user` / `--system` | Explicit scoped configuration and deployment interfaces. |
| `--json` | One `{ status, data, error, taskId }` result envelope; progress goes to stderr. It changes formatting, not scope. |
| `--no-wait` | Return the durable task/workflow ID after acceptance. |
| `--request-id ID` | Repeated submissions with identical inputs reuse the recorded operation. |
| `status ID` | Inspect a task or reviewed workflow, including recorded progress and results. |
| `resume WORKFLOW_ID` | Explicitly retry interrupted reviewed work after checking earlier tasks. |

Exit codes are `0` success, `1` operation failure, `2` usage or validation error,
`3` unavailable service/evidence and `4` conflict. RPC acceptance does not establish
successful completion. Use each command's `--help` for module-specific arguments.

## Reviewed deployment

### Review once, deploy the reviewed inputs

`folio plan` captures one source snapshot for both scopes and evaluates the
resulting system and user artifacts. Its baseline is the last applied environment,
so both committed-but-unapplied changes and uncommitted source files are included.
The installed hardware target is retained; a conflicting source target is rejected.

The review shows affected modules, source paths, changed setting names, public
preference values and activation hints. Other configuration values remain hidden.
It identifies first deployments, disabled contributions and changes that need an
application restart, new login or kernel reboot. If neither target changed, no
plan is created. Otherwise confirmation and a comment retain the exact inputs.

```sh
folio plan --source "$PWD"
folio build PLAN_ID
folio apply PLAN_ID
folio history
folio rollback PLAN_ID
```

A plan binds desired configuration, source, models, tool versions, the system
descriptor, selected profiles and timeouts. Source capture includes the root
Flake/lock, modules and optional assets; it excludes runtime/output metadata and
rejects escaping symlinks. Evaluation uses immutable Nix-store bytes.

Builds do not publish applied state. Apply requires successful builds, checks both
scopes for stale inputs and unresolved effects, then activates system before user.
The user target is bound to the planned system descriptor, including inherited
preferences. Unchanged targets must still match their recorded configuration and
actual effects.

System and user activation are sequential. A partial failure records per-scope
results; a retry verifies and skips targets that are already current. Cancelling a
review removes provisional drafts. If confirmation stops between scopes, any
confirmed scoped plans remain inspectable and no combined plan is reported.

### Long-running work survives the terminal

Reviewed build/apply coordination and scoped deployment tasks run in independent
systemd services. Closing the CLI or restarting a subscriber does not cancel the
accepted work.

```sh
folio --no-wait build PLAN_ID
folio status WORKFLOW_ID
folio resume WORKFLOW_ID
```

Resume observes earlier tasks before retrying. Live tasks are awaited; unresolved
effects block further activation. New attempts recheck inputs and use fresh scoped
request IDs after previous tasks finish. Reboot preserves the records and requires
explicit resume; boot never automatically activates an old queued plan.

### Automation

```sh
result=$(folio --json plan --source "$PWD" --yes --comment "Update desktop settings") &&
plan_id=$(printf '%s\n' "$result" | jq -r '.data.planId // empty') &&
if [ -n "$plan_id" ]; then
  folio build "$plan_id" && folio apply "$plan_id"
fi
```

Non-interactive reviewed planning requires `--yes --comment TEXT`. The original
scoped creation interface remains available through
`folio --json --user plan --source DIRECTORY` or its system equivalent.

### Rollback boundaries

`folio rollback PLAN_ID` requires a successful apply, previews the complete target
state and asks for confirmation; `--yes` skips that prompt. It restores retained
artifacts, configuration and model identities, including unchanged scope baselines.
System restoration uses ordinary sudo authentication. Rollback adds history and
preserves later plans.

Personal application data and separately managed Flatpak revisions are outside
Nix deployment rollback. Mutable application settings in a writable checkout,
such as Pi's native configuration, follow their own version-control history.

## Architecture and configuration

### One source tree, explicit ownership

Only the repository root has a `flake.nix` and `flake.lock`. The root delegates
composition to [modules/manager/src/outputs.nix](modules/manager/src/outputs.nix).
There are no separate host/home trees or nested module Flakes.

```text
flake.nix / flake.lock
modules/
  <capability>/
    default.nix     public exports
    model/          YANG schemas and revision history
    src/            Nix packages and system/user adapters
    cli/            command adapters and help
    runtime/        subscribers, workers and operations
    tests/          capability-owned checks
```

Directories exist only when needed. Module presence does not enable it. The
manager explicitly collects the catalogue, checks command/model collisions and
selects the configured contributions. Modules consume public resources and
capabilities; they do not import another module's private implementation or call
its private runtime scripts.

The manager owns identity, module selection, shared preferences, configuration
commits and deployment records. Each capability owns its settings and actions.
Sysrepo provides modeled storage, validation and subscription dispatch. The
manager's deployment callback is not a generic router for arbitrary module actions.

### From desired data to observed effects

```text
CLI / panel
    │ validate + optimistic durable commit
    ▼
sysrepo desired configuration: running + startup
    │ capture + normalize + bind identities
    ▼
immutable source and folio-input.json
    │ pure Nix evaluation and reviewed build
    ▼
recorded artifacts → system activation → user activation
    │ verify actual effects
    ▼
status, task journals and retained recovery revisions
```

YANG 1.1 owns types, defaults, ranges, enumerations and structural constraints.
JSON follows RFC 7951. Module prerequisites are checked before configuration
persistence where applicable; planning checks system capabilities against the
bound descriptor. Missing prerequisites fail explicitly rather than enabling
another capability silently.

Frozen input format 1 records normalized configuration, SHA-256 configuration and
descriptor digests, model hashes, pinned tool versions, resolved preferences and
their origins. libyang emits defaults; canonicalization sorts object keys and
system-ordered identity lists while preserving user-ordered arrays and RFC 7951
scalar encodings. Nix rejects inconsistent input identities.

### Independent scopes, shared public defaults

| Scope | Persistent state | Runtime state | Responsibility |
| --- | --- | --- | --- |
| System | `/var/lib/folio/` | `/run/folio/` | Accounts, machine policy, prerequisites and system deployment. |
| User | `$XDG_STATE_HOME/folio/` | `$XDG_RUNTIME_DIR/folio/` | Personal preferences, user contributions and Home Manager deployment. |

User state defaults to `~/.local/state/folio`. Repository instances use distinct
shared-memory prefixes. Persistent roots contain `sysrepo/`, `configuration/`,
`deployments/` and `backups/`.

The system publishes its compiled identity, users, defaults and capabilities at
`/run/folio/public/system-descriptor.json`. User snapshots bind this root-owned,
read-only descriptor. Saving desired system settings does not republish them as
applied. User configuration cannot create accounts or redefine the system identity.

Preferences resolve from system defaults to personal overrides, with supported
module overrides last. Resolved values and origins enter the snapshot. A declared
capability is a prerequisite fact; it does not establish device or service health.

### Durable commits and privilege boundaries

The CLI edits a private document and commits with an expected digest. A scoped
lock serializes writers. Before/after journals record `prepared`, `accepted` and
`saved` phases using atomic replacement and durable flushes. Recovery restores a
prepared-only change or rolls an accepted change forward into running/startup
before consumers start. Configuration callbacks do not activate external effects.

`running` holds accepted desired data, `startup` holds persisted desired data and
`operational` reports observed state. Direct `sysrepocfg` edits are maintenance
operations outside the managed commit protocol. Existing desired configuration is
never replaced with defaults by an ordinary boot or rebuild.

System administration is granted at provisioning through `folio-operators` and
scoped repository permissions. Builds run as `folio-builder`; fixed root workers
activate the recorded NixOS closure. Ordinary managed updates need neither a
blanket passwordless sudo rule nor membership in Nix `trusted-users`. Offline
system maintenance requires root.

This is a local administrative boundary: an authorized operator's chosen source
is trusted administration input. It is not a hostile multi-user isolation design
or an implicit NETCONF/NACM policy. Requests cannot supply arbitrary executable
paths or shell payloads for privileged workers.

## Module catalogue

System and user selections are independent. The table describes available
contributions, rather than claiming every module is enabled by default.

| Module | System contribution | User contribution |
| --- | --- | --- |
| `manager` | Configuration and deployment service | CLI, configuration and deployment service |
| `sysrepo` | Repository initialization and models | Repository initialization and models |
| `system` | Boot, storage, accounts, locale, time, console, logging, zram and Nix | — |
| `network` | NetworkManager, DNS, firewall, SSH and optional Mihomo | — |
| `devices` | Hardware access, Bluetooth and power policy | Audio session, device controls and observations |
| `vm` | KVM access | Disposable VM lifecycle |
| `desktop` | Login session and portal prerequisites | Niri, Waybar, Mako, launcher, clipboard and screenshots |
| `appearance` | Console appearance where applicable | Fonts, cursor, GTK and shared appearance resources |
| `input` | — | Fcitx5/Rime and session integration |
| `terminal` | Shell registration | Foot, Zsh, tools, Yazi, Typst and Git/GitHub CLI |
| `emacs` | — | Emacs, Org and Org-roam |
| `agents` | — | Codex and Pi |
| `applications` | Flatpak infrastructure | Native applications and owned Flatpak lifecycle |
| `panel` | — | Local browser frontend package; no selectable system/user adapter |
| `isaac` | — | Optional Isaac Sim / Isaac Lab setup and inspection commands |

For modules with selectable adapters, disabling removes their managed contribution
on apply. Stored settings and personal application data are preserved.
Models and command adapters can be
available while the capability is disabled; availability does not imply activation.

### Public Nix contract

A module's `default.nix` receives `pkgs` and `lib`; the manager may also receive
the collected public command map. Optional exports include:

| Export | Purpose |
| --- | --- |
| `packages` | Named derivations, exported as `<module>-<component>`. |
| `checks` | Owned checks, exported as `<module>-<check>`. |
| `models` | System/user YANG paths, including the required import closure. |
| `commands` | Command roots with executable paths, supported scopes and optional help. |
| `requirements` | Per-scope prerequisites and system capabilities. |
| `impacts` | Public activation hints for deployment review. |
| `nixosModule` / `homeManagerModule` | Context-to-module constructors for each scope. |
| `migrations` / `subscribers` | Hash-bound schema transitions and registered consumers for paired maintenance. |

Adapters receive identity, resolved globals, their own settings and public
capabilities. They never query a mutable repository during evaluation. See
[the catalogue collector](modules/manager/src/catalogue.nix) and
[configuration composition](modules/manager/src/configuration.nix) for the exact
contract. Additional target-specific exports remain owned by their modules.

Public root outputs include `nixosConfigurations.portable`,
`nixosConfigurations.folio`, `homeConfigurations.folio`,
`packages.x86_64-linux.*`, `checks.x86_64-linux.*`, the development shell,
`lib.folio.targets` and `lib.folio.identities`. Standalone builds use bootstrap
defaults unless the source contains a prepared `folio-input.json`.

## Desktop and developer environment

### Consistent appearance and session integration

The desktop uses Niri, Waybar, Mako, Fuzzel, clipboard history and screenshots.
Everforest light/dark palettes, Maple Mono NF CN, a recolored GoogleDot cursor and
GTK resources share resolved preferences. Font and preference origins are recorded
in `~/.config/folio/appearance.json`.

GTK 3 uses adw-gtk3 with Folio colors. GTK 4/libadwaita retains its native stylesheet
and receives named colors and modern CSS variables. Open applications need a
restart to reload styles. Fuzzel's border follows the desktop border width; power
confirmation prompts share the launcher's appearance. The TTY greeter uses the
Everforest ANSI palette and a console font.

Folio's patched Niri provides a 300 ms focus-ring fade that respects global
animation settings. A generation update preserves the running compositor; log
out and back in to load a new binary. Applying greeter configuration does not
restart greetd during the current session.

Fcitx5/Rime Ice starts as a user service and seeds defaults only when absent.
Existing profiles, dictionaries and history remain intact. Initial dictionary
deployment must finish before Chinese composition is ready.

```sh
folio devices status
folio devices volume +5
folio devices mute
folio devices brightness 50
folio devices profile balanced
```

Device commands report actual observations and use native services. Missing
hardware or authorization returns unavailable. Bluetooth pairing is available
through Blueman. External-monitor DDC/CI control is not included.

### Terminal, documents and coding tools

`terminal` provides Foot and Zsh with Powerlevel10k, completion, suggestions and
highlighting. Independent switches control tools including bat, btop, eza, fd,
fzf, jq, ripgrep, zoxide, just, Typst and Yazi. Git/GitHub CLI settings live under
`folio-terminal:terminal.git`; configure the target user's own identity.
Changing the login shell requires the system account's explicit `login-shell`
selection in addition to shell package registration.

Yazi follows the shared palette. Run `yazi`, or `y` in Zsh to also change the
shell's directory on exit. Markdown uses `$EDITOR`; PDFs and images use desktop
associations. The applications module supplies Zathura and imv, controlled by
`applications.native.zathura` and `.imv`.

Emacs provides Org/Org-roam, backlinks, completion and Everforest preferences.
`C-c n f` finds notes, `C-c n b` shows backlinks and `C-c n h` opens the start page.
Notes default to `~/Documents/documents`; configure
`folio-emacs:emacs.notes-directory` to reuse another location. Personal additions
can live in the unmanaged `~/.config/folio/emacs/local.el`.

### Codex and Pi

The `agents` module independently selects Codex and Pi. Codex receives Zsh
completion and a Folio theme without rewriting personal configuration. An optional
PTY color adapter maps fixed accents to the selected palette; non-terminal
commands run directly. Authentication, sessions and mutable configuration remain
application-owned. Review the compatibility adapter when updating the pinned CLI.

Pi uses its native settings and resources under
[modules/agents/src/pi/config](modules/agents/src/pi/config), rather than a second
YANG representation. Set `agents.pi.config-directory` to an absolute writable
checkout to edit those resources in place. The `folio` target defaults to this
repository's local checkout; existing desired data must select that path explicitly.
The portable target uses an immutable snapshot.

The launcher exposes the configuration at `~/.config/folio/pi` and keeps private
agent state under `$XDG_STATE_HOME/folio/pi`. Settings, model/resource declarations
and local packages may be tracked in the checkout; authentication, sessions,
project trust, downloaded packages and caches stay outside it. Pre-existing
personal files are not silently replaced. A missing configured checkout fails
explicitly.

With a writable checkout, `/settings`, model selection and `pi install` can change
tracked native configuration. Review those changes with Git and use `/reload`
after manual edits. Relative local packages can use `./packages/my-tools` in
`settings.json`. Writable checkout changes are live application settings and are
not undone by generation rollback. `FOLIO_PI_CONFIG_DIR` selects configuration
for one invocation; `PI_CODING_AGENT_DIR` explicitly selects a private agent root.
The launcher provides `wl-clipboard` for Wayland text and image clipboard access.

Former standalone Git/Codex modules and dsh are retained only as supported schema
migration history. Hash-bound transforms preserve applicable selections and
preferences; they do not migrate credentials or conversations. Conflicting old/new
settings fail explicitly. Update the root lock and rebuild to update packaged clients.

### Isaac Sim / Isaac Lab

The optional `isaac` user module installs commands, then leaves large environment
setup explicit:

```sh
folio modules enable isaac
# Plan, build and apply the module selection first.
isaac-doctor --stage preflight
isaac-setup
isaac-status
isaac-lab --help
```

Versions and content identities are pinned in
[modules/isaac/src/versions.json](modules/isaac/src/versions.json). Downloads,
environments and experiment outputs stay in user directories. The runtime check
covers the command contract; simulator, rendering and training require actual
GPU acceptance. The base desktop does not install a CUDA SDK.

### Network and machine policy

The system `network` module supplies NetworkManager, connection DNS and a
default-deny inbound firewall. SSH and Mihomo are opt-in. SSH uses public-key
authentication; its firewall port opens only when explicitly selected.

```sh
folio --system network status
folio --system network connect CONNECTION_UUID INTERFACE
folio --system network disconnect INTERFACE
folio --system network proxy-mode rule
folio --system network proxy-select DIRECT
```

CLI connection commands use existing NetworkManager profiles. Profile credentials
remain outside Folio desired data. Proxy commands use the private Mihomo Unix
controller and report actual observations; live mode/node selection is runtime
state, separate from persisted policy. Disabled services and missing profiles or
nodes return unavailable.

An optional `proxy.provider-file` references target-local YAML under `/run` or
`/var/lib`, loaded as a systemd runtime credential. Evaluation and builds never
read its contents. The proxy listener binds loopback; TUN is separately opt-in.
Do not put provider secrets in tracked source or frozen configuration.

The `system` module models locale, time synchronization, console policy, bounded
journal storage, zram and Nix settings. Physical storage requires explicit stable
root/EFI paths and account policy; no adapter partitions disks.

## Applications

### Native packages and Flatpak have distinct lifecycles

Native Zen Beta/OBS and document viewers are selected through
`folio-applications:applications.native` and deployed with the user generation.
The model rejects selecting both native and Flatpak delivery for Zen or OBS.
Native package rollback follows Home Manager; personal profiles remain intact.

The panel's software catalogue and `folio apps` share one applications backend.
Supported Flathub IDs and branches use x86_64 refs; Zen and OBS also have the
`zen` and `obs` aliases with specialized settings and permissions. Generic apps
retain upstream sandbox permissions.

```sh
folio apps init
folio apps refresh
folio apps install org.example.App --ref app/org.example.App/x86_64/stable
folio apps adopt org.example.App --ref app/org.example.App/x86_64/stable
folio apps remove org.example.App
folio apps list
```

The example ID is a placeholder; use an actual Flathub app/ref. `init` explicitly
initializes the verified official Flathub remote. Install/adopt persist desired
selection before submitting a durable worker. A failed installation leaves
visible desired/actual drift.

The catalogue distinguishes **Managed by Folio**, **User installed** and
**System provided**. Configuration selection alone does not establish ownership.
An existing user installation requires explicit adoption before modification;
system applications are read-only in the catalogue. Removal persists deselection
and preserves personal data. Unrelated applications and overrides are left alone.

### Recorded transactions, explicit updates

```sh
folio apps prepare all
folio apps install all --offline
folio apps update zen
folio apps reconcile zen --offline
folio apps status TASK_ID
folio apps resume TASK_ID
folio apps rollback REVISION_ID all --offline
```

Preparation downloads and records resolved app, runtime and extension commits
without activating them. Reconcile preserves an already resolved commit;
explicit update resolves a new one. Pinned policy requires the requested commit.
No timer silently updates managed applications, and no Flatpak operation occurs
during Nix evaluation or derivation builds.

Offline deployment requires retained plans and matching cached content. If refs
or commits no longer match, the operation fails before deploying different bytes.
Historical rollback depends on retained content; version records are not an
indefinite archive. Shared runtimes are neither automatically pruned nor downgraded.

Mutations serialize and journal before/after state per application. There is no
atomic transaction across all apps or between Flatpak and Home Manager. Completed
results remain visible after failure; explicit resume checks stale configuration
and unresolved effects. The panel reads these same journals after a restart.

### Managed configuration preserves application state

User activation publishes a rooted immutable file manifest. The applications
worker materializes supported Flatpak settings as regular files through atomic
replacement, with content hashes and unique first-adoption backups. It rejects
path traversal, unexpected symlinks and conflicting ownership. `--adopt-files`
explicitly adopts supported existing files; unexpected later edits require
resolution.

For Zen, select an existing profile through `zen-profile` before reconciliation.
Missing profiles report `configuration-pending`; stale manifests require a new
user deployment. Folio manages supported preferences and owned CSS, preserving
`prefs.js`, databases, logins and sessions. Required restarts are reported without
killing the browser. OBS scenes, accounts, recording profiles and mutable settings
remain application-owned; full Qt appearance parity is not claimed.

Native Zen can target an existing directory under `~/.config/zen/` through
`applications.native.zen-profile`. Its preferences and owned CSS use the same
renderer, with conflicts rather than silent overwrites. The pinned native package
opens tabs as separate normal windows for Niri, including restored sessions.
Fully quit and reopen Zen after changing the package or browser integration.

## Local web panel

Run `folio panel` as the desktop user, or launch **Folio Panel**. To try a frontend
build directly:

```sh
nix build --out-link modules/panel/result .#folio
./modules/panel/result/bin/folio panel
```

| Page | Actions and observations |
| --- | --- |
| Wi-Fi | Scan, connect to saved/new/hidden personal networks, disconnect and manage profiles. Enterprise/legacy authentication is unavailable. |
| Proxy | Switch Direct/Rule/Global, choose nodes and run bounded endpoint tests. |
| Display & Audio | Default output, volume, mute and supported backlight controls. |
| Device | CPU, memory, graphics, displays, interfaces, uptime and available batteries. |
| Software | Flathub search, explicit ownership/adoption, install/remove and durable task progress. |
| Settings | Public appearance preferences, inheritance/reset and conflict-safe draft saving. |
| Diagnostics | Read-only doctor findings and suggested next commands. |

The responsive interface uses Folio's colors and fonts. Unsaved settings survive
background refresh; a stale save preserves the draft and reports a conflict.
Settings save desired configuration; deployment remains an explicit CLI workflow.
Runtime network/device controls act immediately and are outside generation rollback.

The standard-library Python server binds only `127.0.0.1`, uses a random API session
token and validates host/origin. The launch fragment is removed after the browser
stores its token for the tab. A private runtime record lets later launches reuse
the service; launching a newer installed frontend replaces an older server.
There are no external assets or frontend build dependencies.

Native NetworkManager/PipeWire/backlight permissions and system operator policy
still apply. Wi-Fi credentials are delivered to libnm on stdin and saved by
NetworkManager outside Folio configuration. The panel does not need sudo.

## Hardware targets and virtual machines

| Target | Intended use |
| --- | --- |
| `folio` | Existing migrated USB installation shared between the supported laptop and desktop. |
| `portable` | Disposable x86_64 UEFI guest for development and acceptance. |

```sh
nix eval --json .#lib.folio.targets
nix build --no-link .#nixosConfigurations.folio.config.system.build.toplevel
nix build --no-link .#nixosConfigurations.portable.config.system.build.toplevel
```

An ordinary checkout defaults to `portable`. Installed bootstrap `target.json`
and frozen `folio-target.json` retain hardware selection across future plans.
Within a frozen source, `nixosConfigurations.portable` is the manager's stable
entry for the selected target. The environment/account identity remains separate
from the hardware target. Evaluation never autodetects the host.

### Existing USB installation

The `folio` target supports the Lenovo Legion Y7000 IRX9 (i7-13650HX, RTX 4060)
and MSI MAG B650M MORTAR WIFI (Ryzen 7 9700X, RTX 3090 and AMD integrated graphics).
It supplies Intel/AMD microcode, i915/amdgpu, firmware/Mesa and one stable NVIDIA
open-module driver with DRM modesetting. PCI matching selects drivers; Niri has
no fixed PRIME addresses or DRM card numbering.

Storage uses the inspected USB root/EFI UUIDs and Btrfs `root`, `home` and `nix`
subvolumes. Internal disks are not configured or partitioned. The boot menu is
visible for three seconds and retains up to ten generations; EFI variable writes
are disabled. Secure Boot enrollment/signing is not provided. Shut down normally
before moving the disk between machines; moving it alone requires no rebuild.

Storage/boot policy lives in [modules/system/src/folio.nix](modules/system/src/folio.nix);
CPU/GPU policy lives in [modules/devices/src/folio.nix](modules/devices/src/folio.nix).
This target assumes the migrated account and runtime state already exist.
An unrelated physical installation requires its own inspected device paths,
account policy and hardware acceptance. Retired laptop/desktop target names need
an explicit transition; ordinary planning does not silently rename hardware identity.

### Disposable UEFI guests

```sh
image=$(nix build --no-link --print-out-paths .#vm-image)
"$image/bin/run-folio-vm" portable
```

The fixture includes immutable source at `/etc/folio/source`, locked inputs,
labeled disposable disks and the prototype `folio` password `kl;'`. That password
belongs to the guest fixture; the physical target preserves its existing password
and disables prototype credentials.

The `vm` user contribution provides `folio vm build JOB_ID IMMUTABLE_SOURCE`,
`start`, `stop`, `status` and `cleanup`. System provisioning supplies KVM access;
start checks actual device access. The image launcher also works before a Folio
user service has been installed; `folio-vm-tool status|stop|cleanup portable`
controls that bootstrap job from the `vm-tools` package.

Jobs keep private qcow2 overlays, EFI variables and QMP sockets under
`$XDG_STATE_HOME/folio/vm/jobs/`, using QEMU user-mode networking. Stop requests ACPI
shutdown and waits; cleanup refuses active jobs and archives logs before removing
disposable disks and roots. No host disk passthrough or network bridge is required.

## Recovery and model upgrades

### Diagnose before changing recovery state

```sh
folio doctor
folio status
folio status TASK_OR_WORKFLOW_ID
folio history
```

Subscriber recovery compares actual effects with recorded before/after state.
It can finish publication of a verified activation or restore a profile selection
when effects still match the earlier closure. It never reruns activation merely
to infer success. Ambiguous effects remain visible as recovery-required and block
new applies.

Plans, builds, tasks, revisions and GC roots live under scoped `deployments/`;
reviewed coordination records live under the user's `deployments/workflows/`.
Preserve those records and backups during recovery. `folio cleanup` previews
eligible records; `folio cleanup --apply` removes only selected records and known
roots. It excludes active workers, retained current/previous revisions and
backup/recovery references. It neither runs global Nix GC nor prunes repository
backups or application data.

### Model upgrades

Ordinary deployment requires the source's scoped model/tool identities to match
the installed repository. A new YANG revision therefore needs explicit paired
maintenance before ordinary planning. A generic frozen-input evaluation failure
on an older manager can be a model mismatch; current planning reports that case
explicitly. The applications catalogue requires model revision `2026-10-26`.

Maintenance upgrades the schema, normalized data and matching closure together.
Module-owned transforms are bound to exact revision hashes; changing a schema
without advancing its revision is rejected. The candidate must match the isolated
migration result and all model/tool/configuration identities before installation.
A source file containing arbitrary desired JSON is not sufficient.

```text
folio-manager-maintain SCOPE BOOTSTRAP snapshot ID
folio-manager-maintain SCOPE BOOTSTRAP upgrade ID FROZEN_SOURCE
folio-manager-maintain SCOPE BOOTSTRAP restore ID
```

`BOOTSTRAP` is the currently selected generation's immutable bootstrap.
`FROZEN_SOURCE` must be an immutable store source with candidate models and a
validated `folio-input.json` matching the migrated configuration and descriptor.
`folio-prepare-input` normalizes candidate data and binds identities; the maintenance
coordinator independently verifies it against the migration result.

For example, inspect and snapshot the selected user pair:

```sh
artifact=$(readlink -e "${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager")
bootstrap=$(jq -r .bootstrap "$artifact/folio-home.json")
folio-manager-maintain user "$bootstrap" snapshot before-upgrade
# To restore that same retained pair:
folio-manager-maintain user "$bootstrap" restore before-upgrade
```

Use a new transaction ID for an upgrade. User maintenance runs as the provisioned
account with its real HOME/runtime directory; system maintenance requires root.
Each scope upgrades separately. A system upgrade does not migrate the user
repository, and a fallback subscriber defers when its model identity differs.

The coordinator builds before stopping consumers, refuses active or unresolved
jobs, then stops registered consumers, locks the repository, snapshots the old
pair and validates an isolated candidate. Installation activates and verifies
the paired closure before publishing success. Failure attempts restoration;
failed restoration retains the barrier and journal for explicit `restore ID`.
Never hot-replace schemas while callbacks or deployments are active.

Backups live under `backups/repositories/ID/`, including repositories, normalized
data, identities, journals and roots for both pairs. Do not delete those roots or
call repository primitive `finalize` to bypass verification.

Scoped `folio --user|--system rollback RETAINED_ID [--rebuild]` supports advanced
retained revision recovery. An explicit compatibility rebuild must still prove
supported worker protocol and retained model/tool identities. First adoption of a
Sylphy Home Manager profile uses the separate `adopt` maintenance entry point.

## Legacy migration reference

These operations preserve recovery access for the existing Sylphy installation.
They are separate from daily configuration and model upgrades.

### Existing Sylphy account and home migration

The `system-migration`, `system-keyring` and `system-retirement` packages retain
specialized migration and recovery tools for the existing USB installation.
These are advanced operations for an inspected legacy account, separate from
ordinary deployment. The current `folio` target assumes the account already
exists; its normal configuration no longer enables the migration adapter.

Build `system-migration` and the target system, then run the immutable migration
tool with local sudo authentication:

```sh
tool=$(nix build --no-link --print-out-paths .#system-migration)
system=$(nix build --no-link --print-out-paths .#nixosConfigurations.folio.config.system.build.toplevel)
sudo "$tool/bin/folio-migrate-account" launch "$system"
```

The root worker closes the session after 20 seconds, discovers and stops the
existing login services (including tty autologin), stops UID 1000 writers,
creates a read-only Btrfs home snapshot, pins the old system and legacy store
references, renames the account while keeping UID/GID/password, atomically moves
the home, and keeps `/home/sylphy` as an alias to `/home/folio`. It compares broken
links and preserved application files before selecting the new boot generation.
An error during cutover attempts to restore only the identity or boot stages that
started, then restarts the recorded old login services.
State, account/EFI/network backups and logs stay root-private under
`/var/lib/folio-migration`; the home snapshot is under
`/home/.folio-migration-backups`. No private file bytes are part of builds.
Account backups require passwd/shadow/group; gshadow is optional on NixOS and
its absence is recorded. Preparation retries retain existing protection roots.
The migration tool declares its own systemd-service dependencies and checks for
immediate worker failure after submission. If a worker stopped before quiescing,
`resume SYSTEM` accepts only a queued or failed journal with the original account/home and
running system, complete preparation backups, no snapshot or new proxy state,
and no running worker. It retains backups and pins the updated tool/system before
restarting. A root-owned `/home/folio` alias pointing to the unchanged source home
from an earlier rollback is removed only after those checks pass. Other interrupted
phases require inspection rather than blind retry.

The original native browser profile, encrypted keyring, SSH/GPG, Codex account
directories and Home Manager generation are kept. The transition does not apply
a new user generation or replace the native browser with a clean Flatpak profile.
Legacy `/etc/sylphy` descriptors are restored as regular files after `/etc/static`
changes. Verify existing sessions before separately adopting new user/app profiles.

First login is `folio` with the existing password. Run
`folio-migrate-account finish` from an interactive Folio terminal to change the
password; PAM attempts to update the existing login keyring as well. If it remains
locked with its earlier password, use Seahorse to change that keyring's password;
never delete/reinitialize it to bypass the prompt. A successful password change
does not by itself establish keyring or remote application-session health.

If the login keyring still uses its previous password, run
`nix run .#system-keyring` from the repository in an interactive Folio desktop
terminal, without sudo. It saves a private copy of the encrypted keyrings, reads
the previous password and new password twice with terminal echo disabled, and
changes the existing login keyring through GNOME Keyring's platform-specific
D-Bus interface. No GUI is required. Use the current login password as the new
keyring password; this command does not change the system password. Empty or
mismatched new passwords are rejected. The helper reports success only after the
daemon accepts the change, and does not delete credentials. Log out and in again
and check existing application sessions afterward.

`sudo folio-migrate-account rollback` closes the session, reverses the identity/home
rename and selects the retained old system for reboot. It keeps current file
contents and the current password. Simply booting an old generation does not
reverse a persistent account rename. A complete recovery also has the private
account/boot backups and pre-migration home snapshot; they are not automatically
restored over newer personal data. Preserve aliases and GC roots until verified.

Retiring `/home/sylphy` requires a Home Manager generation built for `folio` at
`/home/folio`, while retaining existing application profiles. Build
`system-retirement` and a `folio` system without the old tmpfiles rule,
then run `sudo TOOL/bin/folio-retire-home launch SYSTEM HOME_GENERATION` locally.
It waits 20 seconds, stops the login session, snapshots the home filesystem,
updates live text/link references, SQLite TEXT fields and Mozilla compressed
sessions, merges duplicate Codex project records, and activates the corrected
Home Manager generation. It selects the new boot system, unlinks only the checked
compatibility symlink, and reboots. Passwords, keyrings and historical transcripts
are retained. Failure restores the compatibility link and old boot selection;
the snapshot is retained rather than overwriting newer files automatically.
The separate root-private journal is `/var/lib/folio-home-retirement`; inspect it
before retrying an interrupted operation. Old Home Manager generations require
the old alias when deliberately selected again.

The path migration fixture is `modules/system/tests/home-retirement.py`, invoked
with the packaged Python environment and `modules/system/runtime/retire-home-paths.py`.
It checks immutable source preservation, absolute links, SQLite data, compressed
sessions and duplicate project merging. These fixtures and system builds do not
establish that physical retirement has completed.

The bounded `checks.x86_64-linux.account-migration` guest checks real account
rename/rollback, password hash, UID/GID/mode/inode preservation, absolute/store
links, opaque application data, tty autologin shutdown/recovery, and legacy
descriptor recovery. It does not prove
physical boot or actual account/keyring password synchronization on the laptop.

### Legacy system compatibility cleanup

After account and home-path migration, the `folio` target uses hostname `folio`,
retains the existing local password, and provisions the keyring through the normal
desktop module. It no longer selects the account migration adapter, restores
`/etc/sylphy`, or creates the old Mihomo service/runtime aliases. Private proxy
rules and node selection remain in `/var/lib/folio-mihomo`; provision the provider
at `/var/lib/folio-mihomo-private/provider.yaml` outside the Nix store.

Build `system-legacy-cleanup` and invoke its `folio-retire-legacy apply STORE_SOURCE`
with sudo and a reviewed immutable source for the `folio` target. The worker
copies and verifies the existing credential, saves configuration and recovery
records, then performs a normal system plan/build/apply. Only after successful
activation and health checks does it archive `/etc/sylphy` and the old proxy
directories under `/var/lib/folio/backups/legacy-*`. It does not reboot or stop
the desktop. Login-service configuration changes are deferred rather than
restarting greetd during activation.

If activation succeeded but final checks or archiving were interrupted, use
`folio-retire-legacy resume BACKUP`. It verifies the recorded plan, active artifact
and unchanged desired data, then continues without another build/apply. Credential
paths are read through systemd's structured D-Bus property rather than formatted
`systemctl show` output. The transient hostname is synchronized with the checked
static hostname. Failures record their step in the private journal.

Before selecting an older generation that requires the legacy paths, run
`folio-retire-legacy restore-files BACKUP` with sudo, then perform its explicit
system rollback. Migration journals, snapshots and old source checkouts are
recovery/history artifacts and are not deleted by this cleanup.

`checks.x86_64-linux.legacy-retirement` checks the evaluated physical target and
unprivileged refusal. `legacy-retirement-files` exercises real root-owned file
copy/archive/restore in a disposable guest, with mocked deployment responses and
real systemd credential properties and transient hostname changes. It also checks
resume after interrupted finalization and rejection of deployment drift. It does
not establish successful system activation on the actual host.

## Development and verification

### Isolated development

Use the root development shell and temporary XDG paths for repository experiments:

```sh
nix develop
bootstrap=$(nix build --no-link --print-out-paths .#manager-bootstrap)
scratch=$(mktemp -d)
export XDG_STATE_HOME="$scratch/state" XDG_RUNTIME_DIR="$scratch/run"
mkdir -p "$XDG_RUNTIME_DIR"
folio-repository user init "$bootstrap/models/user" "$bootstrap/user.json"
folio-repository user cfg --export --module folio-environment --format json --defaults report-all
folio-manager-subscriber user "$bootstrap"
```

Run the subscriber in a dedicated shell. A second shell must use the same scratch
XDG paths before submitting configuration commands. Stop the subscriber when
finished. This example initializes only a disposable user instance.

`folio-repository init` preserves existing startup data and rejects model/library
identity changes. Its `ctl` and `cfg` interfaces are maintenance wrappers, not a
replacement for managed durable configuration writes.

Implementation, CLI help/messages and commit messages use English. Keep product
documentation in this README and behavioral checks under the owning module.
Reuse public resources explicitly; add runtime operations only for concrete public
actions. Run checks appropriate to the changed contract rather than the entire
suite after every small edit.

### Verification map

Self-contained checks are exported by their owning module as
`<module>-<check>`. Cross-module and deployment fixtures are composed in
[modules/manager/tests/default.nix](modules/manager/tests/default.nix), keeping
test wiring out of production output composition. Existing short check names,
including `cli-workflow`, `panel`, `appearance` and `account-migration`, remain
aliases for the same derivations.

The shared `tools` check exercises the generated developer environment across
terminal, agents and Emacs; its fixture lives with manager integration tests.
Capability-specific behavior remains under each owning module's `tests/`.

Python unit tests use `test_*.py`; executable acceptance scripts retain scenario
names. Process doubles live in `tests/fixtures/` and do not activate the host.
Isaac's installed GPU validation commands live in `runtime/validation/`, separately
from the isolated regression tests that exercise them.

| Check | Evidence covered |
| --- | --- |
| `catalogue`, `foundation` | Public composition, schemas, normalization and repository foundations. |
| `configuration`, `cli-workflow` | Real sysrepo commits, stale edits, private drafts, reviewed planning and durable workflow behavior. |
| `user-deployment`, `system-scope`, `system-deployment` | Profile effects, access policy, cross-scope deployment, retained rollback and guest power observation. |
| `agents-migration` | Paired schema/data upgrade and restore with hash-bound transitions. |
| `applications-store`, `applications-native`, `applications` | Catalogue ownership, native delivery and application lifecycle. |
| `panel`, `panel-browser`, `panel-network` | HTTP boundaries, Chromium interactions/layout and native network integration. |
| `appearance`, `desktop-focus-fade`, `desktop` | GTK resources, sampled focus-ring behavior and session integration. |
| `tools`, `tools-deployment`, `agents`, `agents-colors` | Generated tools, user deployment, coding-client integration and color adaptation. |
| `network-proxy`, `isaac-runtime` | Module-owned proxy and optional simulation command contracts. |
| `account-migration`, `legacy-retirement`, `legacy-retirement-files` | Legacy account and compatibility recovery paths. |

For a focused configuration/UI change:

```sh
nix build --no-link \
  .#checks.x86_64-linux.configuration \
  .#checks.x86_64-linux.cli-workflow \
  .#checks.x86_64-linux.panel \
  .#checks.x86_64-linux.panel-browser

git diff --check
```

Checks span static validation, module behavior, isolated real-sysrepo integration
and disposable complete-system guests. The usability acceptance run on 2026-10-22
passed configuration, workflow, panel/browser, store, migration and UEFI deployment
gates, including detached coordination, rollback and observed reboot/shutdown.

The integrated release fixture requires an isolated public Flatpak cache and
matching retained application plans. Supply existing store paths explicitly:

```sh
nix build --no-link --impure --expr '
  let f = builtins.getFlake (toString ./.);
  in f.checks.x86_64-linux.integrated-release.override {
    cache = builtins.storePath (builtins.getEnv "FOLIO_TEST_CACHE");
    plans = builtins.storePath (builtins.getEnv "FOLIO_TEST_PLANS");
  }'
```

The fixture fails before boot when either input is missing and never substitutes
host application data. The complete guest gate has covered both scopes,
interrupted recovery, cached apps, actual Chinese input, OBS portal/PipeWire
frames and externally observed power actions.

### Evidence boundaries

A successful build establishes evaluation/buildability, not activation or hardware
health. Guest results do not establish physical GPU acceleration, suspend, Wi-Fi,
backlight, Bluetooth, storage boot or encoder performance on both target machines.
Generic Flatpak selection has schema-persistence and backend-protocol coverage;
the usability gate did not download and install arbitrary live Flathub apps.
Isaac simulator/rendering/training stages require separate GPU evidence.

Power RPCs report durable acceptance. Completion requires an external observation
such as a changed guest boot ID or clean QEMU exit. Native service declarations
and configured capabilities likewise remain separate from observed health.

## Upstream references

- [Sysrepo](https://github.com/sysrepo/sysrepo)
- [YANG 1.1 — RFC 7950](https://www.rfc-editor.org/rfc/rfc7950.html)
- [YANG JSON encoding — RFC 7951](https://www.rfc-editor.org/rfc/rfc7951.html)
- [Standalone Home Manager](https://nix-community.github.io/home-manager/installation/standalone.html)
- [Flatpak command reference](https://docs.flatpak.org/en/latest/flatpak-command-reference.html)
- [Flatpak desktop integration](https://docs.flatpak.org/en/latest/desktop-integration.html)
- [NVIDIA open GPU kernel modules](https://github.com/NVIDIA/open-gpu-kernel-modules)
- [Yazi configuration](https://yazi-rs.github.io/docs/configuration/yazi/)
- [Zen Linux installation](https://docs.zen-browser.app/guides/install-linux)
- [OBS Linux installation](https://obsproject.com/kb/linux-installation)
