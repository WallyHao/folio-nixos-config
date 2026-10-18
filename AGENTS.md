# Repository Guidelines

## Project Structure & Module Organization

Folio is a planned NixOS configuration framework using module-owned YANG models
and sysrepo. This checkout currently contains design documents and task plans;
implementation directories and build entry points do not exist yet.

- `README.md`: authoritative architecture, contracts, and product documentation.
- `STRUCTURE.md`: planned layout reference.
- `tasks/INDEX.md`: implementation stages and dependencies.
- `tasks/WORKFLOW.md` and `tasks/SYLPHY-REUSE.md`: execution rules and reuse guidance;
  read both before implementing a stage.

Planned code lives in `modules/<capability>/`, with `model/`, `src/`, `cli/`,
`runtime/`, and outer `tests/` directories as needed. Shared images belong in
`assets/`. Keep one root `flake.nix` and `flake.lock`; composition belongs in
`modules/manager/src/outputs.nix`. Do not create empty scaffolding or separate
host/home trees. Maintain product documentation in the root README.

## Build, Test, and Development Commands

No build or development commands are runnable until the root Flake is implemented.
Once corresponding outputs exist, use:

- `nix develop`: enter the default development shell.
- `nix build .#folio`: build the CLI package.
- `nix build .#checks.x86_64-linux.<name>`: run a specific implemented check.
- `git diff --check`: check patch whitespace when Git metadata is available.

Record exact working commands in the relevant task record; do not claim planned
checks have passed.

## Coding Style & Naming Conventions

Use English for source, comments, help, errors, tests, and task records. Follow
surrounding indentation; no formatter or indentation standard is established yet.
Use Bash, jq, and sysrepocfg for CLI code, and C with libsysrepo/libyang for
subscribers. YANG models use `folio-<capability>`, `urn:folio:<capability>`, dated
revisions, and kebab-case nodes. Keep private implementations within their module.

## Testing Guidelines

No test framework, filename convention, or coverage threshold is mandated. Place
behavioral tests in the owning module's `tests/`. Batch related changes, run
affected checks, then the stage acceptance gate. Integration claims require real
sysrepo/subscribers; activation and power tests use disposable guests. Build
success alone does not establish runtime health.

## Commit & Pull Request Guidelines

Git history is unavailable in this checkout. The documented convention is English
Conventional Commits: `type(scope): imperative description`, for example
`feat(manager): apply frozen user configuration`. Stage commits follow passing
gates on `main`. Review intended diffs and stage explicit paths.

No PR template is established. Describe behavior, affected stage, actual
validation, and remaining limitations. Preserve unrelated work and exclude
credentials, private application data, runtime state, and build outputs.
