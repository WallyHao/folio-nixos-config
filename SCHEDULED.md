# Desktop and Application Repair Record

## Request and scope

On 2026-10-20 the user cancelled deferred execution and requested immediate work.
The previous user timer/service were disabled/stopped to prevent a duplicate run;
the scheduling failure was not investigated. Completed in the requested order:
Niri/Waybar geometry, btop colors, then Zen Beta/OBS/dsh restoration. Preserve the
current launcher and zsh. Existing worktree deletions of `TASK.md` and
`IMPLEMENT.md` remain untouched.

## Changes

- Desktop: replace the `top -32` strut with the normal `-4` edge inset. Waybar
  already reserves its exclusive height; subtracting it again let windows overlap
  its area. On the current 2560x1440 logical output, tiled windows are now 1396
  pixels high: 40 pixels reserved above and 4 below. The compositor PID remained
  `1715` throughout all activation and schema maintenance.
- Terminal: generate/select the `folio` btop theme from the existing Everforest
  palette, with true color and theme background enabled. The renderer supports
  both palette appearances. Launcher/zsh implementations were not changed.
- Applications: add explicit native Zen Beta/OBS selections to the module-owned
  YANG model, with archived byte-identical old schema and a hash-bound additive
  migration. Native and Flatpak selections for one identity are mutually exclusive.
  Existing Flatpak defaults and lifecycle stay separate. Native binaries, desktop
  entries and manifest are delivered with the user generation and reported by
  `folio apps list`. Native package changes use `folio apply`.
- Zen Beta retains the reviewed Sylphy upstream pin and uses an explicit wrapper
  and desktop entry to open the existing `~/.config/zen/sylphy` profile. It neither
  copies browser data nor creates a replacement profile. OBS remains application
  configured. The owning module supplies the applications, without importing the
  legacy repository or using retained store paths as package definitions.
- Agents: explicitly enable the existing dsh package in the user's desired data.
  No DeepSeek request, authentication change or credential initialization was made.

## Actual host result

The layout/theme apply completed first. User schema upgrade
`native-schema-20261020-085028` then completed, retaining its old repository and
matching user closure for recovery. A subsequent normal user apply selected
native Zen and OBS, unselected their Flatpak entries, and enabled dsh.

Final user closure:
`/nix/store/slqf435zl5nn7f3bg5agsidr3a0a73d3-home-manager-generation`.
System and user status report healthy; native application status reports both
installed and applied. Manager/applications/devices/Waybar services are active.
No compositor restart, logout, reboot or system rebuild was performed.

Verified commands resolve through `~/.nix-profile/bin`:

- `zen-beta --version`: Mozilla Zen 1.22.2b.
- `obs --version`: OBS Studio 32.2.2.
- `dsh --version`: 0.2.1-rc.2.

Both native desktop entries are installed. Zen's desktop entry executes the same
profile wrapper as its CLI. Selected browser database/preferences fingerprints
and the launcher configuration fingerprint were unchanged across activation;
the fingerprints remain private under scoped migration state, not in Git.
An actual short btop PTY run rendered foreground `#d3c6aa` and background
`#272e33`; the timeout ended the smoke run normally. Its generated configuration
remains managed. No private browser session was launched for testing.

## Validation and reproduction

```sh
nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths -L \
  .#checks.x86_64-linux.configuration .#checks.x86_64-linux.agents-migration
nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths -L \
  .#checks.x86_64-linux.tools-deployment .#checks.x86_64-linux.tools \
  .#checks.x86_64-linux.applications-native
folio --json status
folio --json --system status
folio --json apps list all
niri msg --json outputs
niri msg --json windows
systemctl --user show niri.service --property=MainPID
zen-beta --version
obs --version
dsh --version
git diff --check
```

Passed evidence:

- `/tmp/folio-desktop-terminal-repair.log`: generated shell/theme/tool checks and
  configuration integration; `/tmp/folio-layout-theme-apply.log`: real first apply.
- `/tmp/folio-native-model-check.log`: real old-schema migration/restore and
  subscriber regression, including the archived applications model; outputs
  `/nix/store/a3s0axm6gf283nhpc7agni3k9rnl40bg-folio-configuration-integration` and
  `/nix/store/vzgdx4279gvg9ck4filplkxhyzgqil9j-vm-test-run-folio-agents-terminal-migration`.
- `/tmp/folio-native-packages-gate.log`: native Zen/OBS/dsh binaries, version probes,
  native manifest, existing-profile forwarding and desktop-entry verification.
- `/tmp/folio-app-repair-final-gate.log`: real user-profile delivery/removal and
  subscriber lifecycle, developer tools/themes, native delivery. Outputs:
  `/nix/store/06lx9ysmwcqxflidgpmkd2wvn62x38nm-vm-test-run-folio-tools-deployment`,
  `/nix/store/8nkmclkrs5rddlch4kpinkc7wn5ggkc8-folio-developer-tools`, and
  `/nix/store/iv322s5qbv0gq9jgi04kr6xy18c4a0a7-folio-native-applications`.
- `/tmp/folio-native-schema-upgrade.log` and `/tmp/folio-native-apps-apply.log`:
  actual paired user upgrade, final apply, retained compositor PID, private profile
  preservation, native application inventory and healthy status.

The checks do not claim a DeepSeek inference result, browser sign-in health or an
OBS recording/portal-sharing result. Those application-owned operations were not
needed to restore the requested packages and existing profile selection.
