# Stage 00: Repository baseline

Dependencies: none. Status: complete.
Expected commit: `chore(repo): establish implementation baseline`.

## Objective

Provide a normal main-branch repository and reviewable task plan before product
implementation. This stage does not implement Folio modules or activate anything.

## Ordered work

1. Read the index, workflow, reuse map and root documents. Confirm reference paths.
2. Inspect metadata and existing changes. Complete `git init --initial-branch=main`
   once .git is writable. Preserve existing history; never destructively replace
   metadata. Use configured author identity or obtain the real missing identity.
3. Preserve root documents; add this task set and README development entry.
   Product documentation remains root README only; task records are the exception.
4. Add a minimal .gitignore when generated files are introduced. Exclude secrets,
   Nix result links, runtime outputs and protected environment metadata, not all
   JSON, lock files, models or task sources.
5. Review order, dependencies, source pointers, English and Markdown links.
6. Pass the planning gate, explicitly stage intended files and create the initial
   commit. Report its SHA and next stage.

## Acceptance gate

- Every stage has dependencies, ordered work, scope/deliverables, reuse pointers,
  bounded acceptance and an English Conventional Commit example.
- Root README links the plan and accurately reports pre-implementation status.
- Local links and whitespace pass review; git diff --check passes when available.
- Normal Git repository initialized on main with the reviewed baseline commit.
- No dependency downloads, product builds or VM tests for this planning change.

## Planning-session blocker

On 2026-10-18, `git init --initial-branch=main` failed copying the Git template
description into .git with `Read-only file system`. The mounted directory was
empty and read-only. No alternate repository or invented author was used.
Task preparation can finish; initialization and commit remain pending until
normal metadata writes are available. Do not claim the Git criterion passed.

## Planning preparation record

- Status/date: planning files prepared on 2026-10-18; Git gate blocked.
- Delivered: ten ordered stage files, INDEX.md, WORKFLOW.md, SYLPHY-REUSE.md and
  root README development handoff. No product implementation or activation.
- Reference inspected: Sylphy module inventory, root Flake, manager Nix inventory,
  home theming, Foot renderer and relevant application/editor source inventories.
  Reuse pointers are recorded in SYLPHY-REUSE.md; no reference files were changed.
- Validation actually run: a local read-only Python check of all fourteen changed/
  new Markdown files; ten sequential stage IDs; sixteen relative links; required
  dependency/work/gate fields; Conventional Commit examples; Chinese prose scan;
  final newlines and trailing whitespace. All passed. No build or VM tests run.
- Git evidence: initialization failed on the read-only .git directory. No commit
  exists, so git diff --check and staged/branch verification remain unavailable.
- Pending commit subject: `chore(repo): establish implementation baseline`.
- Next action: finish this stage's Git criterion when metadata is writable, then
  assign Stage 01. Do not misrepresent the planning checks as product acceptance.

## Implementation-session update (2026-10-18)

- `git init --initial-branch=main` now succeeds in the normal `.git` directory.
- `git var GIT_AUTHOR_IDENT` fails with `Author identity unknown`; neither
  `user.name` nor `user.email` is configured. No identity was invented.
- The initial commit remains blocked. Independent foundation work may be
  prepared and tested, but no later stage is marked complete before this gate.
- Existing AGENTS.md is preserved. Protected environment metadata and generated
  images/results/logs are excluded through the root .gitignore.
- The owner supplied `WallyHao <wallyhao@qq.com>` during this session. Repository-
  local Git author configuration now uses that identity; `git var GIT_AUTHOR_IDENT`
  succeeds. The earlier identity blocker is resolved.
- Baseline validation: reviewed task order/dependencies and reference paths;
  `git diff --check` passes; branch is `main`. Baseline sources are explicitly
  staged separately from the foundation implementation under preparation.
- Commit subject: `chore(repo): establish implementation baseline`. The resulting
  SHA is recorded in the next stage's handoff, without a self-referential amend.
- Next stage: 01, fixed libraries, pure composition and isolated repositories.
