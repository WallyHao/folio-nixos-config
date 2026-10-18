# Implementation Handoff

## Session quota policy (codex2, 2026-10-18)

- The user requires continued implementation, with a pause when the codex2
  five-hour quota falls below 5%, then continuation after quota recovery.
- Current account home is `/home/sylphy/.codex-account2`; do not use the other
  account's telemetry. Local checker: `/tmp/folio-codex2-quota/check.sh`, bound to
  this session. It reads only session rate-limit events, not authentication data.
  Run it periodically and before expensive work. Exit 75 means pause; 76 means
  reset time passed but fresh telemetry must confirm recovery. A reset timestamp
  alone does not establish renewed quota. Keep the conversation active while
  waiting, with bounded sleeps, rather than ending and promising a scheduled wake.
- Last observed remaining quota: 38%; reset 2026-10-19 02:27:46 Asia/Shanghai.
- Stage 05's completion record below supersedes the initial incomplete boundary.
  Both native helper packages compile;
  regular-file safety checks passed using
  `/nix/store/vi7wz7hw3gwymj13772c2pphb42b8x75-folio-applications-files-0.1.0/bin/folio-applications-files`.
  Evidence: `/tmp/folio-application-files.THR6B3`. Continue the worker, public
  subscriber/CLI wiring and bounded real guest gate are now complete.

## Required next boundary: restore the agreed layout

The owner explicitly requested completion of the current Stage 05 first, followed
by correction of all implemented module layouts to `STRUCTURE.md`, before moving
on to later stages. Read that file in full. In particular, keep Nix implementation
in `src/`, client adapters/resources in `cli/`, and C subscribers/Shell operations
in `runtime/`, with outer `tests/`. Current manager, sysrepo, system, VM and
applications files mix these categories under `src/`; this must be corrected,
including package/source/test references. Preserve working behavior and avoid
empty placeholder trees. The later root-only product documentation rule remains
applicable: do not add module READMEs or a documentation tree merely to match the
older example. Record and validate the actual moved paths and CLI contracts.

## Stage 05 completion boundary (2026-10-18)

Stage 05 passed its real guest gate; see `tasks/05-applications.md` for exact
invocations and limits. Commit subject:
`feat(applications): reconcile owned flatpak apps and configuration`.
The final guest output is
`/nix/store/jmfysaabzbyqmw6fhlayps697j33l91k-vm-test-run-folio-owned-applications`.
Actual two-app deployment, real operational state, explicit adoption, preservation
of an independently installed local Flatpak, regular files/profile/pending/stale
manifest behavior, retained/unavailable rollback and conflict/resume passed.
Keep caches/plans outside source and reuse them for affected integration checks.
The next work is the layout correction above, not Stage 06 yet. Do not retain the
current mixed `src/` arrangement as the final architecture.

## Stage 04 completion boundary (2026-10-18)

This section supersedes all historical boundaries below. Stage 04 is complete;
continue Stage 05 applications. See its completion record for exact commands and
evidence. Submilestone `54beb78` preceded the final stage commit; obtain the latest
SHA from Git rather than interpreting the old uncommitted-work table below.

- Implemented terminal revision 18 -> additive percent revision 19 -> unit-fraction
  revision 20, with model-owned hash-bound transforms and preserved old models.
- Implemented `folio rollback REVISION_ID [--rebuild]`, offline journal status and
  `folio cleanup [--apply]`. System offline maintenance requires root. Rebuild
  preserves old models/adapters/lock and must prove a supported worker protocol
  and retained identities; mismatch remains unavailable.
- Root/user paired restoration, real schema migration with activated Foot,
  unsupported-protocol rejection/rebuild/rollback after a newer failed desired
  value, real reboot preservation and explicit cleanup passed the scoped VM gate:
  `/nix/store/jl782y0ysgvbjikq6qzi7jb3krv8kmiw-vm-test-run-folio-deployment-recovery`.
  Logs `/tmp/folio-stage04-complete-gate2.log` and
  `/tmp/folio-stage04-complete-expanded.log`. Isolated percent 75 -> fraction 0.75,
  failure and protected-cleanup evidence is in `tasks/04-recovery.md`.
- Still no development-host activation, physical acceptance, application or desktop
  implementation. Preserve private data and the read-only Sylphy reference.
- The final stage subject is
  `feat(manager): recover deployments and restore retained revisions`.

## Historical offline maintenance boundary (2026-10-18)

This section supersedes the historical incoming handoff below. Stage 04 remains
in progress; do not start 05 yet. The incoming uncommitted maintenance work has
been continued with a manager-owned offline coordinator and focused integration.
See `tasks/04-recovery.md` for exact commands, actual evidence and limits.

