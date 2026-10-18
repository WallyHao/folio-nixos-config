# Project Structure

Planned layout. [README.md](README.md) defines the implementation baseline;
directories below are created as their implementation is added.

```text
folio-nixos-config/
├── README.md
├── STRUCTURE.md
├── flake.nix
├── flake.lock
├── assets/
├── modules/
│   ├── manager/
│   ├── sysrepo/
│   ├── system/
│   ├── network/
│   ├── devices/
│   ├── vm/
│   ├── desktop/
│   ├── appearance/
│   ├── input/
│   ├── terminal/
│   ├── git/
│   ├── emacs/
│   ├── codex/
│   └── applications/
└── docs/
```

- `README.md`: project introduction and usage.
- `STRUCTURE.md`: file structure design.
- `flake.nix`: dependency declarations and a thin entry to the manager-owned
  output composition.
- `flake.lock`: pinned Flake dependencies.
- `assets/`: logos and other image assets.
- `modules/`: module implementations, including the manager.
- `modules/manager/`: global models, CLI translation, and its own build and
  deployment operations.
  The root Flake explicitly loads it so that building the manager does not
  require a running manager or datastore.
- `docs/`: reserved for documentation; initially empty.

## Module inventory

| Module | Scope |
| --- | --- |
| `manager` | Global data, CLI composition, configuration snapshots, builds, deployment, and recovery. |
| `sysrepo` | sysrepo/libyang integration, repository initialization, model installation, and access permissions. |
| `system` | Boot, storage, account configuration, locale, time synchronization, TTY, journald, zram, and Nix settings. |
| `network` | NetworkManager, Mihomo, DNS, firewall, and OpenSSH. |
| `devices` | Audio, Bluetooth, brightness, power policy, and hardware information. |
| `vm` | QEMU/KVM, OVMF UEFI guests, build/launch entry points, and disposable VM lifecycle for testing. |
| `desktop` | Niri, Waybar, Mako, launcher, clipboard history, screenshots, and keyboard shortcuts. |
| `appearance` | Font installation, cursor, GTK appearance, and shared theme resources. |
| `input` | Fcitx5, Rime, and input method configuration. |
| `terminal` | Foot, Zsh, prompt, Typst, and terminal utilities. |
| `git` | Git, GitHub CLI, and their configuration. |
| `emacs` | Primary editing environment, Org, and Org-roam. |
| `codex` | Codex installation and configuration. |
| `applications` | Zen Browser and its configuration, OBS Studio, and other applications. |

All software installed through Flatpak belongs to `applications`, including its
installation declarations, configuration integration, update operations, and
status reporting. Other modules do not own Flatpak-installed applications.
`applications` may also contain software installed through Nix.

Terminal utilities include bat, btop, eza, fd, fzf, jq, ripgrep, zoxide, unzip,
unrar, chsrc, just, and Typst. These are internal components rather than separate modules.
Typst's Nix implementation belongs at `modules/terminal/src/typst.nix`.
Aggregated components can be enabled individually without creating new modules.

Modules own their implementation and application-specific models. They do not
import other modules' private code. Cross-module interaction uses public modeled
interfaces through sysrepo; the manager does not dispatch those operations.

### Prototype choices

- Account name: `folio`; home directory: `/home/folio`.
- Prototype account password: `kl;'` (four characters).
- Emacs is the sole selected editor; Neovim is excluded.
- Panel is excluded, including the existing Sylphy Panel implementation.
  Device capabilities remain in `devices`; a replacement UI may be designed later.
- Reuse Sylphy's current appearance and applicable desktop/application preferences,
  adapting account-specific paths to `folio` and omitting excluded components.
- Appearance baseline: Everforest dark/hard, Maple Mono NF CN, themed GoogleDot
  cursor, and Sylphy's existing typography and window geometry.

Global identity and shared appearance preferences belong to the manager's model.
The system module applies account configuration; appearance installs shared
resources; application modules render their own configuration from those preferences.

## Flake and module entries

The root `flake.nix` declares inputs and delegates output construction to
`modules/manager/src/outputs.nix`. This is an ordinary Nix file, not another
Flake. There is one root Flake and one Flake lock.

Each module exposes its implementation through `default.nix`. Optional outputs
are `packages`, scoped `models`, scoped `commands`, `nixosModule`, and
`homeManagerModule`; absent capabilities are empty or null. The last two are
context-to-module constructors. The precise interface is in README.md.
System and user configuration/deployment remain distinct scopes within unified
environment management, without top-level host/home directories.

The manager's `src/outputs.nix` explicitly loads module entries and collects
their outputs. It owns build-time composition, not runtime operation dispatch.
Its bootstrap entry and the manager's own `default.nix` must not load one
another recursively. Building the manager does not require a running datastore.

Model and command collection stay in `outputs.nix` until their complexity
justifies separate files.

## Manager

