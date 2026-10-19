# Stage 06: Niri, appearance, input and devices

Dependencies: 05. Status: complete (2026-10-19).
Expected commit: `feat(desktop): integrate sylphy desktop preferences and devices`.

## Execution baseline

- Stage 05 committed as `e3ab28a`; the owner's required layout correction passed
  its guest gates and committed as `3270914`. New Nix stays in `src/`, runtime
  operations in `runtime/`, clients/resources in `cli/`, and tests outside them.
- Inspected selected Sylphy desktop geometry/shortcuts, Niri/Fuzzel renderers,
  Waybar/Mako, GTK style, GoogleDot asset rendering and Fcitx5/Rime appearance at
  `9cba023d90c4485b33a91e2d12724b6920580580`. No Rust verifier or private input
  profile is copied. Build-only cursor rendering may use Python/Pillow; the
  installed CLI/runtime does not gain a Python/Rust toolchain.
- The implementation covers appearance, input, desktop and devices. The corrected
  full automated gate passed after resumption; earlier failures below are historical.

## Objective and deliverables

Complete desktop/appearance/input/devices around earlier prerequisites. Preserve
Sylphy appearance and useful behavior through Folio public settings. Do not add
Panel, Neovim or Noctalia as a replacement desktop shell.

## Ordered work

1. Inspect reuse-map sources and selected home/theme preferences. Reuse existing
   generation, geometry, shortcuts and assets before designing alternatives.
2. Define module-owned settings and real state/actions only where needed. Introduce
   new models through Stage 04's schema upgrade path even for disabled modules.
3. Complete Everforest dark/hard, Maple Mono NF CN, GoogleDot, GTK and shared
   resources. Resolve system defaults -> user -> module overrides with origins;
   each app renders its own config. Preserve input support with English authored
   prose/help/labels; do not confuse English development with deleting Rime data.
4. Complete system Niri session/portal availability and user Niri, Waybar, Mako,
   launcher, clipboard, screenshots and shortcuts. Adapt references to excluded
   components. No new language toolchain for folio CLI.
5. Integrate Fcitx5/Rime, applicable Sylphy preferences and session startup without
   copying private dictionaries/history or whole mutable input profiles.
6. Complete audio/Bluetooth/brightness/power/hardware info under devices. Assign
   each NixOS/Home Manager option once, especially system-provided user audio
   services. Capabilities and observed health remain distinct. Missing hardware
   yields unknown/unavailable, not fabricated healthy state.
7. Verify installed desktop integration and portal/PipeWire OBS capture. Correct
   Stage 05 assumptions through supported interfaces without taking ownership of
   application scenes/profiles or other mutable data.
8. Implement concrete device/session actions in their own module subscribers only
   when required. No manager dispatch or Panel dependency. Missing backend fails
   explicitly; do not report a declaration as proof of working hardware.
9. Update root README for session/input/device features and restart/GUI limitations.

## Bounded gate

Evaluate/render affected configurations and schemas. Reuse one guest session for
Niri, bar/notifications/launcher, clipboard/screenshot, input startup, resources
and actual OBS portal capture. Unobservable interaction/visual parity stays pending.
Use representative unavailable-device cases; physical Bluetooth/Wi-Fi/brightness/
audio limitations go to Stage 09 hardware evidence. Do not rerun journal fault
suites for resource-only changes or create a VM per CSS adjustment.

## Handoff

Record actual Sylphy sources/selected values, service ownership, session/capture
evidence and hardware gaps rather than claiming VM evidence proves physical use.

## Implementation at the earlier handoff (2026-10-19)

The owner stopped implementation and requested handoff. Read `tasks/HANDOFF.md`
for the authoritative current state, reproduction command and external resources.
All Stage 06 source changes remain uncommitted on top of `3270914`.

Implemented contributions:

- Appearance: scoped model, Everforest/GTK, Maple Mono NF CN, GoogleDot-Folio
  static/animated cursor, preference/module override origins.
- Input: Fcitx5/Rime Ice, candidate appearance, no-clobber regular-file initial
  defaults preserving personal data, C/GIO language indicator.
- Desktop: system Niri/greetd/portals; user Niri, Waybar, Mako, Fuzzel, clipboard,
  screenshots, session confirmations and public devices media-key calls.
- Devices: system-owned audio/Bluetooth/backlight/power service policy; user-owned
  typed RPC/C subscriber/Bash client, bounded controls and actual observations.
- Manager: explicit catalogue/defaults/build resources, public context and
  provisioning capabilities. A private captured-source permissions fix permits
  immutable store sources to be planned and cleaned up without altering bytes.

Passing evidence:

- Resource/package builds: `/tmp/folio-stage06-resources-build2.log`,
  `/tmp/folio-stage06-desktop-build.log`, `/tmp/folio-stage06-connected-build2.log`,
  `/tmp/folio-stage06-indicator-build.log`. Pinned Niri validated the generated KDL.
- Isolated no-clobber input seed: `/tmp/folio-input-seed-check.vrfvKd`.
- Real guest old-source deployment, explicit paired user model upgrade from
  `3270914`, current configuration/build/apply, devices observations/unavailable
  backlight and cached Zen/OBS installation have succeeded.
- Actual nested Wayland input displayed Rime candidates and committed Chinese
  text. Evidence: `/tmp/folio-stage06-live-output/input-rime.png`,
  `/tmp/folio-stage06-live-output/rime-input.txt`; desktop screenshot in that
  directory. This does not establish the unresolved cold-start case below.
