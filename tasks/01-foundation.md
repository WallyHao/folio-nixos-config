# Stage 01: Flake, model and repository foundation

Dependencies: 00. Status: complete.
Expected commit: `feat(core): establish flake and modeled repositories`.

## Objective and deliverables

Build a reproducible bootstrap without a running Folio service. Own root Flake/
lock, manager composition/models and sysrepo packaging/initialization. Introduce
only the system/terminal pieces needed by the first vertical slice.

## Ordered work

1. Inspect Sylphy dependency pins/composition and Foot renderer. Select compatible
   fixed sysrepo/libyang versions and verify APIs against selected source rather
   than guessing. Reuse applicable dependency/package definitions.
2. Delegate root outputs to modules/manager/src/outputs.nix. Implement explicit
   catalogue and README's optional outputs/adapter context. Reject unknown modules,
   unsupported scopes, duplicate commands and conflicting model names/revisions.
   No recursive manager entry/bootstrap dependency or mutable repository query.
3. Export applicable packages, minimal portable system and standalone folio home,
   development shell and existing checks. Expose folio as its package becomes
   buildable; incomplete runtime commands remain unavailable rather than fake.
4. Define folio-environment/folio-deployment roots and initial terminal augmentation.
   Separate config/operational nodes. Model identity, selections, preferences,
   commit inputs/results, plans/tasks and errors with dated YANG revisions.
5. Package scoped sysrepo wrappers, persistent/runtime paths, separate shared-memory
   prefixes and ownership. Prove pinned libraries support root and user instances.
   Install full applicable model import closure with correct scope permissions.
6. Generate versioned defaults for portable/x86_64-linux and folio. Import only
   into new repositories. Existing desired values must survive restart/rebuild.
   Do not maintain a second editable JSON/Nix settings store.
7. Establish the frozen input format consumed by pure Nix. Normalize using libyang
   RFC 7951 JSON, deterministic object keys, correct list semantics and numeric
   encoding. Record model/tool identities and the digest procedure.
8. Establish read-only versioned system descriptor fields/digest. Bootstrap values
   precede real publication in Stage 03. Identity/privilege are not user-overridable
   preferences; declared capabilities do not prove observed health.
9. Update root README for actual outputs/development/bootstrap and current limits.
   Do not create empty module/doc/test trees or module README files.

## Reuse and scope limits

Use the manager/system/terminal rows in SYLPHY-REUSE.md. Adapt useful legacy
helpers, not the old source-registration/host/home architecture. Storage is an
explicit disposable fixture until an actual physical target is supplied.

## Bounded gate

Evaluate affected root outputs with sysrepo stopped; build pinned libraries and
initial package/model closure once. Validate schemas/defaults with real pinned
tools. Initialize isolated instances and prove separation plus non-overwrite of
edited desired values on restart. One focused contract check covers representative
unknown-module, duplicate-command and invalid-scope failures. No desktop VM yet.

## Handoff

Record versions, wrappers/permissions, schema revisions, frozen format, digest,
descriptor and exact commands/results. Stage 02 must consume public facts without
reverse engineering private implementation.

## Completion record (2026-10-18)

- Baseline prerequisite: `e9aa62e` on `main`; author configured from the owner's
  supplied `WallyHao <wallyhao@qq.com>` identity.
- Delivered: root Flake/lock; explicit manager/sysrepo/system/terminal catalogue;
  optional module exports, scope/collision checks, bootstrap models/defaults,
  pinned libraries, repository maintenance wrappers, normalizer, frozen input
  format and minimal pure system/home outputs. No runtime deployment claims.
- Sylphy reference: `9cba023d90c4485b33a91e2d12724b6920580580`. Reused its root
  dependency pins and `modules/foot/src/config.nix`; inspected selected values in
  `home/sylphy/default.nix`, shell/theming/theme files, and manager home-authority
  and portable defaults. Adapted diagnostics and public preference inputs; Foot
  uses Maple Mono NF CN size 16 and padding 15x15. Reference remained unchanged.
- Versions: sysrepo 3.7.11 built from fixed upstream source; libyang 3.13.6 from
  pinned Nixpkgs. Verified upstream CMake compatibility (libyang >= 3.13.2),
  actual instance environment-variable names and CLI options from that source.
- Schema revisions: all initial Folio models use 2026-10-18. System has manager
  roots; user additionally has terminal augmentation. Bootstrap identity is
  portable/x86_64-linux/folio. Models are available independently of selection.
- Exact passing commands:
  - `nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths path:.#checks.x86_64-linux.catalogue path:.#checks.x86_64-linux.foundation`
  - `nix eval --no-update-lock-file --raw path:.#nixosConfigurations.portable.config.system.build.toplevel.drvPath`
  - `nix eval --no-update-lock-file --raw path:.#homeConfigurations.folio.activationPackage.drvPath`
  - `bootstrap_path=$(nix build --no-link --no-update-lock-file --print-out-paths path:.#packages.x86_64-linux.manager-bootstrap)`
  - `nix develop --no-update-lock-file path:. --command bash modules/sysrepo/tests/scopes.sh "$bootstrap_path"`
  - `nix develop --no-update-lock-file path:. --command bash modules/manager/tests/prepared.sh . "$bootstrap_path"`
  - ShellCheck on all five Shell sources/tests, Nixfmt on Nix sources, and
    `git diff --check` passed.
- Foundation evidence: `/nix/store/0wway397psvj9w73izm2rqhcqlkxl1l8-folio-foundation`;
  catalogue evidence: `/nix/store/8nhk87cpdy591c0ngmz5bjj728ihb4s9-folio-catalogue-contract`.
  Nix logs retain actual schema rejection and persistence/isolation results.
  Namespace test verified UID 0 library use and separate root/user paths/prefixes;
  normal foundation build tested ordinary unprivileged repository ownership.
- Frozen format 1: libyang RFC 7951 output with defaults; jq compact sorted object
  keys and only schema-known system lists sorted, one trailing LF, SHA-256.
  Input records scope/configuration, model source hashes, tool versions and a
  descriptor with its own digest. Pure Nix checks the identities and digests.
- Bootstrap descriptor is versioned/read-only store data with explicit bootstrap
  origin and no claimed capabilities. Stage 03 must publish real system facts.
- Repository wrappers fix scope paths and prefixes, use process ownership and
  private initialization permissions, refuse schema/library changes, and never
  reimport defaults into an initialized repository. Restart after the install/
  marker boundary also preserves accepted startup values.
- Limits: no Folio subscriber/CLI/services, source snapshot copier, activation,
  system deployment or schema-upgrade executor yet. No host or guest activation.
- Commit subject: `feat(core): establish flake and modeled repositories`.
- Next: Stage 02 consumes the exported bootstrap, normalizer/input packages and
  pure prepared-input interface to implement durable configuration/deployment.
