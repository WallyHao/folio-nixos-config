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

## Outer window margins — 2026-10-20

Increased the desktop adapter's left, right and bottom struts to 16 logical
pixels. Combined with the default 8-pixel window gaps, this leaves 24 pixels at
those edges. The top strut remains -4 to preserve the existing Waybar reservation.
Fuzzel remains the launcher, bound to Super+D.

Built and applied the frozen source through `folio --json plan --source DIR`,
`folio --json build PLAN_ID` and `folio --json apply PLAN_ID`. Transaction records
are in `~/.local/state/folio/migration/outer-margins-KENsChI0/`.
`folio --json status` reports healthy with user artifact
`/nix/store/a9qj7mn53x2nycd3r92kjdp47s2n0q59-home-manager-generation`.
`niri validate` passes; `niri msg --json windows` reports tiled windows of
1252 × 1376 logical pixels on the current 2560 × 1440 logical output, matching
the retained 40-pixel top reservation and new 24-pixel bottom inset. The running
Niri PID stayed 1715 throughout activation. `git diff --check` passes.

## Focus-ring transitions — 2026-10-20

The desktop now owns a version-guarded patch of Niri 26.04. Each tile animates
only its focus-ring opacity over 150 ms with ease-out-cubic timing. Outgoing
rings remain rendered until their fade finishes; interrupted fades resume from
their current opacity. The shared animation clock preserves global disable and
slowdown behavior. Idle transitions stop requesting frames. Window content,
straight corners, colors and margins are unchanged.

`src/compositor.nix` and `src/niri-focus-fade.patch` belong to the desktop module;
its public `desktop-niri` package is selected by both the system login entry and
the user service. Existing guest instrumentation now follows the configured
compositor package. The protected user unit retains `X-SwitchMethod=keep-old`.
No compositor restart, logout or system activation was performed.

Validation:

```sh
nix build --no-link --no-update-lock-file --max-jobs 2 --cores 8 -L \
  .#desktop-niri .#checks.x86_64-linux.desktop-focus-fade
niri --version
niri validate
systemctl --user show niri.service -p MainPID -p ExecStart
folio --json status
git diff --check
```

The package's Rust gate passed 196 tests (including three new transition tests);
two upstream EGL tests are excluded by the existing Nixpkgs package. The isolated
Xvfb/software-GL check passed with actual screenshot samples: outgoing red
255 → 98 → 0; incoming red 0 → 157 → 255. Its deliberately slowed clock makes
the intermediate frames observable. Screenshots, samples and logs are in
`/nix/store/dlq3aa6wgqqqzqpal4cvli2piah27h36-folio-niri-focus-fade`.

Built and applied the frozen source through the normal user plan/build/apply
flow. Records are in `~/.local/state/folio/migration/focus-fade-Gtvx6afm/`.
Desired configuration exports before/after are identical. User health is healthy,
artifact `/nix/store/kpciyzlmy8v2w5bl4kdiw3brzyxzhlqi-home-manager-generation`.
The installed binary reports `niri 26.04 (Folio focus-fade)`, and the loaded user
unit points to that binary. The running compositor remains PID 1715 on the old
binary: log out and back in when convenient to use the transition on the actual
desktop. The system module selects the same patched package on the next normal
system deployment; the installed user unit already selects it for the next login.

## Retiring active Sylphy compatibility — 2026-10-20

The user explicitly selected system-wide cleanup. Historical attribution, source
checkouts, migration tools/tests, snapshots and recovery journals remain; the
cleanup removes active compatibility dependencies rather than deleting history.

Implemented:

- The physical `folio` target uses hostname `folio`, preserves the existing local
  password with mutable users, and no longer selects the account migration
  adapter or its `/etc/sylphy` restoration activation. Keyring/PAM integration now
  belongs to the normal desktop system contribution. Greetd is not restarted by
  configuration changes during activation.
- Network target composition retains the working private policy/cache under
  `/var/lib/folio-mihomo`, removes old service/runtime aliases, and selects
  `/var/lib/folio-mihomo-private/provider.yaml`. Evaluation never reads credentials.