```text
modules/manager/
├── README.md
├── default.nix
├── model/
│   ├── folio-environment.yang
│   └── folio-deployment.yang
├── src/
│   ├── outputs.nix
│   ├── package.nix
│   ├── configuration.nix
│   ├── system.nix
│   └── user.nix
├── cli/
│   └── ...
├── runtime/
│   ├── main
│   ├── callbacks/
│   ├── operations/
│   ├── snapshot/
│   └── journal/
└── tests/
```

- `default.nix`: public module entry, exposing packages, models, and Nix
  integration to the root Flake.
- `model/`: global environment data and the manager's own deployment operations,
  task state, and results. Application models belong to their respective modules.
- `src/outputs.nix`: constructs root Flake outputs, loads module entries, and
  collects their models, commands, packages, and adapters.
- `src/package.nix`: builds the manager executables.
- `src/configuration.nix`: composes Nix configuration from frozen environment
  data and module entries supplied by the root Flake.
- `src/system.nix`: root deployment service, system repository integration,
  prototype operator authorization, permissions, and service ordering.
- `src/user.nix`: CLI installation and the account's user deployment service.
- `cli/`: Bash client using jq and sysrepocfg; detailed below.
- `runtime/`: subscribes to and executes the manager's own operations; detailed
  below. Other modules subscribe to and execute their own operations through
  sysrepo.
- `runtime/snapshot/`: freezes configuration and records model, source, and dependency
  identities for reproducible build inputs.
- `runtime/journal/`: persists deployment progress and recovery information.
- `tests/`: reserved for all manager tests, including CLI and full-system tests;
  initially empty. Acceptance levels are defined in README.md; test files and
  tooling are introduced with implementation.

`src/` contains Nix implementation; `cli/` contains the client; `runtime/`
contains the manager's operation implementation. Subscribers use C with
libsysrepo/libyang; command-oriented operations may use Shell.
The manager does not dispatch other modules' operations. The root `docs/`
directory remains empty.

## CLI

```text
modules/manager/cli/
├── bin/
│   └── folio.sh
├── lib/
│   ├── arguments.sh
│   ├── commands.sh
│   ├── transport.sh
│   ├── output.sh
│   └── help.sh
└── commands/
    ├── build/
    │   ├── command.sh
    │   ├── request.jq
    │   └── help.txt
    ├── deploy/
    │   ├── command.sh
    │   ├── request.jq
    │   └── help.txt
    └── rollback/
        ├── command.sh
        ├── request.jq
        └── help.txt
```

- `bin/folio.sh`: executable entry; loads shared functions, parses global options,
  and invokes the selected command adapter.
- `lib/arguments.sh`: global options and reusable argument checks. Individual
  commands parse their own arguments.
- `lib/commands.sh`: looks up adapters in the command table assembled by Nix.
  This selects CLI translation code, not RPC callbacks.
- `lib/transport.sh`: invokes sysrepocfg for RPC/action requests and datastore
  access, preserving response data and reporting transport failures.
- `lib/output.sh`: text/JSON output, diagnostics, ANSI colors, and exit handling.
- `lib/help.sh`: top-level help and command help lookup.
- `commands/<name>/command.sh`: command argument parsing and the call sequence
  for request construction, submission, and presentation.
- `commands/<name>/request.jq`: constructs modeled JSON using explicitly typed
  arguments. YANG remains responsible for model validation.
- `commands/<name>/help.txt`: usage, options, and examples.

### Composition and conventions

- Runtime dependencies are Bash, jq, and the sysrepocfg executable and its
  dependencies. No additional language toolchain is introduced for the CLI.
- Each module supplies its own `cli/commands/<name>/` adapters. The root Flake
  passes these entries to the manager's CLI package builder. It generates an
  explicit command table and rejects duplicate command paths. Loading another
  module's private implementation is not part of this interface.
- Commands expose a common `command_main` function and run in isolated
  subshells so their functions and variables do not overwrite other commands.
- Global options include `--help`, `--json`, `--system`, `--environment`, and
  `--color=auto|always|never`. Tasks also support `--no-wait`.
  Automatic color requires a terminal and respects `NO_COLOR`. JSON output
  never includes ANSI styling; diagnostics go to stderr.
- JSON is constructed with jq, never interpolated manually. Argument arrays
  preserve quoting; command lookup does not use `eval`.
- Shared transport code checks failures explicitly. Exit codes distinguish
  success (0), operation failure (1), invalid usage/model input (2), unavailable
  service/evidence (3), and conflict (4). An RPC reply indicating application failure must not be
  reported as success merely because sysrepocfg exited successfully.
- The Nix package binds interpreter, library, command, and executable paths to
  its immutable installation. It does not load scripts from the current directory.

## Runtime

Each module may provide a `runtime/` when it needs to handle operations,
configuration changes, or actual state. Modules that only supply generated
configuration do not necessarily need one. Filenames below describe logical
components. C source files use `.c`/`.h`; Shell operations use `.sh`. A logical
component becomes a directory only when it needs multiple related files.

```text
modules/<name>/runtime/
├── main
├── callbacks/
│   ├── configuration-change
│   ├── rpc-action
│   └── operational-data
├── operations/
└── lib/
```

