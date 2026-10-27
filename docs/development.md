# Configuration and development

## Choose the configuration entry

| Change | Entry | Effect |
| --- | --- | --- |
| Current font, timezone or application setting | `folio config` or the panel | Saves desired data; review, build and apply to activate. |
| Initial module choices and personal preferences | `modules/manager/configuration/defaults.nix` | Used when initializing a repository or evaluating an unprepared checkout. |
| Accounts, disk identities or target-specific module choices | `modules/manager/configuration/targets/folio.nix` | Supplies the installation's initial differences and NixOS target modules. |
| Shared deployment on another machine | `just init`, then `modules/manager/configuration/targets/local/` | Reuses installed NixOS modules; `host.nix` adds hardware settings, `host.json` supplies initial identity. See the README deployment guide. |
| Field types, ranges or structural constraints | The capability's `model/` | Requires a versioned model migration when the model changes. |
| Generated files, packages or service behavior | The capability's `src/` and `runtime/` | Rebuilt through the reviewed source workflow. |

Initial configuration lives in `modules/manager/configuration/`.
Keeping the files within `modules/` also lets
previously installed managers capture them before their source whitelist has
been updated. Production composition imports the internal path directly.

Initial defaults do not overwrite an existing sysrepo repository. Change an
installed system's desired data explicitly; source changes and configuration
changes are reviewed together by the normal plan/build/apply workflow.

```sh
folio --system config explain /modules/system/time-zone
folio --system config set /modules/system/time-zone '"Asia/Shanghai"'
folio config set /modules/terminal/foot/padding '"18x18"'
folio config explain /preferences/font-size
folio plan --source "$PWD"
```

Values are JSON. `get` returns the selected desired field, including model defaults;
`explain` resolves inherited global preferences and includes deployment state.
`unset` removes an override. Theme selection uses `folio theme set THEME` and its
existing coordinated deployment. Font preferences may also have an appearance
module override; inspect that module if an application differs from the global
preference. A module setting's inspection origin explicitly includes model
defaults because normalized desired data does not retain their explicitness.

`config show` and the panel share one preference resolver. Pending deployment,
persistence and recovery observations are independent of configuration values.
Missing or concurrently changed observations produce unknown status. Matching
configuration digests do not establish hardware or application health.

## Initial configuration and target overrides

`modules/manager/configuration/defaults.nix` provides system and user documents. Target files
contain only their differences plus public, module-owned hardware adapters.

- `environment.system` and `environment.user` select the scope.
- Entries in `environment.<scope>.modules` merge by `name`. An override preserves
  existing nested settings; a new entry appends a selection and should explicitly
  set `enabled` when it is intended to be active.
- Nested objects merge recursively. Lists other than the module selection list
  are replaced, including users, groups, application selections and DNS servers.
- Repeated module overrides in one target are rejected.

For example, a target can change one terminal choice without restating the
default terminal selection:

```nix
environment.user.modules = [
  {
    name = "terminal";
    "folio-terminal:terminal".foot.padding = "18x18";
  }
];
```

Inspect initial data without querying the running repository:

```sh
nix eval --json path:.#lib.folio.initialConfiguration
```

YANG remains the authority for types and data defaults. Initial profiles contain
intentional installation choices. Pure Nix/bootstrap adapters retain explicit
fallbacks where their input is not yet model-normalized; keep those fallbacks
local to the owning module and consistent with its model. Avoid introducing a
second generated schema or bypassing frozen-input identity checks.

## Module contract

Declare packages, commands, models, requirements, provided capabilities and
activation hints in the capability's `default.nix`. Register the module in the
explicit catalogue in `modules/manager/src/outputs.nix`, then select it in the
appropriate initial profile or installed desired data.

```nix
provides.system = [ "example-provisioned" ];
requirements.user.capabilities = [ "example-provisioned" ];
impacts = [ "Open a new application window to load this setting." ];
```

Capability availability derives from the provider's enabled selection. It does
not report service or device health. Capability names have one provider per
scope; collisions fail composition. Catalogue metadata is shared by bootstrap,
CLI and runtime consumers.