- `system-legacy-cleanup` builds `folio-retire-legacy`, a root maintenance worker.
  It verifies/copies the provider with root ownership and mode 0600, saves desired
  data, plans/builds/applies the immutable source, and checks deployment/service
  health before archiving obsolete directories. Partial failures retain recovery
  records. `restore-files BACKUP` restores prerequisites before an old-generation
  rollback. Archives live under `/var/lib/folio/backups/legacy-*` with mode 0700.
- Native Zen now receives the existing Folio preference/CSS renderer through
  Home Manager. An explicit existing profile is required; unmanaged destination
  files cause a conflict. `prefs.js`, databases, logins and session files are not
  declared as managed files.

Actual user result: the stopped browser's directory was backed up with reflink
support and renamed from `~/.config/zen/sylphy` to `~/.config/zen/folio`; desired
data and the wrapper/desktop entry now select `folio`. The original path is absent.
`user.js`, browser UI CSS and content CSS are installed. Checksums for `prefs.js`,
`cookies.sqlite`, `places.sqlite`, `key4.db` and `logins.json` are unchanged.
User apply is healthy with artifact
`/nix/store/inz3gz00b8hw3az699i1z3laspdxkhiv-home-manager-generation`.
Niri remained PID 1715 with straight corners and the existing outer margins.
Restart Zen to read the generated preferences and styles; no browser using the
personal profile was launched as a test.

Validation and evidence:

```sh
nix build --no-link --no-update-lock-file -L \
  .#checks.x86_64-linux.applications-native .#checks.x86_64-linux.configuration
nix build --no-link --no-update-lock-file -L .#system-legacy-cleanup \
  .#checks.x86_64-linux.legacy-retirement \
  .#checks.x86_64-linux.legacy-retirement-files
git diff --check
```

Native resource delivery and real configuration subscriber checks passed:
`/tmp/folio-legacy-cleanup-checks.log`, outputs
`/nix/store/rlb17pdw72zb3cbwwwh16scw8rkfgldz-folio-native-applications` and
`/nix/store/2hknw5rcn9am3ay3bay5ay835irf7l7m-folio-configuration-integration`.
`/tmp/folio-legacy-final-gate.log` records the target/password/keyring/login-service
checks and a real disposable guest's file lifecycle test. The guest mocks the
deployment/service responses; it proves credential copy, failed-apply retention,
retry, private archive and explicit file restoration, not actual host activation.
Outputs are `/nix/store/n00nx52c2ic12j7h2bj991wwrh6h7cca-folio-legacy-retirement`
and `/nix/store/15x1pszanp878bdh7gm1d0hjnayrlgw8-vm-test-run-folio-legacy-retirement-files`.
The final combined gate also passed (`/tmp/folio-legacy-consolidated-gate.log`),
with native/configuration outputs
`/nix/store/94pmm90fdv90hd4kz2x0zivdbbqdjpfd-folio-native-applications` and
`/nix/store/kyxbmmcqg1k018741b5n20cs4zvshy8z-folio-configuration-integration`.

The actual host's root configuration was exported read-only, its provider path
updated in a private candidate, normalized against the installed bootstrap and
built successfully. `/tmp/folio-retired-system-final-build.log` records artifact
`/nix/store/2mhax7028n7wzg812r5qhyfakclqyjxp-nixos-system-folio-26.11.20261011.7fd4004`.
The reviewed immutable source is
`/nix/store/w7w34qqq368kwfs932cxb6ppxj8qqydb-folio-retired-source`; the worker is
`/nix/store/rdj9kz8dqrcxx99fspldq163fhjd0pp8-folio-retire-legacy`.
Artifacts are GC-rooted under the private work directory.

**Pending root step:** sudo requires interactive authentication here. The running
system is still `sylphy-portable`; its provider path and legacy directories have
not been changed. Both existing system and new user deployments are healthy.
Run the prepared launcher locally:

```sh
sudo /home/folio/.local/state/folio/migration/retire-sylphy-CnO411uk/finish-system
```

