# Execution rules for every assigned AGENT

## Scope and architecture

- Deliver working behavior, not success-shaped scaffolding. Incomplete commands
  must be unregistered or explicitly unavailable with exit code 3.
- Follow README's ownership: one root Flake/lock, explicit module catalogue,
  module-owned YANG/subscriptions, separate scopes, no top-level host/home trees,
  no generic manager action router and no private cross-module imports.
- Use Bash, jq and sysrepocfg for the CLI, C with libsysrepo/libyang for subscribers.
  Optional fixed-path Shell operations consume/return modeled JSON. Do not migrate
  Sylphy's Rust CLI/manager architecture or introduce a new CLI language framework.
- Separate desired data, immutable plans/builds, application, observed state and
  journals. Configuration commits have no external application side effects.
  Never evaluate Nix against live sysrepo or perform online Flatpak work in builds.
- Keep available models/command adapters independent of capability activation.
  Missing prerequisites and unsupported scopes fail explicitly.
- Inspect and reuse Sylphy before replacing existing behavior. Do not modify that
  checkout or depend on it through absolute imports, runtime paths or symlinks.
- Use English in source, comments, CLI design/help/errors, tests and task records.
  Preserve required upstream names, Chinese input functionality and font support;
  translate copied prose rather than disabling those features.
- Maintain only root README.md as product documentation. Task files are the
  requested planning exception. Leave existing STRUCTURE.md as reference; do not
  expand it or create module READMEs, docs trees or tutorials. Required help.txt,
  schema descriptions and useful code comments remain implementation resources.
- Keep README commands/status truthful. No fabricated build, activation, hardware
  or rollback claims. Distinguish planned design from delivered behavior.
- Avoid unrelated cleanup, speculative frameworks and empty module/test trees.
  Create components only when needed; tests live in the owning module's tests/.
- Preserve private application data. No browser logins, keys, credentials, proxy
  subscriptions, real network records or runtime state in source/build snapshots.

## Git and milestones

1. Inspect worktree changes first and preserve others' work. Initialize a normal
   repository if absent using `git init --initial-branch=main`.
2. If .git is read-only or author identity is missing, report the actual blocker.
   Do not invent identity, remove protected metadata or redirect Git to /tmp.
3. Commit Stage 00's reviewed baseline. Each later stage must pass its relevant
   gate before its implementation commit. Do not require a commit/full suite for
   every numbered item. A larger stage may use coherent tested submilestones.
4. Use English Conventional Commits: `type(scope): imperative description`.
   Examples: `chore(repo): establish implementation baseline`,
   `feat(manager): apply frozen user configuration`,
   `fix(manager): recover accepted configuration journals`.
   Choose feat, fix, refactor, test, docs, build or chore appropriately. Optional
   bodies explain behavior and meaningful validation in English.
5. Review branch, intended diff, `git diff --check` and staged diff. Use explicit
   paths for git add. Never blindly stage secrets, logs, disks, outputs or metadata.
6. Record/report the resulting SHA and worktree state. Do not push, rewrite shared
   history, activate Folio on the development host or execute host power actions.
   Physical disk writes and target activation require actual target authorization.

## Testing without excessive repetition

The owner explicitly rejects full testing after every small edit. Batch related
changes, run cheap affected checks during development, then run the bounded stage
gate once its feature is ready. After a fix, rerun failed/affected checks; repeat
broader checks only if shared behavior or earlier evidence has been invalidated.

| Change | Normal checks | Broaden when |
| --- | --- | --- |
| README/tasks/help prose | Diff, links, English, command accuracy | Protocol or actual command behavior changed |
| Nix adapter/rendering | Parse/evaluate affected output, render check | Shared composition/dependency changed |
| YANG/config commit | Schema and affected real repository integration | Shared schema/import/persistence changed |
| Bash/C callback | Syntax/lint/build and affected behavior | Shared transport/scope/task contract changed |
| Journal/root activation | Focused fault test and scoped guest case | Worker/deployment assumptions changed |
| Application/desktop | Affected app/session/config case | Shared portal/runtime/manifest changed |
| Integrated release | One bounded final regression pass | Material later changes invalidate it |

- Do not run full `nix flake check`, NixOS rebuilds or desktop suites after every
  edit/commit. Select named checks/derivations; reuse unchanged built closures.
- Test behavior, risk and failure boundaries. Avoid source-text assertions,
  file-count tests, trivial reversible edit tests and boilerplate per-package
  suites. Do not create an exhaustive app/scope/theme/fault Cartesian matrix.
- Reuse existing relevant tests and fixtures. Do not build a large testing
  framework or CI matrix before working functionality.
- Keep network downloads out of the fast loop. Prepare/cache Flatpak content for
  the stage's real integration gate; do not redownload every iteration.
- Use isolated disposable state/guests and bound every wait. Missing KVM/network/
  graphics evidence is unavailable, never passing. Record actual task outcomes.
- Real sysrepo/subscribers are mandatory for integration claims. Mocks can verify
  translation/controlled failure, not actual activation, capture or physical boot.
- Keep compilers/headers/SDKs in build/development inputs, not user installation
  just to run checks. Prefer pinned existing tools.
- Stage gates specify behavior, not imaginary output names. Record exact working
  commands once implemented. Do not fabricate check commands or silently waive
  a required gate because the environment cannot execute it.

## Handoff

Update the assigned stage/index and report delivered behavior, Sylphy reuse,
actual checks/limits, commit SHA and next stage. No separate report hierarchy.
If blocked, state the exact missing input and complete independent authorized
work. Ordinary implementation choices do not require repeated confirmation.