- Real virtual DRM OBS capture succeeded using QEMU SDL on independent Xvfb:
  `/tmp/folio-stage06-drm-output/sdl-frame2.png` and `sdl-frame3.png`, 640x400,
  2438/2944 colors, different pixel hashes after an actual desktop notification.
  The latter was inspected; actual niri/obs PipeWire nodes were running.

Latest failed gate and unresolved work:

- `/tmp/folio-stage06-final-gate6.log` failed at the Chinese-content assertion.
  The terminal received `nihao`. Focus cleanup and a bounded public dictionary
  cache wait (5.05 seconds in this run) did not fix it. Input-context activation,
  Rime ASCII state and focus are diagnostic hypotheses, not confirmed causes.
- The final automated OBS block has not been reached successfully because input
  fails earlier. Manual OBS capture evidence must not be presented as an automated
  stage gate pass. No Stage 06 completion commit exists.
- Failed gates 4–6 left QEMU descendants running while the driver hung in cleanup
  behind the Xvfb wrapper. Their owned Nix clients were cancelled during handoff;
  drivers/QEMU descendants are gone. Investigate wrapper teardown before another
  complete run. Reuse one interactive guest for diagnosis.
- The current software Mesa/Xvfb/SDL fixture starts successfully inside the Nix
  sandbox. Earlier errors with unique option priority, QMP type annotations,
  expected exit-3 shell handling and Mako process names were fixture issues fixed
  in source. The latest failure above remains unresolved.
- Niri's winit backend has no GBM and cannot capture. Host AMD EGL-headless virgl
  caused GPU resets/QEMU aborts; do not repeat that route. The current fixture no
  longer accepts a host render-node parameter.

The current full command and cache/source marker paths are in HANDOFF. Continue
with a bounded diagnostic fix, then the affected gate; do not repeat deployment
fault suites for these desktop/fixture changes. Physical GPU/encoder, Bluetooth,
backlight and audio acceptance remains Stage 09 work. Exact GUI parity and OBS Qt
appearance are not established. No host activation or real user app data changes.

## Resumed diagnosis (2026-10-19)

- The owner explicitly resumed implementation. Preserved the entire Stage 06
  diff and reused cached public Flatpak content/plans and the real legacy source.
- Built the interactive driver and used one disposable DRM guest:
  `/tmp/folio-stage06-resume-driver.log`,
  `/tmp/folio-stage06-resume-interactive.log`. The original cold-input failure
  reproduced; warm input committed Chinese. Clearing only the guest's public
  Rime cache reproduced deployment: the input-method icon already claimed Rime,
  while `user.yaml` appeared about 11 seconds later. Actual input after full
  deployment committed Chinese; artifact `rime-cold.txt` in
  `/tmp/folio-stage06-resume-output`. Replaced the early prism wait with bounded
  `last_build_time` readiness, without changing production input defaults.
- OBS websocket readiness preceded its first-run modal. That late modal consumed
  selector clicks. Explicitly closing it allowed the unchanged real portal and
  capture path to pass: 640x400 snapshots contained 2878/3111 colors and different
  pixel hashes after a notification. Inspected `obs-frame2.png` in the same output
  directory. The full gate now waits for that modal before closing it.
- Replaced `xvfb-run` with owned-child supervision in
  `modules/desktop/tests/qemu-software.sh`. Interactive driver exit completed in
  0.48 seconds; supervisor/QEMU/Xvfb PIDs 652880/652912/652908 were all gone.
  Bash syntax and `git diff --check` passed.
- Corrected full affected gate is running, log
  `/tmp/folio-stage06-resume-gate1.log`; the exact command is in HANDOFF.
  These diagnostic successes were followed by the complete gate below.

## Completion record (2026-10-19)

- Completed ordered work 1–9 within guest acceptance scope. Implemented paths are
  listed above; no new architecture, private imports or host activation was added.
- Full affected gate passed, including real legacy-source deployment, paired user
  model upgrade, current build/apply, device observations and unavailable backlight,
  cached Zen/OBS, Niri/bar/notifications/launcher/clipboard/screenshot/resources,
  cold-profile Chinese input and real changing OBS portal/PipeWire frames.
- Command: the `desktop.override` Nix build in HANDOFF with all three retained
  source/cache/plan markers. Log `/tmp/folio-stage06-resume-gate1.log`; test script
  completed in 108.95 seconds, cleanup in 0.38 seconds. Output:
  `/nix/store/mz3i9kanf7r2kd73v3xxw18wxp7kxafd-vm-test-run-folio-desktop-session`.
  Its `rime-input.txt` contains Chinese text; `desktop.png` and `obs-frame2.png`
  are retained. Inspected the latter live-capture image.
- Reused unchanged Stage 04 recovery/layout and Stage 05 application gates at
  `3270914`; no fault-suite rerun for these desktop additions. Package compilation,
  generated resources, schemas and actual runtime are exercised by this gate.
- Exact GUI parity, OBS Qt styling and physical GPU/encoder, sound, Bluetooth,
  backlight and Wi-Fi remain unverified; physical evidence belongs to Stage 09.
- Commit subject: `feat(desktop): integrate sylphy desktop preferences and devices`.
  The resulting SHA is reported after commit; no push is authorized.
- Next: Stage 07 developer tools. Preserve the explicit upgrade path, public
  preference/context interfaces, input defaults and module directory ownership.
