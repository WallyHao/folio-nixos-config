# Stage 01: Flake, model and repository foundation

Dependencies: 00.
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
