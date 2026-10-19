# Implementation Handoff

## Current delivery (2026-10-19)

Stages 00–08 and the Stage 09 **VM milestone** have passed. The owner explicitly
requested selectable hardware targets and prioritized the current laptop after
allowing physical acceptance to be deferred. That configuration preparation is
also implemented and build-validated. Physical installation/activation remains
pending by owner choice; no development-host activation, partitioning, bootloader
writes or power actions were performed. No push is authorized.

Delivery commit subject: `feat(manager): add laptop hardware targets and integrated acceptance`.
See tasks/09-acceptance.md for exact commands, failures corrected and evidence.

### Implemented interfaces

- One root Flake/lock; shared defaults remain in manager/src/defaults.nix.
  manager/src/targets.nix composes only public module exports. The checkout's
  portable target remains a disposable UEFI guest; nixosConfigurations.laptop
  prepares the current Lenovo Legion. No separate host/home trees were created.
- System owns current USB UUID/Btrfs storage, devices owns Intel/NVIDIA hardware.
  Hardware and storage are distinct module exports. Desktop remains unregistered
  until actual CPU/GPU/firmware and intended storage are inspected.
- Bootstrap target.json and frozen-source folio-target.json retain installed
  target selection across plans from ordinary checkouts. Conflicting source
  targets fail explicitly. The frozen source's portable output is the manager's
  stable build entry for the selected target. Environment/account remain shared
  portable/folio. Hardware policy is immutable source, not live autodetection.
- Laptop physical prototype password is disabled; Folio login remains locked.
  Provision reviewed credentials/recovery access before any future installation.

### Laptop inventory and boundary

Read-only discovery: Lenovo Legion Y7000 IRX9, i7-13650HX, Intel 00:02.0
(8086:a78b), NVIDIA 01:00.0 (10de:28e0, RTX 4060 Mobile), iwlwifi, r8169,
UEFI. Current root is USB sda2, Btrfs UUID
4e59b522-0ecc-4bc7-b6d0-edc4531e4a00, root/home/nix subvolumes; EFI UUID
767D-8E97. Internal NVMe has existing partitions and was not changed. Select a
new system storage export for a different disk; do not silently reuse this USB
binding for an internal installation. No driver, suspend, external-display or
physical boot acceptance is claimed from the successful build.

### Passed evidence

- Integrated gate 5: /tmp/folio-stage09-integrated5.log, exit 0, 173.59 seconds
  guest scenario, cleanup 0.00 seconds, no surviving test guests. Output:
  /nix/store/fdankxaxdz0y1acq1wkag5dsfvdmf6mm-vm-test-run-folio-integrated-release.
  Contains desktop/OBS screenshots, actual Chinese input, post-reboot healthy
  status and differing boot IDs. Includes actual user/root builds/apply, retained
  rollback, interrupted publication recovery, cached Zen/OBS, tools/network,
  actual portal/PipeWire frames, denied effects and observed reboot/poweroff.
- Hardware retention/conflict plus real user deployment: target-checks2.log in
  /tmp, exit 0. Older fixture needed dconf enabled for current appearance.
- Final selected static checks and full laptop build: /tmp/folio-target-final-build.log,
  exit 0. Laptop closure: /nix/store/d7hddg5y197y92vc5ma14mn4mqf7acs4-nixos-system-portable-26.11.20261011.7fd4004.
  Prepared frozen laptop evaluation retained PCI IDs, microcode and USB mounts:
  /tmp/folio-laptop-frozen-eval.json.
- CLI closure audit: 184 paths, no compiler/toolchain name matches, recorded in
  /tmp/folio-stage09-cli-closure-final.txt. Runtime source policy is unchanged
  by the subsequent test-only helper correction.

Desktop fixtures are shared through tests/guest.nix and session-script.nix. The
OBS helper is now explicitly in /etc/folio-test in every guest/root closure.
The release-only UEFI fixture schedules stock root growfs after growpart; merely
setting root autoResize did not start growfs with the legacy initrd. Shared SSH
is deliberately disabled: Stage 09 observes that policy, while Stage 08 retains
its enabled/key-auth/firewall evidence. Missing app cache/plans fails before boot.
Prior full recovery/migration, tools migration/removal and real DNS/proxy/SSH
focused gates are reused rather than repeated as a broad matrix.

### Next work and quota

