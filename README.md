# Folio

Folio is a NixOS configuration framework built around module-owned YANG models
and sysrepo. One CLI manages system and user configuration; each module executes
its own operations. Root Nix composition lives in the manager module.

Status: foundation, durable user configuration, Foot deployment, root deployment
and system-owned power actions have passed isolated UEFI guest tests. A standalone
UEFI image and module-owned VM lifecycle are implemented. Later modules below
remain the implementation contract until their stages pass. Owned Zen/OBS Flatpak
lifecycle and regular-file configuration delivery have passed an isolated guest
gate. Niri, desktop resources, cold-start Chinese input and actual OBS portal capture
have passed a disposable virtual DRM guest gate. Exact GUI parity and physical
hardware acceptance remain unverified. No development-host
activation or physical installation has been performed. See [STRUCTURE.md](STRUCTURE.md)
for directory ownership.

Terminal/developer tools, the paired model upgrade and selective removal with
personal-data preservation have also passed a disposable user-profile guest gate.
System policy and network-owned connection/proxy actions have passed an isolated
UEFI guest gate, including real DNS/proxy traffic, firewall and key-only SSH.
Integrated release acceptance has passed one disposable UEFI lifecycle, including
both scopes, interrupted recovery, retained rollback, cached apps, actual Chinese
input/OBS capture, denied effects and externally observed reboot/poweroff. The
unified Folio hardware configuration builds successfully; physical acceptance
remains deferred.

Implemented modules keep Nix implementation in `src/`, client entry points and
command resources in `cli/`, subscribers and operations in `runtime/`, models in
`model/`, and behavioral checks in the outer `tests/`. Module `default.nix` files
expose those owned implementations. Manager composition remains
`modules/manager/src/outputs.nix`; product documentation stays in this README.

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
changes requiring an explicit paired upgrade. `ctl`/`cfg` are maintenance wrappers;
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
it does not initialize system state on the development host. Managed rollback and
offline maintenance are described below.

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
Unavailable rollback protocols/inputs return exit 3; unsupported scopes return exit 2.

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
rollback use the explicit maintenance commands below; interrupted activation reports failure or interruption.

Deployment now retains matching configuration/model identities in scoped
`deployments/revisions/`. On subscriber restart, recovery probes actual effects:
it can finish an activation's recorded successful publication or restore only a
profile selection when actual files/running system still match the before
closure. It never repeats activation to infer success. Ambiguous effects and
failed restoration stay visible in `status` under `recovery`, degrade health and
block further applies. Preserve those records and their GC roots for explicit
managed rollback and schema migration.

Offline paired maintenance is available through the separate
`folio-manager-maintain SCOPE BOOTSTRAP ACTION ID [FROZEN_SOURCE_OR_REVISION]` command.
`BOOTSTRAP` must identify the currently selected generation's immutable bootstrap,
recorded in its `folio-home.json` or `folio-system.json`. Run user maintenance as
the provisioned account with its real HOME and runtime directory; system
maintenance requires root. For example, on a provisioned disposable user system:

```sh
artifact=$(readlink -e "${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager")
bootstrap=$(jq -r .bootstrap "$artifact/folio-home.json")
folio-manager-maintain user "$bootstrap" snapshot before-upgrade
# Restore that snapshot's models, startup/running data and selected closure:
folio-manager-maintain user "$bootstrap" restore before-upgrade
```

Snapshots require desired startup/running data to agree with the selected closure.
Rollback can also capture an unapplied later desired revision: the snapshot records
its desired data and the separately verified actual deployment digest, preserving
that drift as evidence instead of calling it applied.
The command rejects active deployment/VM jobs, unresolved effects and interrupted
maintenance. It stops registered consumers, records their prior active state and
uses runtime service conditions to prevent premature restart during activation.
Repository mutations also require an exclusive repository lock and no real
sysrepo connection locks. The scoped mutation lock precedes repository and
initialization locks; consumers restart after the mutation lock is released.

