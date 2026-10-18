# Agreed layout correction

Status: complete (2026-10-19). Dependency: Stage 05, committed as `e3ab28a`.
Expected commit: `refactor(modules): restore agreed source cli and runtime layout`.

The owner explicitly requested finishing the current stage and then correcting
all implemented modules to STRUCTURE.md before continuing later stages. Root-only
product documentation remains required; do not create empty module READMEs/docs.

## Changes

- `src/` contains Nix implementation. Bash clients and jq requests/help are in
  each owner's `cli/commands/`; C subscribers and concrete Shell operations are
  in `runtime/`. Model and outer test ownership is unchanged. No empty callback
  directories or artificial placeholder components were introduced.
- Manager entry delegates package construction to `src/package.nix`, frozen-data
  composition to `src/configuration.nix`, and system/user adapters to their
  matching Nix files. Root composition remains `src/outputs.nix`; there is one
  root Flake/lock. Catalogue and prepared-input helpers remain private Nix files.
- Manager client entry is `cli/bin/folio.sh`, with arguments, command lookup,
  help, output and transport helpers in `cli/lib/`. Module command adapters expose
  `command_main` in isolated subshells. Public command help resources and jq request
  constructors are immutable package inputs. Existing public command spellings
  and scope/exit contracts are preserved; command-specific `--help` now selects
  the module-owned help resource.
- Manager runtime has module-owned operations, callbacks, snapshot and journal
  resources. C entry/callbacks remain in `runtime/main.c`; they do not require
  artificial separate files. Sysrepo, system, VM and applications likewise own
  their runtime and client sources outside `src/`.
- Applications now has `src/package.nix`, `src/system.nix`, `src/user.nix`,
  `src/flatpak.nix`, `src/apps/zen.nix` and `src/apps/obs.nix`. Browser palette/CSS
  resources remain private beneath `src/apps/zen/`. Minimum desktop/device
  infrastructure is delegated to the owning `src/system.nix` adapters.
- Updated Nix source references and the frozen-source symlink fixture. Offline
  `--rebuild` copies the current manager's src/cli/runtime together, while retaining
  frozen composition/defaults and module inventory so older source trees remain
  meaningful even when newer optional modules are absent.
- The expanded recovery gate exposed an application startup deadlock introduced
  in Stage 05: Home Manager's apply worker holds the configuration lock while
  restarting manager/app services, so application startup must not synchronously
  wait for manager RPC recovery. Startup now only dispatches/probes app journals;
  application mutations check that any configuration transaction is saved after
  acquiring the configuration lock. This preserves the mutation barrier without
  making activation wait on itself.

## Actual validation

- Initial moved-source package builds and real configuration integration passed:
  `/tmp/folio-layout-build.log`.
- After extracting CLI libraries/resources, named configuration and foundation
  checks passed, log `/tmp/folio-layout-cli-gate.log`:
  `/nix/store/hwmvilkny41v7wmjyxgpnvi1rlnld3zi-folio-configuration-integration`
  and `/nix/store/fksknmi1vydxjplivfc77pncflxrcyk5-folio-foundation`.
- Root help, module help, `help vm` and unsupported application system scope were
  exercised against `/nix/store/nj83vjlb80p0yr449vqiiwg2z691d13r-folio/bin/folio`.
- Scoped application guest passed after the startup correction:
  `/nix/store/7iibk628x9xvrjkxgms4wh0q42p1km6v-vm-test-run-folio-owned-applications`,
  log `/tmp/folio-layout-applications-gate3.log`. Cached public content was reused.
- A source from actual pre-applications commit `7af1c09`, overlaid with the new
  manager implementation while preserving the old module composition, built its
  Home Manager output at
  `/nix/store/2d3gz0n3avn2qn89hrbsv9c4748ryp6y-home-manager-generation`;
  log `/tmp/folio-layout-legacy-build.log`. This was build-only, not host activation.
- The scoped recovery guest passed after making newly copied store-source
  directories writable before restoring frozen composition:
  `/nix/store/l21ckznc7bap75qgxk1ymknfkliinbc7-vm-test-run-folio-deployment-recovery`.
  Exact command: `nix build --no-link --no-update-lock-file --max-jobs 2
  --print-out-paths -L path:.#checks.x86_64-linux.recovery`.
  Log `/tmp/folio-layout-recovery-gate7.log`; actual test runtime 125.86 seconds.
  This covers real schema migration, retained rollback/rebuild, paired recovery,
  root deployment and guest reboot/poweroff after the path correction.
- The offline guest retains native build tools for the rebuild path; runtime
  closures did not contain the `lndir`/Perl inputs needed for a newly derived
  wrapper/join. These are test-only store paths, not product user dependencies.
- Diff/whitespace and explicit staged paths were reviewed. No host activation,
  physical-device claims, private data, reference edits or pushes. Next: Stage 06,
  keeping the agreed ownership/layout for all new implementation.
