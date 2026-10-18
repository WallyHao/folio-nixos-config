# Folio implementation task index

This is the implementation handoff requested by the project owner, not a new
product documentation hierarchy. All development must use English, including
source comments, help, diagnostics, tests, task records, and commit messages.
Preserve upstream identifiers and functional input-method data; do not introduce
Chinese prose or localized CLI output.

## Read first

1. Read root README.md for the architectural baseline.
2. Read [WORKFLOW.md](WORKFLOW.md) for execution, testing, Git and reporting rules.
3. Read [SYLPHY-REUSE.md](SYLPHY-REUSE.md) before implementing existing behavior.
4. Read the assigned stage and its prerequisite completion records.
5. Consult root STRUCTURE.md for planned ownership and paths. Its examples of
   module READMEs and docs trees are deferred by the owner's later instruction:
   maintain product documentation only in root README.md. Do not expand that
   structure document or create module guides or explanatory AGENTS.md files.

The owner's later language, reuse, testing, documentation and commit requirements
take precedence over conflicting older examples. Resolve routine implementation
choices locally without replacing the specified architecture.

## Current state

- Planning date: 2026-10-18.
- Product implementation: foundation preparation underway; no installed or activated Folio system.
- Product documents: README.md and STRUCTURE.md.
- Reference checkout inspected: /home/sylphy/Workspace/sylphy-nixos-config.
- Normal Git initialization on `main` succeeds. The owner supplied the real Git
  identity during implementation; the repository-local author is configured.
- Stage 00 baseline is reviewed and committed independently of foundation code.

## Ordered stages

Statuses: pending, in-progress, blocked, complete. Complete requires the stage's
acceptance gate and its implementation commit. Work items are not instructions
to run the full suite or create a commit after each checkbox.

| Stage | Task | Dependencies | Status | Deliverable |
| --- | --- | --- | --- | --- |
| 00 | [Repository baseline](00-repository-baseline.md) | None | complete | Normal main repository and reviewed baseline |
| 01 | [Foundation](01-foundation.md) | 00 | in-progress | Pure Flake composition, models, isolated repositories |
| 02 | [User Foot deployment](02-user-foot.md) | 01 | pending | Actual user config/build/apply vertical slice |
| 03 | [System and VM](03-system-vm.md) | 02 | pending | Authorized passwordless guest system updates |
| 04 | [Recovery and rollback](04-recovery.md) | 03 | pending | Fault recovery, migrations, managed rollback |
| 05 | [Applications](05-applications.md) | 04 | pending | Owned Zen/OBS lifecycle and regular-file delivery |
| 06 | [Desktop](06-desktop.md) | 05 | pending | Niri, appearance, input, devices, capture |
| 07 | [Developer tools](07-tools.md) | 06 | pending | Terminal, Git, Emacs, Codex migration |
| 08 | [Network and system](08-network-system.md) | 07 | pending | Remaining modeled connectivity and system policy |
| 09 | [Acceptance](09-acceptance.md) | 08 | pending | Integrated guest evidence and separate hardware evidence |

Main path: 00 -> 01 -> 02 -> 03 -> 04 -> 05 -> 06 -> 07 -> 08 -> 09.
Stage 03 introduces only network/device/system prerequisites needed for its VM.
Stage 05 introduces only desktop/portal prerequisites needed for applications.
Stages 06 and 08 complete those same modules; never create parallel replacements.

Each stage can be assigned to one AGENT. Its ordered work items are implementation
steps, not separate agents or mandatory commits. Respect the owner's assigned
scope and existing work. Do not start later stages to avoid fixing a failed gate.
Continue independent work within a stage when an external prerequisite is blocked.

## Completion record

Append the following to the assigned task and update this index at delivery:

- Status and date:
- Completed work items and changed paths:
- Sylphy files inspected/reused, source revision if available, adaptations:
- Commands actually run, outcomes and evidence locations:
- Relevant prior checks reused without rerunning, revision and justification:
- Unavailable evidence, limitations or exact blocker:
- English Conventional Commit subject and resulting SHA:
- Next stage and public interface facts it needs:

A commit cannot contain its own final SHA. Put its subject in the staged record,
report its SHA in the handoff, and let the next normal stage record that prior
SHA. Do not amend just to insert a self-referential SHA. Mark an implementation
stage complete only after committing its passing gate; correct status if commit
creation fails. Stage 09 explicitly separates its VM and hardware milestones.