It invokes the pinned worker/source above. All profile backups, immutable inputs,
before/after desired data, plans and the launcher are in
`~/.local/state/folio/migration/retire-sylphy-CnO411uk/`.
After execution, verify `hostname`, `folio --json --system status`,
`systemctl is-active folio-mihomo.service`, the root retirement journal phase,
and absence of `/etc/sylphy` and the old proxy directories. Preserve archives
before any deliberate rollback to an older system.

## Retirement finalization recovery — 2026-10-20

The user executed the launcher; journal
`/var/lib/folio/backups/legacy-j15YxzBg` reported interruption. Read-only host
inspection confirms that the system switch already succeeded: the active artifact
is `/nix/store/2mhax7028n7wzg812r5qhyfakclqyjxp-nixos-system-folio-26.11.20261011.7fd4004`,
plan `6a07d23a49970ec7d10d152418c6c32bae7bbfd27e8df7abfe77c8eede7cf032`.
System deployment health is healthy; manager and proxy services are active. Desired
data and the loaded service use the new Folio provider path. Legacy directories
remain unarchived. Static `/etc/hostname` is `folio`, but the transient hostname
is still `sylphy-portable`. Niri remains PID 1715.

The formatted `systemctl show ... LoadCredential` property can return
`[unprintable]`, making the worker's text grep unreliable. Replaced it with a
typed D-Bus query (`busctl --json=short get-property ... LoadCredential`). Added
`resume BACKUP`, which verifies successful apply, current plan/artifact and equal
desired data before finalization. It synchronizes the transient hostname through
`hostnamectl --transient`, then archives obsolete files. Resume does not call
plan/build/apply. Failed steps are recorded explicitly; unvalidated backup paths
are rejected without writing a journal there.

The updated guest uses a real systemd unit with `LoadCredential`, exercises the
real typed property and hostname update, injects a failure after successful apply,
rejects a changed plan, then resumes and confirms exactly two apply attempts total
(the injected failed apply and the successful retry). File restoration and private
credential/archive checks still pass. Deployment itself is mocked in this guest.
Gate: `/tmp/folio-legacy-resume-final-gate.log`.

```sh
nix build --no-link --no-update-lock-file -L .#system-legacy-cleanup \
  .#checks.x86_64-linux.legacy-retirement \
  .#checks.x86_64-linux.legacy-retirement-files
git diff --check
```

Passed outputs:
`/nix/store/q1bx6haqddagzg61fk00ch4kg8hzxv7q-folio-retire-legacy`,
`/nix/store/ainz2gi2yl00zz1ln4kjjw5dz81yccbp-folio-legacy-retirement`, and
`/nix/store/0lw3wba1cx00wisffzamw2qk38kq7nhm-vm-test-run-folio-legacy-retirement-files`.

The same private `finish-system` launcher has been atomically updated to invoke
the pinned new worker with `resume /var/lib/folio/backups/legacy-j15YxzBg`; its
previous version is retained as `finish-system.before-resume`. The worker is
GC-rooted. Interactive sudo authentication still prevents running this final root
step from the agent environment. Repeat the same local sudo command above to
finish; no repeat system switch is requested. Actual host archiving and transient
hostname synchronization remain pending that invocation.

The user subsequently ran the updated launcher successfully and reported archive
completion at `/var/lib/folio/backups/legacy-j15YxzBg`. Independent read-only host
verification confirms hostname `folio`, healthy system and user deployments, and
active manager/proxy services. `/etc/sylphy`, `/var/lib/sylphy-mihomo`,
`/var/lib/sylphy-mihomo-private`, `/run/sylphy-mihomo` and the old Zen profile path
are absent. Niri remains PID 1715. Host retirement finalization is complete; keep
the private archive for explicit recovery before selecting a legacy generation.

## Straight launcher corners — 2026-10-20

Set the Fuzzel renderer's default border radius to zero. Built and applied a frozen
source through the normal user plan/build/apply flow; the live
`~/.config/fuzzel/fuzzel.ini` now contains `radius=0`. User health is healthy and
the compositor PID was unchanged. Records are in
`~/.local/state/folio/migration/fuzzel-square-vnYgmQeu/`. The next launcher opening
reads the updated configuration. `git diff --check` passes.
