# Open Tasks

Updated: 2026-10-20

This tracker records remaining work reported by the user or supported by the
current README and source.
It is not a fresh acceptance report. Remove completed items after verification.
Historical task documents have been removed; their absence does not mean their
implementation stages are incomplete.

## User-confirmed remaining work

Reported by the user on 2026-10-20, in the supplied order:

- [ ] Complete Emacs personalization.
- [ ] Complete Pi personalization.
- [ ] Complete the knowledge base migration.

## Confirmed remaining work

- [ ] Complete physical acceptance of the shared `folio` USB system on both the
  Lenovo Legion Y7000 IRX9 and MSI MAG B650M MORTAR WIFI desktop. Verify boot,
  display/output selection, networking, audio, Chinese input, OBS capture,
  suspend/resume, shutdown and moving the disk between machines. Keep a working
  generation and record results per machine. VM checks do not establish this.
- [ ] Verify the ESP removable fallback loader on the USB disk, including boot
  through each machine's UEFI USB boot menu.
- [ ] Validate integrated-GPU rendering, discrete-GPU power saving and required
  application compute environments on physical hardware. The base desktop does
  not supply a CUDA SDK; add one only if the intended workloads require it.
- [ ] Verify exact desktop/application GUI parity against the intended setup;
  isolated guest acceptance does not establish full parity.
- [ ] Implement the proposed intelligent apply workflow. The current CLI requires
  explicit plan, build and apply operations with a plan ID.
- [ ] Implement the proposed unified history/rollback interface. Existing managed
  deployment rollback and application rollback remain separate capabilities.
- [ ] Complete physical acceptance of the web panel's Wi-Fi, proxy,
  audio and brightness controls with the matching installed backend/model.
- [ ] Repair stale README links to removed `STRUCTURE.md`, `tasks/INDEX.md`,
  `tasks/WORKFLOW.md` and `tasks/SYLPHY-REUSE.md`; reconcile the old handoff text
  with the current repository layout and this tracker.

## Status to confirm before treating as unfinished

- [ ] Confirm account/home migration and legacy-system retirement from their
  retained journals and actual state. The running system is named `folio` and
  `/home/sylphy` is absent, so do not repeat migration based on old README wording.
  Verify login, password/keyring synchronization and preserved application sessions
  if their acceptance has not already been recorded.

## Deferred scope, not current commitments

- Fresh physical installation/image workflow: the current `folio` target expects
  the existing migrated USB installation.
- Secure Boot enrollment/signing, enterprise/legacy Wi-Fi, external-monitor
  DDC/CI controls and automatic application updates are not currently provided.
- Additional module documentation is deferred until its scope is confirmed.

## Evidence and maintenance

- Sources: `README.md` sections on hardware targets, account/home migration,
  legacy compatibility retirement, local web panel and CLI deployment contracts.
- Keep this file focused on remaining work; retain verification in the README,
  relevant checks or deployment records when removing completed items.
- When implementation or desired configuration changes after a plan is created,
  create a new plan: existing plans bind an immutable source/configuration snapshot.
