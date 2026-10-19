# Implementation Handoff

## Current state (2026-10-19)

The owner explicitly resumed implementation after the earlier handoff. Stages
00–06 have passed their gates; Stage 06 is ready for its implementation commit.
Stage 07 is next; Stages 07–09 are not implemented. Physical acceptance remains
separate and no development-host activation is authorized.

Read README.md, STRUCTURE.md, tasks/WORKFLOW.md, tasks/SYLPHY-REUSE.md,
tasks/INDEX.md and the assigned stage before changes. Preserve Nix in `src/`,
Bash clients/resources in `cli/`, C/Shell runtime in `runtime/`, YANG in `model/`
and behavioral tests in outer `tests/`. Product documentation stays in root
README. Keep English authored prose/code/task records. Do not launch subagents
without explicit authorization, modify the reference checkout, or push Git.

## Baseline and change scope

Branch: `main`. Prior committed baseline: `3270914`.

- `7af1c09`: Stage 04 recovery, migrations, rollback and protected cleanup.
- `e3ab28a`: Stage 05 owned Zen/OBS Flatpak lifecycle and regular-file delivery.
- `3270914`: required directory correction, with application/recovery guest gates.
- Stage 06 subject: `feat(desktop): integrate sylphy desktop preferences and devices`.
  Record its actual resulting SHA after commit; do not amend for a self-reference.

Stage 06 integrates module-owned appearance, input, desktop and devices:
Everforest/GTK, Maple Mono NF CN, GoogleDot-Folio cursor, preference origins;
Fcitx5/Rime Ice, public no-clobber regular-file defaults, C/GIO language observer;
Niri/greetd/portals, Waybar/Mako/Fuzzel/clipboard/screenshots; actual device
observations and bounded typed controls through a user-owned subscriber.
The manager explicitly composes these modules and public resources. A private
captured-source permissions fix supports planning immutable store sources.
No Panel, Noctalia, Neovim, private profiles or Rust manager/CLI was imported.

Sylphy reuse revision: `9cba023d90c4485b33a91e2d12724b6920580580` in
`../sylphy-nixos-config` (read-only). Stage 06 records inspected/reused sources.
Git identity is locally configured as WallyHao <wallyhao@qq.com>.

## Passing Stage 06 evidence

Full affected gate passed, exit 0:

- Log: `/tmp/folio-stage06-resume-gate1.log`.
- Output: `/nix/store/mz3i9kanf7r2kd73v3xxw18wxp7kxafd-vm-test-run-folio-desktop-session`.
- Test script: 108.95 seconds; cleanup: 0.38 seconds, no QEMU/Xvfb survivors.
- Real legacy-source plan/build/apply and explicit paired user model upgrade from
  `3270914`, then current configuration/build/apply succeeded.
- Actual device observations, unavailable backlight exit 3 and cached Zen/OBS
  installation succeeded. Physical health is explicitly unverified.
- Niri, bar, notifications, launcher, clipboard/history, screenshot, font and cursor
  metadata checks passed. `desktop.png` is retained in the output.
- Fresh-profile Rime committed Chinese text; retained `rime-input.txt` contains it.
- Actual OBS screen capture used the real chooser, portal and running PipeWire
  Niri node. Snapshots had over 100 colors and changed pixel hashes after a live
  notification. Inspected retained `obs-frame2.png`.

Earlier failing input gates are superseded. A prism file exists while Rime still
compiles other schemas. The corrected bounded wait observes the fresh profile's
`user.yaml` `last_build_time`, followed by actual input. No production input
configuration change was required. OBS websocket readiness preceded the first-run
modal; the gate now waits for and dismisses it before opening properties.

Interactive diagnosis used one guest, log
`/tmp/folio-stage06-resume-interactive.log`, artifacts
`/tmp/folio-stage06-resume-output`. Clearing only its public cache independently
reproduced deployment, then successful Chinese input. Diagnostic OBS snapshots
had 2878/3111 colors and different hashes. The final full gate above is authoritative.

`modules/desktop/tests/qemu-software.sh` owns and reaps QEMU and Xvfb directly.
The old xvfb-run wrapper left descendants behind on failure. Interactive driver
exit now completed in 0.48 seconds; PIDs 652880/652912/652908 were all gone.
Bash syntax and `git diff --check` passed. No test process is intentionally running.

## Reproduction

Reuse retained public cache/plan markers; do not redownload or use the host profile:

- `/tmp/folio-stage05-cache-store`: `/nix/store/1ff4ynmx6ywb598jaz86409kq82pnbk0-flatpak`.
- `/tmp/folio-stage05-plans-store`: `/nix/store/ls17b6553h4k1gapj5cwmhijdphpva0y-prepared-plans`.
- `/tmp/folio-stage06-legacy-store`: archived real `3270914` source.

```sh
nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths -L --impure --expr '
let
  f = builtins.getFlake (toString ./.);
  pathFrom = p: builtins.storePath
    (builtins.replaceStrings ["\n"] [""] (builtins.readFile p));
in f.checks.x86_64-linux.desktop.override {
  legacySource = pathFrom /tmp/folio-stage06-legacy-store;
  cache = pathFrom /tmp/folio-stage05-cache-store;
  plans = pathFrom /tmp/folio-stage05-plans-store;
}'
```

For an actual new failure, build the same override's `.driverInteractive` and use
one guest. The working virtual DRM fixture uses software Mesa/SDL on independent
Xvfb. Niri's nested winit backend has no GBM and cannot capture. Do not repeat host
AMD EGL-headless/virgl attempts: earlier diagnostics reset that GPU and aborted
QEMU. Do not add host-render-node assumptions. No host activation or power action.

Unchanged recovery and application checks at `3270914` were reused, not rerun for
desktop resources. Evidence is in tasks/04-recovery.md, 05-applications.md and LAYOUT.md.
Exact GUI parity, OBS Qt appearance, physical GPU/encoder, audio, Bluetooth,
backlight and Wi-Fi remain unverified and belong to Stage 09 hardware evidence.

## Next steps and boundaries

1. Review and commit the passing Stage 06 diff with explicit paths; report SHA and
   worktree state. AGENTS.md already exists and has not been changed.
2. Implement Stage 07, then 08, then Stage 09 VM acceptance. Read their ordered
   requirements and reuse sources. Do not mark hardware acceptance complete from VM
   evidence. Target activation or physical writes require actual authorization.
3. Maintain this handoff, the assigned stage record and INDEX as work progresses.
   Use focused checks and bounded stage gates; no full suite after every edit.

Historical account2 quota telemetry/checker was scoped to the previous session.
The resumed environment uses `/home/sylphy/.codex`; do not switch accounts, read
credentials or use another session's telemetry as current evidence. The earlier
owner policy was to sleep below 5% allowance and resume only on fresh recovery
telemetry. No authentication/session files belong in source or build snapshots.