The manager resolves the modeled container into `context.settings` once, using
`settingsKey` (default `folio-<module>:<module>`). `context.selection` retains the
full original selection. Adapters also receive `moduleName`, identity, resolved
globals/theme, preference origins, enabled modules and public capabilities.
The system fallback subscriber's account follows the initial user selection.
Subcomponents use that context instead of re-importing another capability's
private settings or re-resolving the global theme. Standalone renderers may keep
their own documented fallback theme.

Routine source refactoring and changes to initial choices do not require YANG
revision changes. Actual model changes retain the paired migration procedure in
the [reference](reference.md#model-upgrades).

## Code conventions

Use the root's pinned tool versions:

```sh
nix run path:.#check -- format
nix run path:.#check -- style
```

The formatter applies Nixfmt, Ruff and Stylua to repository-owned Nix, Python and Lua sources.
`nix fmt` uses the same formatter once new files are tracked by Git; explicit
`path:.` commands also include files that have not yet been staged.
The style entry verifies formatting, Python correctness rules, Bash syntax and
the check runner's ShellCheck result. Nix `writeShellApplication` additionally
checks assembled shell operations during their builds. Python fragments executed
inside the NixOS driver have narrowly scoped exceptions for injected names in
`ruff.toml`; ordinary Python files keep undefined-name checks.

Keep public module exports declarative and implementation helpers under `src/`.
Separate transport, record persistence, domain operations and presentation where
the same code otherwise mixes responsibilities. Workflow record encoding and
durable replacement live in `cli/commands/workflow/records.py`; process-local
presentation stays in the command entry. Do not change journal bytes, protocol
versions or transitions as a side effect of moving code.

## Existing checks and stable fixtures

```sh
nix run path:.#check -- fast
nix run path:.#check -- integration
# Requires isolated store paths; never point these at personal Flatpak state.
FOLIO_TEST_CACHE=/nix/store/… FOLIO_TEST_PLANS=/nix/store/… \
  nix run path:.#check -- release
```

Groups are declared once in `modules/manager/tests/groups.nix` and exposed as
`lib.folio.checkGroups`. They select existing checks, without adding test cases
or removing existing aliases. `fast` covers configuration, workflows, HTTP,
catalogue/store and small module checks. `integration` adds generated tools,
migrations, browser interactions and module integration. `release` adds full
system guests, recovery and complete desktop/application acceptance; it requires
the documented cache and application-plan inputs before starting.

Tests for module behavior use the fixed profile in
`modules/manager/tests/fixtures/defaults.nix`. Integration bootstrap, Home Manager
generation and frozen guest sources are composed from that same profile, so
changing personal defaults does not change unrelated expected behavior. The
existing foundation check still validates the real initial configuration.
Change fixture choices when the tested contract changes, independently of
personal configuration. Keep expected outcomes explicit rather than deriving
them from the implementation's result.

Owned checks stay in the module; cross-module composition stays in manager
tests. Ordinary checks use temporary HOME/XDG state. Fixed guest accounts are
part of their disposable scenario and never name host data. Process doubles
exercise process contracts; guest checks establish actual activation effects.
Run focused checks for the changed contract and retain failure logs before
starting broader acceptance. Guest checks require KVM and release inputs;
successful local checks do not establish physical hardware behavior.

## Deployment protocol invariants

| Concern | Required ordering or behavior |
| --- | --- |
| Configuration commit | Mutation lock, recover prior journal, check expected digest, persist `prepared`, update running, persist `accepted`, update startup, persist `saved`. |
| Commit recovery | `prepared` restores the before document; `accepted` rolls the after document forward. Validate its digest before either action. |
| Task submission | Queue lock before mutation lock where needed; request identity binds the operation and plan. Reusing an ID with other input conflicts. |
| Task execution | Acquire the task lock without waiting, then acquire mutation lock for activation. Recovery/cleanup use nonblocking task locks while holding mutation lock. |
| Activation | Record before/after artifacts before changing profiles; persist effect phases; verify effects before publishing current deployment. |
| Cross-scope workflow | Validate reviewed inputs, apply system before user, observe prior tasks before a retry, and refuse unresolved effects. |
| Durable records | Write a temporary file, flush it, replace in the same directory and flush that directory. |
| Compatibility rebuild | Preserve retained configuration/composition and model identities while explicitly updating the worker/repository implementation. |

These are local serialized state machines, not an atomic transaction across
NixOS, Home Manager and application data. Keep partial outcomes inspectable and
require explicit recovery when effects cannot be verified.
