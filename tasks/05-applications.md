# Stage 05: Owned Flatpak lifecycle, Zen/OBS and configuration files

Dependencies: 04. Status: complete (2026-10-18).
Expected commit: `feat(applications): reconcile owned flatpak apps and configuration`.

## Execution baseline (2026-10-18)

- Stage 04 passed and was committed as `7af1c09`; the worktree was clean before
  this stage. Continue without development-host activation or reference changes.
- Inspected Sylphy browser preferences and Zen palette/chrome/content renderers,
  OBS integration and PipeWire NixOS adapter at
  `9cba023d90c4485b33a91e2d12724b6920580580`. Adapt the bounded browser-owned
  scopes and preferences; do not migrate the Rust CLI or native OBS/Zen packaging.
- Checked the pinned Flatpak 1.18.4 CLI/manual and upstream command reference.
  `--no-deploy` prepares content; `--no-pull` deploys cached content. Install has
  no `--commit` flag, so fixed-commit initial installation needs explicit local
  ref validation rather than inventing an option. The Zen Flathub manifest uses
  `--persist=.zen`, confirming the sandbox profile root beneath `.var/app/`.
- A completely isolated public Flatpak cache is being prepared beneath the path
  recorded in `/tmp/folio-stage05-cache-root`, with its own HOME/XDG paths, English
  and Chinese locales and no SDK/debug request. Inspect its download log and
  actual repository before claiming it ready; no app is deployed by this step.
- Initial work adds the owned model, adapted CSS/preferences manifest, anchored
  no-symlink regular-file publisher and minimum owned portal/PipeWire prerequisites.
  No lifecycle command is registered until its subscriber/backend is coherent.

## Objective and deliverables

Own applications model, scoped commands/subscriber, Nix generation and task journal.
Deliver real user Flatpak operations and safe regular-file configuration. Add only
the host desktop/device prerequisites needed here; Stage 06 completes that desktop.

## Ordered work

1. Inspect/adapt Sylphy browser settings, Zen themes and OBS integration. Use actual
   Flatpak profile paths and supported interfaces, not whole writable profiles.
2. Model full refs, source/branch/architecture, stable/pinned policies, requested
   commits, selection/config/permissions, and actual app/runtime/extension commits.
   Bootstrap Zen app.zen_browser.zen and OBS com.obsproject.Studio. Initialize
   official Flathub explicitly using --user. Typst remains in terminal via Nix.
3. Implement applications list/install/update/remove/reconcile with its own C
   subscriptions and durable tasks. Persist install/remove selection before task
   submission; failed effects leave visible drift. Stable updates are explicit,
   not timers. Reconcile preserves resolved commits. Require explicit adoption
   before modifying unmanaged installs; preserve unrelated apps/remotes/data.
4. Resolve/download without activation, record actual app/dependency commits,
   revalidate and deploy prepared local content. Changed refs require replan.
   Check final commits; flatpak pin is not version locking. Parse machine-oriented
   columns with fixed locale. No online Flatpak work in Nix evaluation/builds.
5. Serialize app mutations; user-config precedes application locks when both are
   needed. Journal per-app before/after effects, partial success and idempotent
   resume. No atomicity promise across apps, Flatpak or Home Manager.
6. Generate managed-file manifest from frozen desired data. User apply publishes
   and roots it; explicit applications operations atomically materialize regular
   files with hashes and adoption backups. Reject stale digests, traversal,
   symlink destinations, overlapping owners and unexpected edits. Never expose
   the entire Nix store or overwrite a whole writable directory.
7. Zen needs explicit profile selection; missing profiles become configuration-
   pending. Manage supported preference file/namespaced CSS only, preserving
   prefs.js, arbitrary CSS, databases, logins and sessions. Seed three workspaces
   once only if supported. Report restart-required without killing user work.
8. OBS owns scenes, accounts, recording profiles and mutable settings. Manage only
   installation/integration/permissions and supported theme interfaces. Portal and
   PipeWire capabilities stay in desktop/devices. Report unsupported Qt appearance
   rather than claiming GTK establishes parity or overwriting OBS state.
9. Implement applications-owned rollback operation. Preflight availability of old
   app/dependency/extension refs before mutation, otherwise rollback-unavailable.
   Record shared runtime effects; never automatically downgrade/prune runtimes
   used by unmanaged apps. No indefinite offline rollback or NixOS-only restore
   claim. Record its public invocation under the agreed applications CLI root.
10. Update root README for actual install/update/adopt/reconcile/rollback and the
    distinction between user apply, pending manifest and application operations.

## Bounded gate

Use prepared local data for logic/schema/manifest checks. Run one real guest case
with cached Flatpak refs: install both apps, verify actual commits and supported
file delivery, repeat reconcile, preserve unrelated installation/data, reject stale
manifest and handle missing profile/conflicting file. Check one available rollback
and one unavailable preflight without changes. Use controlled failures for partial
progress, not repeated network downloads. Final capture/GUI evidence is Stage 06;
installation alone is not proof of capture or appearance parity.

## Handoff

