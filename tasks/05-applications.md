# Stage 05: Owned Flatpak lifecycle, Zen/OBS and configuration files

Dependencies: 04.
Expected commit: `feat(applications): reconcile owned flatpak apps and configuration`.

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