- New entry point: `folio-manager-maintain SCOPE BOOTSTRAP snapshot|upgrade|restore
  ID [FROZEN_SOURCE]`, packaged in `manager-runtime`. BOOTSTRAP comes from the
  selected closure's metadata. Never run its activation paths on the development
  host. It quiesces registered consumers, builds as the scoped user/builder,
  validates paired identities and restores data/models/closure together.
- Repository primitives now retain incomplete candidates on explicit preparation
  retry and validate bound closure scope/account/bootstrap/configuration. A changed
  schema without a revision, a failing hash-bound test transform and invalid
  closure binding were actually rejected using real isolated repositories.
- Scoped guest gate passed at
  `/nix/store/6rxa51zzrs5d1ids8f6f4cpj4dr126rk-vm-test-run-folio-deployment-recovery`;
  log `/tmp/folio-recovery-paired-gate7.log`. Includes both scopes' paired restore,
  failed root restore/barrier/retry, a real root candidate install and healthy
  publication/restore, plus the existing bounded recovery/system assertions.
- Important fixes: runtime masks do not override the generated `/etc` units;
  journaled runtime ConditionPathExists drop-ins block consumers through
  activation. The JSON datastore writes with the caller's primary group; system
  candidates use `setpriv --regid folio-operators --keep-groups` and umask 0007.
  Optional not-found consumer services are not errors. Restart success requires
  real RPC readiness after releasing the mutation lock.
- Final package compilation (after reusing the snapshot identity check before
  restore activation) passed:
  `/nix/store/r6qvqkzai04nyybs8sy13bcnwmn75jxj-folio-manager-runtime`.
  See the task record for why the prior guest evidence was reused for this final
  additional validation. Foundation/configuration/catalogue and isolated primitive
  gates also passed; no full flake check was run.
- Still open: production module-owned additive/meaning-changing migrations,
  general retained-revision rollback with unsupported-protocol rebuild, explicit
  reference-aware cleanup and the full Stage 04 completion gate. The production
  migration registry remains empty; no later-stage implementation is claimed.
- Reviewed submilestone subject:
  `feat(manager): coordinate offline paired repository recovery`.
  Obtain its SHA from `git log`; preserve any later unrelated work.

## Historical incoming handoff (superseded by the section above)

Updated: 2026-10-18, 13:21 UTC. The owner requested a handoff to another agent.
Implementation is stopped at this boundary; preserve the uncommitted work below.

## Start here

Read `AGENTS.md`, root `README.md`, `tasks/WORKFLOW.md`,
`tasks/SYLPHY-REUSE.md`, `tasks/INDEX.md` and `tasks/04-recovery.md` before editing.
The existing `AGENTS.md` must not be overwritten. Continue stages in dependency
order; do not skip recovery to start applications or desktop work.

- Repository: `/home/sylphy/Workspace/folio-nixos-config`, branch `main`.
- Local Git author: `WallyHao <wallyhao@qq.com>`; the owner reports gh is logged in.
- Communicate with the owner in Chinese; source, comments, help, tests, task records
  and commits stay English. Resolve routine choices without consulting the owner.
- Product documentation belongs only in root README; task/handoff files are the
  planning exception. Do not add module guides or empty scaffolding.
- Never activate Folio on the development host, invoke host power operations,
  modify the Sylphy reference, push, or claim physical hardware acceptance.
- Do not spawn agents unless explicitly authorized. This handoff requests no
  background agent or continued work from the outgoing agent.

## Completed and committed

There are ten stages, numbered 00–09. Stages 00–03 are complete; 04 is in progress;
05–09 have not started. The latest implementation commit is `839e8d9`.

| Commit | Delivered behavior |
| --- | --- |
| `e9aa62e` | Stage 00 repository baseline |
| `a5bded7` | Stage 01 root Flake, models, isolated repositories |
| `9add07f` | Durable user configuration submilestone |
| `359aea1` | Stage 02 real user Foot build/apply |
| `010dff7` | Root/user service provisioning and actual descriptor |
| `9c0e62a` | Stage 03 authorized system deployment, UEFI image, VM lifecycle and power |
| `839e8d9` | Stage 04 effect-reconciliation submilestone; not full Stage 04 completion |

The committed framework uses one Flake/lock, explicit catalogue and module-owned
YANG/C subscribers. CLI operations use Bash/jq/sysrepocfg. User and root have
separate sysrepo instances, profiles and mutation locks. Plans capture immutable
source/configuration/descriptor identities; transient workers survive subscriber
restart. Builds do not imply application or runtime health.

