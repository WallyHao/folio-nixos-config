# Stage 06: Niri, appearance, input and devices

Dependencies: 05.
Expected commit: `feat(desktop): integrate sylphy desktop preferences and devices`.

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