No further implementation is needed for the authorized VM + laptop preparation
milestone. Physical acceptance stays deferred. Future desktop configuration needs
its actual inventory and storage choice. Any physical deployment first needs
reviewed access/recovery and target-specific authorization; current code is not
an installer and must not be switched onto the development host automatically.

This execution used codex2: CODEX_HOME=/home/sylphy/.codex-account2. The temporary
/tmp/folio-codex2-quota/check.sh is tied to this root session, not another agent.
Latest checked remaining quota was 59%, reset 19:02:05 Asia/Shanghai. Future agents
must identify their own session/account telemetry; follow the owner's below-5%
sleep policy without switching accounts. Public app cache/plan paths below were
reused; never use private host profiles as replacements.

The earlier records below preserve the incoming baseline and focused evidence.

## Historical baseline before Stage 09

The owner explicitly resumed implementation after the earlier handoff. Stages
00–08 have passed their gates. Implementation HEAD is `0ce2277` on `main`;
Stage 09 is pending. The worktree was clean before this documentation-only
transition. No Stage 09 implementation or integrated-release pass is claimed.
Physical acceptance is separate and no development-host activation is authorized.

## Original Stage 09 assignment (completed for VM scope)

1. Read the rules below, then tasks/09-acceptance.md and its receiving-agent
   execution plan. Preserve existing AGENTS.md. Check current HEAD and worktree;
   this handoff may be followed by a separate documentation commit.
2. Audit the current composition and root README against delivered behavior.
   Extend existing module-owned fixtures for one integrated disposable lifecycle;
   there is currently no named integrated-release check. Do not invent a passing
   command or substitute separate historical gates for end-to-end evidence.
3. Complete and commit the Stage 09 VM milestone. Keep physical acceptance pending
   until an actual target, recovery plan and target-specific authorization exist.
   Ordinary implementation decisions require no repeated consultation.

### Delivered milestones

| Stage | Commit | Delivered boundary |
| --- | --- | --- |
| 00–03 | See owning task records | Foundation, scoped user/root deployment, VM lifecycle and observed guest power |
| 04 | `7af1c09` | Durable recovery, model migration, retained rollback and protected cleanup |
| 05 | `e3ab28a` | Owned Zen/OBS lifecycle and regular-file configuration |
| Layout | `3270914` | Agreed module source/client/runtime/model/test ownership |
| 06 | `6cec01f` | Desktop/resources, Chinese input, device controls and real portal capture |
| 07 | `d09467b` | Terminal/Git/Emacs/Codex, migration and selective removal preserving personal data |
| 08 | `0ce2277` | Network-owned actions, DNS/proxy/firewall/SSH and explicit system/storage policy |

Stages 06–08 have individual passing guest gates; no single final-revision
lifecycle spanning all stages has yet passed. Evidence below states its tested
scope and limitations. Stage 08 changes are concentrated in `modules/network/`,
`modules/system/` and manager composition/public module exposure. Stage 07 also
extended the manager's readiness-probe timeout within its existing retry budget.

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
- `6cec01f`: Stage 06 desktop preferences, input and devices.
- `d09467b`: Stage 07 terminal and developer environment.
- `0ce2277`: Stage 08 modeled connectivity and system policy.

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

1. Stage 08 passed its complete gate and is committed as `0ce2277`.
   AGENTS.md is unchanged. Read its task record and retained evidence before
   changing network/system policy or claiming physical health.
2. Continue with Stage 09 VM acceptance. Read its ordered
   requirements and reuse sources. Do not mark hardware acceptance complete from VM
   evidence. Target activation or physical writes require actual authorization.
3. Maintain this handoff, the assigned stage record and INDEX as work progresses.
   Use focused checks and bounded stage gates; no full suite after every edit.

Historical account2 quota telemetry/checker was scoped to the previous session.
The resumed environment uses `/home/sylphy/.codex`; do not switch accounts, read
credentials or use another session's telemetry as current evidence. The earlier
owner policy was to sleep below 5% allowance and resume only on fresh recovery
telemetry. No authentication/session files belong in source or build snapshots.

## Passing Stage 08 evidence and interfaces

Commit: `0ce2277 feat(network): complete modeled connectivity and system policy`.

- Scope: network-owned system YANG/C/Bash controls; NetworkManager/DNS/firewall,
  key-only SSH and optional local Mihomo; system storage/account/locale/time/
  console/journal/zram/Nix policy; exact system-model 2026-10-18 archive and
  hash-bound 2026-10-19 migration; public `nixosModules.portable` composition.