Stage 03 verifies real UEFI boot, unprivileged `folio-builder` builds, fixed root
activation, actual UTC change, independent user generation, authorization/payload
rejection, changed boot ID and externally observed clean shutdown. The VM module
has its own RPC/subscriber, async builds, direct QEMU/KVM/OVMF, private overlays,
bounded ACPI shutdown and explicit log-preserving cleanup. The prototype account
is `folio`, UID 1000, HOME `/home/folio`, password `kl;'`; it is not the host user.
The image exposes its immutable source through `/etc/folio/source`.

`839e8d9` adds before/profile-selected/activation-returned checkpoints and retained
`deployments/revisions/` records with configuration/model/tool/closure identities.
Startup can finish a verified successful publication or restore only a profile
when actual effects already match the before closure. Ambiguous effects and
failed restoration remain visible, degrade health and block further applies.
Activation is never blindly repeated. Explicit rollback and migration remain open.

## Current uncommitted work

These changes belong to Stage 04 and are deliberately **not committed**. They
compile, but their new maintenance integration script has **not been run**.

| Paths | Work in progress |
| --- | --- |
| `modules/sysrepo/src/maintenance.sh` | Offline snapshot, prepare, bind, install, restore, finalize and inspect primitives |
| `modules/sysrepo/src/quiescent.c` | Checks real whole-file POSIX connection locks using `F_GETLK`, without opening a damaged repository |
| `modules/sysrepo/tests/maintenance.sh` | Isolated real-repository test, ready to run; no host profile selection or activation |
| `modules/sysrepo/default.nix` | Packages the maintenance tool and kernel-lock helper |
| `modules/sysrepo/src/repository.sh` | Shared repository lock and schema-transaction barrier |
| Manager/system/VM subscriber C files | Hold a shared repository lock for each subscriber lifetime |
| Manager catalogue/outputs and module defaults | Public subscriber registry, migration registry and injected public helper packages |

The catalogue now accepts optional `subscribers` and `migrations`; bootstrap
outputs include `subscribers.json` and `migrations.json`. The registry currently
contains **no migration transforms**. No production YANG revision was changed.

Maintenance uses the fixed scoped paths. Snapshots preserve raw repository,
startup/running exports, model identity, configuration journal and closure/bootstrap
GC roots. Preparation installs and validates an isolated candidate. Installation
checks that both live datastores still match the snapshot. A global
`schema-transaction.json` guards incomplete swaps. Restore supports an absent live
repository at the directory-swap boundary. Successful primitives do not establish
paired closure activation or deployment health.

Important unfinished responsibilities:

- A manager-owned offline coordinator must stop/restart registered consumers,
  reject active tasks/pending recovery, maintain lock order, build/validate the
  candidate closure and restore both repository and closure on failure.
- `bind` currently checks only an immutable directory; it does not establish the
  artifact's scope, account, model identity or configuration digest. The test uses
  bootstrap as a stand-in root reference because it tests repository primitives.
- `finalize` is a coordinator acknowledgement, not an activation verifier. Do not
  expose these primitives as a completed public deployment workflow.
- Harden incomplete preparation/retry states and cleanup. A partial candidate can
  remain after failure; retain evidence rather than deleting backups implicitly.
- Add actual module-owned, hash-bound YANG revision migrations: an additive change
  and a meaning-changing transformation. Reject changed schemas without revisions.
- Implement managed rollback restoring matching desired data/models/closure;
  unsupported old worker protocols need a rebuild with a supported protocol.
- Implement explicit cleanup that excludes active tasks, current/previous success,
  recovery/upgrade references and unmanaged-file adoption backups.
- Prove failed migration/restoration and one scoped root recovery case before the
  Stage 04 completion commit. Do not mark 04 complete based on compilation.

The intended coordinator can keep the same mutation-lock open file description
on FD 9 across maintenance phases; the engine recognizes that inherited FD.
Repository lock FD 5 is exclusive only for repository mutations; finalize/inspect
do not need it. The engine checks pinned sysrepo connection locks in addition to
cooperative locking. Inspect lock ordering carefully when adding the coordinator.

## Immediate next commands

Latest package compilation passed:

```sh
nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths \
  path:.#manager-bootstrap path:.#sysrepo-tools \
  path:.#sysrepo-maintenance path:.#manager-runtime
```

Run the pending isolated primitive test using those exact built outputs:

```sh
bash modules/sysrepo/tests/maintenance.sh \
  /nix/store/11ffiizjcz07ixan9vpsv6yzbd5p5ncc-folio-bootstrap \
  /nix/store/lc5zb32lw5kihmaawarm86b3d1mp710s-folio-repository \
  /nix/store/b2dva6yb0744sxv5ix017j5mym64a3ds-folio-repository-maintain \
  /nix/store/6f3nm8f6x7qsfyzw2ljvw1chylrcqw8f-folio-manager-runtime
```

The script retains `/tmp/folio-repository-maintenance.*` evidence. It tests an
active subscriber refusal, candidate preparation, stale-snapshot refusal, install
barrier, denied restoration and a missing-live-directory restore. It does not test
schema transformation or real closure activation. Fix failures before claiming it
passed. New shared-lock changes also require affected configuration/foundation and
scoped guest checks when the feature is coherent; avoid full-suite repetition.

## Passing evidence to reuse accurately

| Check | Evidence and log |
| --- | --- |
| Stage 03 final system gate | `/nix/store/56la33g302kc9nfjc9fzhbb7y4axp28r-vm-test-run-folio-system-deployment`; `/tmp/folio-stage03-release3.log` |
| Final Stage 03 image | `/nix/store/vi0iha821incrk5df3a19gj5pssdqyh2-folio-uefi-image`; `/tmp/folio-vm-image-release.log` |
| Real VM lifecycle | `/tmp/folio-vm-lifecycle.clhezc`; `/tmp/folio-vm-lifecycle.log` |
| Effect recovery VM | `/nix/store/93fici1da0gkams85a38bgkq2xpnpsk0-vm-test-run-folio-deployment-recovery`; `/tmp/folio-recovery-effects-gate2.log` |
| Atomic/configuration recovery | `/nix/store/djfi89fs8dsj1hwf31s9ygphjr2f7pyr-folio-configuration-integration`; `/tmp/folio-recovery-atomic-gate.log` |
| Current WIP package compilation | `/tmp/folio-maintenance-build2.log`, `/tmp/folio-maintenance-test-packages.log` |

Earlier passing gates precede the uncommitted maintenance/shared-lock changes;
they are not evidence that this WIP integration already passes. Full earlier
commands, boot IDs and profile evidence are in stages 02–04 task records.
`git diff --check` passed at handoff. No Nix build or QEMU process was observed
running when the handoff was inspected; prior tool session IDs may be stale.

## Lessons that prevent expensive regressions

- Offline VM seeds must import outputs from the **same frozen source** as guest
  plans, not import the development tree while merely overriding `self.outPath`.
  `/etc/folio/source` makes that difference affect the system closure. The corrected
  fixture is `modules/manager/tests/system-deployment.nix`.
- Seed output closures and pinned inputs, not whole derivation dependency graphs.
  Guest gates disable substitutes/network intentionally; an incorrect seed once
  tried rebuilding hundreds of dependencies. Do not solve that by broad downloads.
- systemd active state precedes subscriber readiness. Probe real RPC availability
  after reconciliation, as `modules/manager/tests/recovery.py` does.
- Pinned sysrepo callback `sr_session_get_user` identifies the subscriber, not the
  requester. Authorization uses real sender module permissions and kernel access;
  do not invent caller identity from JSON or originator fields.
- Opaque anydata can lose singleton-list/scalar shape. Configuration commit uses
  a JSON-text leaf and VM RPC uses `result-json`; manager recovery status uses a
  keyed map. Preserve exact shapes when extending RPCs, with explicit schema
  migration rather than silently changing installed model identity.
- Sources/models remain immutable through evaluation. Initialization refuses
  changed model/library identities; never replace that with an implicit hot upgrade.
- Keep long-lived workers and all recovery inputs rooted. Never infer runtime
  success from a build, accepted power request or selected profile alone.

## Reference and remaining stages

Read-only reference: `../sylphy-nixos-config`, inspected revision
`9cba023d90c4485b33a91e2d12724b6920580580`. Relevant reuse includes Foot renderer,
Everforest dark/hard preferences, Maple Mono NF CN size 16, padding 15x15,
`manager/scripts/home-authority.py`, `manager/nix/adoption.nix`, VM/image helpers
and account provisioning. Do not port its Rust manager or host/home architecture.
Root Flake pins were reused; sysrepo is 3.7.11 and libyang is 3.13.6.

After the full Stage 04 gate and commit, continue 05 applications, 06 desktop,
07 developer tools, 08 network/system and 09 integrated acceptance. Hardware
acceptance remains separate and requires an actual target. The overall task is
unfinished; the owner was told that remaining work is substantial.