`upgrade ID FROZEN_SOURCE` builds a candidate bootstrap and closure from an
immutable source containing `folio-input.json`; system builds run as
`folio-builder`. The candidate configuration must exactly match the isolated
migration result, model/tool identities and closure metadata. Successful
installation activates and verifies the paired closure before publishing its
maintenance revision. Installation/activation failure attempts to restore the
original repository and closure. A failed restore retains the schema barrier,
consumer conditions and journals; repeat `restore ID` after resolving the recorded
failure. Restore is independent of the manager RPC service. Application data is
outside these snapshots.

Backups live in scoped `backups/repositories/ID/`, with raw repositories, normalized
exports, model identities, coordinator/transaction journals and GC roots for both
pairs. Partial candidate preparations are retained on explicit retry. Changed
models without a new YANG revision are rejected. Terminal owns two hash-bound
schema transitions: `2026-10-18` to `2026-10-19` adds opacity in percent; the next
revision, `2026-10-20`, converts that value to a decimal unit fraction (`75` becomes
`"0.75"`). Both schemas and their transforms remain module-owned. The Foot
renderer consumes the fraction as background alpha. Unknown transformations
remain unavailable; schema revisions are never changed in place.

`folio rollback REVISION_ID` restores a retained revision's desired configuration,
models and closure together. IDs come from `status`'s applied `revisionId` (or
`planId` for an ordinary deployment) and scoped `deployments/revisions/`. Source,
configuration, model, tool, account and closure identities are checked before
installation. A later failed desired revision is preserved only in the before
snapshot; boot does not reapply it after rollback. `--rebuild` reconstructs the old
source using current manager/repository implementations while retaining its old
models, adapters and lock. A rebuild must still prove a supported worker protocol
and exact retained model/tool identities; incompatible source is unavailable.
System rollback is an offline root operation, invoked as root with
`folio --system rollback REVISION_ID [--rebuild]`; user rollback runs as its owner.

`folio cleanup` previews eligible plans/tasks; `folio cleanup --apply` records the
selection and removes only their deployment records and known GC-root links.
Cleanup takes queue before mutation locks, excludes active/locked workers,
current/previous successful revisions and every backup/recovery/upgrade reference,
and preserves adoption backups and application data. It does not run global Nix
GC or prune repository backups. System cleanup likewise requires root. `status`
includes maintenance phases; while consumers are offline it can inspect readable
scoped journals without opening the repository. Pending maintenance degrades
health and blocks new configuration commits/applies. Do not delete backup roots
or invoke repository primitive `finalize` as a substitute for paired verification.

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

`portable` is an environment/output name, not a binding to the development
laptop or a guarantee of compatibility with every machine. The default system
is an x86_64 UEFI disposable guest with root/EFI labels `nixos`/`ESP`. No specific
GPU PCI IDs or development-host disk UUIDs are selected. Physical deployments
must select the `physical` storage profile, supply inspected stable root/EFI
paths and disable the prototype password. That model support is not an installer
or proof of physical driver/boot compatibility. Keep existing data and recovery
access; a physical target needs its own reviewed configuration and acceptance.

### Hardware targets

One root Flake and `modules/manager/src/defaults.nix` supply shared software,
preferences and user identity. Manager composition uses public system storage/boot
and devices CPU/GPU exports. There are two supported targets:

| Target | Purpose |
| --- | --- |
| `folio` | Existing migrated USB installation shared across the laptop and desktop |
| `portable` | Disposable UEFI guest for development and acceptance tests |

```sh
nix build --no-link --print-out-paths .#nixosConfigurations.folio.config.system.build.toplevel
nix build --no-link --print-out-paths .#nixosConfigurations.portable.config.system.build.toplevel
nix eval --json .#lib.folio.targets
```

The ordinary checkout defaults to `portable`. Use the explicit `folio` output to
prepare the physical USB system. Its bootstrap `target.json` and frozen source
`folio-target.json` record the hardware selection. Plans retain the installed
selection; conflicting source targets are rejected. Within a frozen source,
`nixosConfigurations.portable` is the manager's stable entry for its selected
target. Hardware names are separate from the existing environment/account
identity. Builds never autodetect hardware or read live sysrepo.

The old `laptop`, `desktop`, `laptop-migration` and `desktop-migration` build
outputs and dedicated GPU profiles have been removed. Old installed bootstraps
still name their original targets: ordinary plans against this simplified source
cannot update those installations until an explicit transition to `folio`.
Retained immutable system generations and recovery data remain available; source
cleanup does not switch the live system or remove old boot entries. Recovery
helpers still recognize retained `laptop-migration` closures.