- `main`: program entry. Connects to sysrepo, opens sessions, registers callbacks,
  keeps subscriptions active, and releases resources on shutdown. Application
  operations belong elsewhere. This entry need not be a separate source file.
- `callbacks/configuration-change`: handles configuration change events when needed.
- `callbacks/rpc-action`: accepts RPC/action inputs, invokes the relevant operation,
  and constructs the modeled result or error.
- `callbacks/operational-data`: supplies actual state through sysrepo.
- `operations/`: implements the module's concrete actions.
- `lib/`: optional helpers private to this module.

Only components needed by a module are included. Subscription callbacks require
a running subscriber; sysrepocfg submits requests but does not host those callbacks.
Modules do not invoke one another's private runtime code.

### Manager runtime

```text
modules/manager/runtime/
├── main
├── callbacks/
│   ├── rpc-action
│   └── operational-data
├── operations/
│   ├── configuration
│   ├── plan
│   ├── build
│   ├── deploy
│   └── rollback
├── snapshot/
└── journal/
```

- `callbacks/rpc-action` accepts only the manager's own modeled operations.
- `operations/configuration` owns validated configuration commit/import/export
  and persistence recovery; it does not execute application-specific operations.
- `operations/plan` binds proposed changes to immutable inputs and prior state.
- `operations/build` invokes Nix using frozen inputs.
- `operations/deploy` activates the resulting configuration.
- `operations/rollback` restores a previously recorded deployment.
- `snapshot/` freezes configuration and identifies build inputs.
- `journal/` records task progress, results, and recovery information.
- `callbacks/operational-data` exposes deployment task progress and actual state.

```text
CLI -> sysrepocfg -> sysrepo -> callbacks/rpc-action -> operations/<operation>
```

Long-running operations return a task identifier after reliable task submission
and continue in the background. Clients query progress through modeled state.
Execution and recovery remain the runtime's responsibility, not the CLI's.
Runtime tests belong in the module's outer `tests/` directory, initially empty.

## Applications

```text
modules/applications/
├── README.md
├── default.nix
├── model/
│   └── folio-applications.yang
├── src/
│   ├── package.nix
│   ├── system.nix
│   ├── user.nix
│   ├── flatpak.nix
│   └── apps/
│       ├── zen.nix
│       └── obs.nix
├── cli/
│   └── commands/
│       └── applications/
│           ├── command.sh
│           ├── request.jq
│           └── help.txt
├── runtime/
│   ├── main
│   ├── callbacks/
│   │   ├── rpc-action
│   │   └── operational-data
│   ├── operations/
│   │   ├── install
│   │   ├── update
│   │   ├── remove
│   │   ├── reconcile
│   │   └── rollback
│   ├── journal/
│   └── lib/
│       └── flatpak
└── tests/
```

- `model/`: application selection, sources, enablement, operations, and observed
  installation state.
- `src/package.nix`: builds the module's runtime and packages its CLI resources.
- `src/system.nix`: enables host Flatpak infrastructure. Desktop portal
  configuration belongs to the desktop module.
- `src/user.nix`: installs user configuration, runtime services, and application
  integration, and publishes the generated managed-file manifest.
- `src/flatpak.nix`: shared Flatpak integration consuming the frozen application
  selection; it does not maintain a second editable application list.
- `src/apps/`: application-specific configuration generation and integration.
  These files are internal components, not independent module entries.
- `cli/commands/applications/`: application command translation and help.
- `runtime/operations/`: installs, updates, removes, and reconciles managed
  Flatpak applications as the user. Nix-installed applications are updated
  through the manager's build and deployment operations.
- `runtime/lib/flatpak`: invokes Flatpak commands and interprets results/errors.
- `runtime/journal/`: application task state, managed ownership, configuration
  file manifests, and before/after ref and commit records. Persistent records
  live outside the checkout.
- `tests/`: initially empty; test implementation follows the README acceptance levels.

Reconciliation compares the desired selection with actual installations and
only modifies applications explicitly managed by Folio. Independently installed
applications are not removed. Application removal preserves personal data by
default. Typst belongs to the terminal module, not this module.

### Application configuration

Editable desired values live in sysrepo. Nix consumes a frozen snapshot and
generates configuration and a managed-file manifest; application Nix files do
not store a second editable copy of those values. User activation publishes the
manifest; applications runtime copies its owned files into Flatpak application
directories as regular files. It does not rely on sandbox access to Nix store
symlinks. Flatpak installation and Nix configuration generation remain separate
responsibilities.

- Declarative settings, such as themes and managed defaults, use Nix generation
  where the application supports it.
- Runtime changes use a module operation when the application exposes a reliable
  interface.
- Application-owned data, such as browsing history, login state, and OBS scenes,
  remain application-managed by default.

Each application defines which files or fields Folio owns, using its actual
Flatpak profile/configuration paths. Do not replace an entire writable profile
or configuration directory. If the application rewrites a file, use a supported
policy, separate managed file, or runtime interface rather than competing writers.