Record full refs/commits, owned files/profile selection, locks/journal, supported
interfaces, prerequisites and observed limits. Never copy private reference data.

## Completion record (2026-10-18)

- Added the applications-owned YANG model, C RPC/operational subscriber, `folio
  apps` client, pinned independent workers, complete prepare/deploy transaction
  helper and anchored regular-file publisher. Install/remove save selection
  through the public manager configuration adapter. Explicit initialization,
  adoption, permission overrides, status/resume and conservative local rollback
  are implemented. No automatic downloads occur on activation or service startup.
- Public Flatpak content was cached in an isolated HOME/XDG tree. Real commits:
  Zen `7ce097e9b6c826656be4872830a3126e5eebf88a46b0401e87b65dea1403c022`;
  OBS `21b35765922fb5c8b92ccdccedc0d8ca709b12f86a961780350199082da822ef`;
  freedesktop Platform 25.08
  `b7aba340fd291e08bf26442d43a0e4adb6733da5a06d47ff4296a964af40cc8a`.
  Prepared operations also bind actual locale/GL/codecs refs and English/Chinese
  locale subpaths. Public cache and plans are outside the checkout; paths are
  recorded in `/tmp/folio-stage05-cache-store` and `/tmp/folio-stage05-plans-store`.
- The final real guest gate passed at
  `/nix/store/jmfysaabzbyqmw6fhlayps697j33l91k-vm-test-run-folio-owned-applications`.
  Logs: `/tmp/folio-stage05-final-guest-gate3.log` and
  `/tmp/folio-stage05-final-expanded3.log`. Exact invocation:

```sh
nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths --impure --expr '
  let flake = builtins.getFlake (toString ./.);
      trim = path: builtins.replaceStrings ["\n"] [""] (builtins.readFile path);
  in flake.checks.x86_64-linux.applications.override {
    cache = builtins.storePath (trim /tmp/folio-stage05-cache-store);
    plans = builtins.storePath (trim /tmp/folio-stage05-plans-store);
  }'
```

- Verified both actual app commits/dependencies, operational state, repeat
  reconciliation, missing-profile pending state, explicit existing-install
  adoption, a genuine separately exported/installed unmanaged Flatpak and its
  sentinel data, explicit profile regular-file publication, stale manifest
  nonpublication, available retained-plan rollback, unavailable rollback with
  unchanged deployments, owned-file conflict and successful explicit resume
  after resolving the edit. Available rollback reused retained cached commits;
  this is not evidence of an online historical-version download.
- Native file safety and real configuration integration passed as recorded above.
  Reused Stage 04's paired schema recovery evidence; no changed root deployment
  behavior or new hardware claims. No development-host application deployment.
- Limits: initial historical pins need an exact resolvable preparation; local
  missing/changed refs or changed shared runtimes make rollback unavailable.
  Workspace seeding and OBS Qt appearance remain unsupported. GUI rendering,
  screen capture and physical hardware evidence belong to later stages.
- Reviewed commit subject:
  `feat(applications): reconcile owned flatpak apps and configuration`.
  Next: the owner's requested repository-layout correction against STRUCTURE.md,
  then Stage 06. Keep the later root-only product documentation rule.

## Implementation progress (2026-10-18, not a completion record)

- Added a dedicated C subscriber, public `apps` adapter, pinned independent user
  worker, durable request/phase journals, explicit `prepare`/`resume`/`adopt`
  operations, machine-oriented actual inventory, exact local transaction checks,
  conservative shared-runtime policy, scoped permissions and retained revisions.
- Shared configuration adapter is exposed as a public package; install/remove
  commit selection using that API before submitting application work. The manager
  does not route application operations. Offline schema maintenance rejects
  application tasks with pending effects/recovery.
- `nix build --no-link --no-update-lock-file --print-out-paths
  path:.#applications-subscriber path:.#applications-worker path:.#folio
  path:.#checks.x86_64-linux.configuration` passed before the subsequent focused
  guest fixes; log `/tmp/folio-stage05-connected-build.log`. The real existing
  configuration integration output was
  `/nix/store/33ly1kv0mghaaw8b3ai8pw59kcfgryj2-folio-configuration-integration`.
- Default Home Manager activation package built at
  `/nix/store/drx5fzq5l4q7lcgglpvvipjaw4vnaq32-home-manager-generation`, log
  `/tmp/folio-stage05-home-build.log`. Build success is not runtime acceptance.
- Native regular-file checks passed; retained evidence
  `/tmp/folio-application-files.THR6B3`. Both native helpers compile with warnings
  treated as errors. The public cache has complete Zen/OBS/runtime objects and
  online-resolved transaction plans; no application was deployed on this host.
- Actual application guest gate is in progress. Its first run reached real local
  Flatpak deployment but failed the post-deploy inventory comparison. Inventory
  now uses `flatpak info --show-commit` instead of relying on the abbreviated
  `list` active column. See `/tmp/folio-stage05-guest-gate2.log` for the current run.
- After completing this stage, the owner's new required next task is correcting
  all implemented module paths to `STRUCTURE.md`, including CLI/runtime separation
  and affected package/test references, before Stage 06.