- Gate log: `/tmp/folio-stage08-network-gate5.log`, exit 0. Output:
  `/nix/store/fwhq9dab4gc7914aayklcpcihv3g207p-vm-test-run-folio-network-system`.
  Script: 56.24 seconds; cleanup: 0.17 seconds, no guest/driver survivors.
  Retained `network-status.json` and `folio-ssh-policy.txt` were inspected.
  Final catalogue/foundation checks passed in `/tmp/folio-stage08-static-final.log`,
  including actual isolated repository validation and restart preservation.
- Passed real system-model upgrade, policy plan/build/apply, descriptor/timezone,
  zram/journal, actual connection effects, scoped failures, DNS and SOCKS HTTP,
  live proxy mode/selection, unavailable backends, peer key SSH and blocked HTTP.
- Reproduce with `nix build --no-link --no-update-lock-file --max-jobs 2
  --print-out-paths -L .#checks.x86_64-linux.network` (one shell command).
  Earlier failed gates and precise fixes are recorded in tasks/08-network-system.md.
- The upgrade fixture retains the exact prior system model in a documented
  synthetic source; it is not an unchanged historical release. Test closures use
  the same QEMU/instrumentation modules as the frozen fixture Flake.
- Physical policy rejects missing/unstable devices and prototype passwords.
  Runtime SSH keys and optional provider credentials are provisioned outside
  desired data/builds. No private provider or real network records were imported.
- Physical storage/boot, Wi-Fi, TUN, provider nodes and NTP are unverified. QEMU
  follows its virtual RTC; production time-sync evaluates enabled. Stage 09 must
  keep guest and hardware acceptance separate. Earlier GUI/tools gates are reused.

## Passing Stage 07 evidence and interfaces

Terminal utilities/shell, Git, Emacs and Codex are implemented with user models;
terminal also registers Zsh system-wide. Only the system account record can select
the login shell; focused evaluation selected Zsh and rejected missing registration.
Default account remains Bash. Only `unrar` is allowed by the unfree predicate.
The 2026-10-20 terminal model is archived; its additive hash-bound migration targets
2026-10-21. Existing opacity migrations still bind their original exact models.

- Package/config check: `/tmp/folio-stage07-tools-final.log`, output
  `/nix/store/a83hlv2y7z47vf4l4k0fizq4pidcjr7j-folio-developer-tools`.
- Full real profile gate: `/tmp/folio-stage07-profile-gate5.log`, output
  `/nix/store/vmkfw14nisx8shrl06hjdqn7w8r06d99-vm-test-run-folio-tools-deployment`.
  Script 86.16 seconds; cleanup 0.12 seconds. Retained `tools-status.json` reports
  healthy configuration after selective removal and snapshot/resumption.
- Actual legacy `6cec01f` paired upgrade, build/apply, configured shell, Git/Codex
  delivery, seven Emacs ERT tests, notes/indexing, disabling fzf/Git/Emacs/Codex,
  preserved repository/notes/index/private-state sentinels and offline snapshot
  all passed. No real GitHub/Codex login or physical acceptance claim.
- Full-profile status measured 1.64 seconds against the old one-second readiness
  timeout. The probe now permits a five-second RPC/six-second process cap within
  its existing overall retry deadline. Both upgrade and snapshot prove the fix.
- Interactive shell checks use `setsid --wait` and null stdin to avoid sharing
  the driver's controlling terminal. Configuration-free Zsh had the same conflict;
  isolated configured startup took 0.51 seconds. No prompt feature was disabled.
  Diagnostic logs: `/tmp/folio-stage07-profile-interactive.log`,
  `/tmp/folio-stage07-profile2-interactive.log`; shell trace in
  `/tmp/folio-stage07-profile2-output/zsh-session.log`. A diagnostic guest reset
  restored its test backdoor; it is not system power acceptance evidence.
- All interactive guests are closed. Reuse unchanged earlier fault/GUI checks;
  do not rerun them merely for tools. Exact GUI/TUI parity remains unverified.

Current Stage 07 reproduction command (marker is archived real `6cec01f`):

```sh
nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths -L --impure --expr '
let
  f = builtins.getFlake (toString ./.);
  old = builtins.storePath
    (builtins.replaceStrings ["\n"] [""] (builtins.readFile /tmp/folio-stage07-legacy-store));
in f.checks.x86_64-linux.tools-deployment.override { legacySource = old; }
'
```