### One USB system across the laptop and desktop

`folio` preserves the existing migrated account, password/keyring policy, private
runtime proxy compatibility, software and Btrfs mounts across both machines. It
is not a fresh-install image: the Folio account and migration runtime state must
already exist. CPU/GPU policy lives in `modules/devices/src/folio.nix`; storage and
boot policy live in `modules/system/src/folio.nix`.

Supported machines are the Lenovo Legion Y7000 IRX9 with Intel i7-13650HX and
RTX 4060, and MSI MAG B650M MORTAR WIFI with Ryzen 7 9700X, RTX 3090 and AMD
integrated graphics. The closure supplies Intel/AMD microcode, i915/amdgpu,
firmware/Mesa and one stable NVIDIA driver with open modules and DRM modesetting.
See the [NVIDIA module documentation](https://github.com/NVIDIA/open-gpu-kernel-modules).
Kernel PCI matching selects applicable drivers; Niri selects display/render
adapters without fixed PRIME addresses, DRM card numbers or global render
variables. Integrated-GPU rendering, discrete-GPU power saving and application
compute environments still require appropriate runtime configuration/validation.
No CUDA SDK is installed in the base desktop.

Storage uses inspected USB root/EFI UUIDs and Btrfs `root`, `home`, `nix`
subvolumes. Internal disks are not configured or partitioned. The boot menu keeps
up to ten generations with a five-second selection window; EFI variable writes
are disabled. Machines must support x86_64 UEFI USB boot. Check the ESP removable
fallback loader during deployment: its contents were not readable without
privilege during preparation. Secure Boot enrollment/signing is not provided.

After deploying `folio` once, future plans retain that target on either machine.
Shut down normally before moving the disk. Moving it alone requires no rebuild
or target selection. Keep a known-working system generation while validating both
machines. Builds do not establish physical display, suspend or power health.

Earlier build/policy evidence is retained outside source under
`/tmp/folio-mobile-*` and `/tmp/folio-target-rename-build.log`; the earlier name
`mobile` was renamed to `folio`. No activation, EFI writes or reboot was performed
while preparing or simplifying these targets. Live desired data and personal files
were not changed.

Simplification validation (2026-10-19) passed:

```sh
nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths -L \
  .#nixosConfigurations.folio.config.system.build.toplevel \
  .#system-retirement .#checks.x86_64-linux.catalogue
nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths -L \
  .#checks.x86_64-linux.account-migration
```

Evidence: `/tmp/folio-simplify-build.log`, `/tmp/folio-simplify-account-check.log`
and `/tmp/folio-simplify-policy.json`. Evaluation confirmed exactly the two public
targets, rejection of retired targets, frozen `folio` identity, retained driver
support and existing password preservation. The account guest verified rename/
restore and login-service recovery; this does not establish physical activation.

### Migrating the existing Sylphy account

`nixosConfigurations.folio` retains guarded account migration support for the
inspected existing USB installation. It supplies both machines' hardware, adds
administrator access and login/passwd GNOME Keyring integration, and retains the
existing private proxy policy at runtime. It is not a fresh-install target:
activation refuses to create a duplicate UID 1000 or run before the offline rename.

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
folio apps init|list|install|update|remove|reconcile|adopt|prepare ...
folio apps rollback|resume|status REVISION_OR_TASK_ID ...
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

The current application entry is `folio apps` in user scope. Enable/apply its
system contribution for Flatpak infrastructure and its user contribution for the
subscriber and generated manifest. Then use:

```sh
folio apps init
folio apps prepare all
folio apps install all --offline
folio apps list
folio apps update zen
folio apps reconcile zen --offline
folio apps adopt obs
folio apps remove obs
folio apps rollback REVISION_ID all --offline
folio apps status TASK_ID
folio apps resume TASK_ID
```

Mutations accept `zen`, `obs`, or `all`, optional `--offline` and
`--request-id ID`; `--no-wait` is a global option. `prepare` downloads and records
complete resolved transactions without deploying apps. Offline work requires
those retained plans and matching cached refs, including locale and graphics
extensions. Initial pinned installation requires the target commit to resolve
from that preparation; a different available branch head is rejected. Existing
installed pinned apps use explicit commit updates. Historical rollback currently
requires local retained content and matching refs; missing/changed refs return
unavailable before effects. Shared deployed runtimes are preserved; a historical
plan requiring a different shared runtime is unavailable.

Set the Zen app's `zen-profile` to an existing relative profile directory recorded
in its sandbox `profiles.ini`, then build/apply the user configuration and run
reconcile. Missing profiles or stale manifests leave configuration pending.
`--adopt-files` allows first ownership of existing supported files, retaining
unique backups. Unexpected edits to an already owned file must be resolved before
resuming its recorded task. Workspace seeding and OBS Qt appearance remain
explicitly unsupported; scenes, logins, databases and sessions remain app-owned.

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
features rather than overwriting OBS state. Screen-capture acceptance requires
actual frames through desktop portals and PipeWire. Devices and desktop retain those host capabilities.

## Terminal and developer tools

The user `terminal` selection now renders Foot and Zsh with the reused Pure
Powerlevel10k prompt, completion, history, suggestions and highlighting. Its
`folio-terminal:terminal.shell` settings control those features; `.tools` contains
independent boolean switches for bat, btop, eza, fd, fzf, jq, ripgrep, zoxide, unzip,
unrar, chsrc, just and Typst. Typst remains a terminal component. Only the named
unrar package is allowed by the unfree predicate. Zsh history/cache are writable
per-user state. The system terminal contribution registers Zsh; changing a user's
login shell still requires an explicit system account `login-shell` selection.

`git` installs Git and optional GitHub CLI, defaults new repositories to `main`,
and enables rebasing pulls. Set `folio-git:git.user-name` and `.user-email` in the
user configuration; no personal identity, signing key or token is supplied.

`emacs` provides Org/Org-roam, backlinks, search/completion, the dashboard and
Everforest preferences. `C-c n f` finds notes, `C-c n b` shows backlinks and
`C-c n h` opens the start page. Notes default to `~/Documents/Notes`; set
`folio-emacs:emacs.notes-directory` to reuse an existing directory. The rebuildable
index and editor history stay in `$XDG_STATE_HOME/folio/emacs`. Optional personal
additions live in `~/.config/folio/emacs/local.el`, which Folio does not manage.

`codex` installs the pinned CLI, Zsh completion and a selectable Folio `.tmTheme`.
Choose it with `/theme`; theme loading follows the
[official Codex customization interface](https://learn.chatgpt.com/docs/cli-customization).
Mutable Codex configuration, authentication and session state remain application
owned. GitHub/Codex authentication requires the target user's own setup. Disabling
a module removes its managed files while preserving repositories, notes, indexes
and personal application data.

Use `folio config export desired.json`, edit the owning module settings, then
`folio config import desired.json` and the plan/build/apply workflow above. A
configuration commit alone does not install software or change the login shell.

## Desktop, input and device integration

User modules render Niri, Waybar, Mako, Fuzzel, clipboard
history and screenshots; system desktop owns the login session and portal
prerequisites. Appearance provides Everforest palettes, Maple Mono NF CN, a
recolored GoogleDot cursor and GTK resources. Shared preference and module override
origins are recorded in `~/.config/folio/appearance.json`. Applying a generation
does not log out the current desktop; session-dependent changes need a new login.

Fcitx5/Rime Ice starts as a user service. Initial profile and candidate defaults
are seeded only when absent; existing personal profiles, dictionaries and history
are preserved. The bar observes the real input-method indicator. Chinese input
has committed text from a fresh profile in an isolated Wayland guest. First-run
Rime Ice dictionary deployment must finish before Chinese composition is ready.

`folio devices status` reports actual audio, Bluetooth adapter, backlight, power
profile and basic hardware observations. `volume`, `mute`, `brightness` and
`profile` use the module's own subscriber and native services. Media and brightness
keys call those public commands when the user devices module is selected. Missing
hardware or authorization returns unavailable; a configured service does not prove
physical device health. Bluetooth pairing remains available through Blueman.
Physical GPU, sound, backlight and Bluetooth acceptance remains separate from guest
checks. The virtual DRM acceptance fixture observed changing OBS frames through
the real portal and PipeWire. It uses software Mesa in an isolated SDL/Xvfb QEMU
display; it does not establish physical GPU acceleration or encoder performance.

## Network and system policy

The system-owned `network` contribution enables NetworkManager, DHCP/connection
DNS and a default-deny inbound firewall. Explicit `dns` addresses override
connection DNS. SSH and Mihomo are opt-in; SSH permits public-key authentication
and opens its configured port only when `ssh.open-firewall` is enabled. Provision
authorized public keys on the target in `~/.ssh/authorized_keys` or
`/run/folio/authorized_keys/ACCOUNT`.

```sh
folio --system network status
folio --system network connect CONNECTION_UUID INTERFACE
folio --system network disconnect INTERFACE
folio --system network proxy-mode rule
folio --system network proxy-select DIRECT
```

These commands require system operator access. Connection commands use an existing
NetworkManager profile; provision its credentials outside Folio desired data.
Proxy actions use Mihomo's private Unix controller and return actual observations.
Live proxy mode/selection are application state; they do not commit desired policy.
Disabled services, missing profiles/nodes and backend failures return unavailable.
The optional `proxy.provider-file` references a target-local YAML under `/run` or
`/var/lib`; systemd loads it as a runtime credential. Evaluation and builds never
read its contents. The proxy listener binds loopback; TUN is separately opt-in.

System policy models locale/time sync, console, bounded journald storage, zstd
zram and Nix build/store settings. Storage defaults describe a disposable guest.
Physical configuration requires explicit stable root/EFI device paths and
`prototype-password=false`; accounts then start with locked password hashes.
No adapter partitions disks. The public `nixosModules.portable` exposes the same
frozen composition as `nixosConfigurations.portable` for explicit integration.
Physical storage boot, Wi-Fi, TUN, private provider nodes and NTP synchronization
require separate target evidence.

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
tests. Behavioral checks live under the owning module's outer `tests/`.
The final release scenario reuses the manager and desktop fixtures rather than
introducing another test framework.

- Static: Nix/Shell syntax, shell lint, YANG import/type/constraint validation.
- Module: request translation, configuration rendering, scope checks, modeled
  errors and ownership behavior without changing the host.
- Integration: real isolated sysrepo, actual CLI and subscribers, persistence,
  missing subscribers, conflicts, migrations and controlled backend failures.
- System: disposable VM boot, both scopes, passwordless updates, persistence,
  interrupted deployment, rollback, desktop/Flatpak integration and power actions.

`checks.x86_64-linux.integrated-release` requires an isolated public Flatpak cache
and matching retained application plans as explicit overrides. It fails before
boot when either is missing; it never substitutes host application data. With
their existing store paths in `FOLIO_TEST_CACHE` and `FOLIO_TEST_PLANS`, run:

```sh
nix build --no-link --impure --expr '
  let f = builtins.getFlake (toString ./.);
  in f.checks.x86_64-linux.integrated-release.override {
    cache = builtins.storePath (builtins.getEnv "FOLIO_TEST_CACHE");
    plans = builtins.storePath (builtins.getEnv "FOLIO_TEST_PLANS");
  }'
```

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
6. Desktop, input, developer tooling and network/system policy (implemented).
7. Integrated VM acceptance and separately authorized physical hardware validation.

## Upstream references

- [Sysrepo API, permissions, instances and datastores](https://github.com/sysrepo/sysrepo)
- [YANG 1.1](https://www.rfc-editor.org/rfc/rfc7950.html)
- [YANG JSON encoding](https://www.rfc-editor.org/rfc/rfc7951.html)
- [Standalone Home Manager](https://nix-community.github.io/home-manager/installation/standalone.html)
- [Flatpak command reference](https://docs.flatpak.org/en/latest/flatpak-command-reference.html)
- [Flatpak desktop integration](https://docs.flatpak.org/en/latest/desktop-integration.html)
- [Zen Linux installation](https://docs.zen-browser.app/guides/install-linux)
- [OBS Linux installation](https://obsproject.com/kb/linux-installation)
