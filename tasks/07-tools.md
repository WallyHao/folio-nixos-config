# Stage 07: Terminal tools, Git, Emacs and Codex

Dependencies: 06. Status: complete (2026-10-19).
Expected commit: `feat(tools): migrate terminal and developer environment`.

## Objective and deliverables

Complete terminal and deliver git/emacs/codex capabilities by adapting existing
Sylphy implementations. Stage 02 Foot stays in the same terminal module.

## Ordered work

1. Inspect relevant Sylphy source/tests from the reuse map. Reuse package
   definitions, defaults, rendering, themes and meaningful tests; replace private
   cross-module imports with local implementation or explicit public resources.
2. Extend terminal model/adapters with Zsh/prompt and individually selectable bat,
   btop, eza, fd, fzf, jq, ripgrep, zoxide, unzip, unrar, chsrc, just and Typst.
   Typst belongs at modules/terminal/src/typst.nix. Login-shell registration is a
   system contribution; user selection cannot silently alter system policy.
3. Preserve selected Foot/shell/tool behavior, replacing identity paths and obsolete
   manager/Panel references. Any required unfree policy is explicit and narrow,
   not global allowUnfree. No one-capability-directory per small utility.
4. Add Git/GitHub CLI model/entry/user adapter and safe defaults without personal
   Git identity/signing keys/tokens. Runtime is optional without public actions.
5. Adapt Emacs including Org/Org-roam, dashboard, theme and applicable integrations.
   Preserve notes/databases; replace paths and unavailable Sylphy-specific service
   references. Emacs is selected; do not migrate Neovim.
6. Adapt Codex package/preferences/theme without authentication/session state.
   Reuse application integration, not the legacy Rust manager/CLI architecture.
7. Upgrade schema through existing protocol, keeping models/adapters available for
   disabled modules. Enabling/disabling changes managed contribution without
   deleting notes, repositories or application data.
8. Update root README for tool selection, editor usage and external authentication
   setup requirements. Do not port module documentation trees.

## Bounded gate

Build changed package/config outputs once. Run focused shell/command smoke checks
and relevant adapted Emacs batch checks for Org/Org-roam loading plus a disposable
note operation. Check Git/Codex packaging/config without real logins. Reuse one
user-profile case for selection/file delivery, no full VM per utility. Avoid
boilerplate tests asserting each package-list element or duplicating render code.

## Handoff

Record source reuse, versions, important preference/path changes, preserved data,
observed editor behavior and external authentication limitations.

## Implementation record (2026-10-19)

- Stage 06 completed as `6cec01f`; its full virtual DRM desktop/input/capture
  gate passed. Existing layout and module interfaces are preserved.
- Inspected Sylphy shell preferences and Zsh configuration/Pure Powerlevel10k,
  Git packaging, Emacs Org-roam/interface/dashboard/documents and behavior tests,
  Codex packaging/theme, Typst and chsrc patches at
  `9cba023d90c4485b33a91e2d12724b6920580580`. Reused local renderers/resources;
  excluded reference Rust verifiers and the reference-only OMP agent integration.
- Added independently selectable terminal utilities/shell, explicit additive
  terminal revision/migration, user Git/Emacs/Codex models and adapters, system
  Zsh registration and account-shell prerequisite validation. Only `unrar` is
  permitted by the unfree predicate. No real Git identity or authentication data
  is included in defaults.
- Codex keeps mutable configuration/authentication ownership. Its supported
  `.tmTheme` delivery and `/theme` selection were checked against official OpenAI
  documentation: https://learn.chatgpt.com/docs/cli-customization.
- Affected output evaluation passed; the bounded tools behavior gate is running,
  log `/tmp/folio-stage07-tools-gate1.log`. Seven adapted Emacs ERT behavior tests,
  shell/Git behavior and Codex packaging/theme passed. The relocated builder shell
  fixture's absolute history path was corrected; the affected second tools check
  passed at `/nix/store/jbp7zasl4wlv7fa5xiibm6hl1i4kzylh-folio-developer-tools`,
  log `/tmp/folio-stage07-tools-gate2.log`.
- Actual profile gate preparation caught a duplicate Emacs YANG prefix; corrected
  it before guest execution. The next guest exposed a one-second offline readiness
  RPC budget: valid full-profile status took 1.64 seconds, repeatedly timing out.
  Corrected only that probe to a five-second RPC/six-second process cap, preserving
  the 30-second overall retry deadline. A patched copy in the same interactive
  guest completed the real paired upgrade in 7.90 seconds.
- Interactive diagnosis: `/tmp/folio-stage07-profile-interactive.log`. Original
  failure log: `/tmp/folio-stage07-profile-gate2.log`. The third gate passed upgrade
  but was cancelled at the shell output pipe wait. The test now has a clean user
  environment, explicit target-profile PATH and bounded shell output redirection.
  Gate 4 bounded that check and reproduced the startup timeout. Configuration-free
  `zsh -f -i` also timed out before any startup tracing. The driver controlling
  terminal was the cause: a separate session with null stdin completed the real
  configured shell in 0.51 seconds. The fixture now uses `setsid --wait` rather
  than sharing job control with the driver. No prompt configuration was disabled.
- The same interactive guest then passed real Git/Codex delivery, all seven Emacs
  tests, disabling fzf/Git/Emacs/Codex, preservation of notes/index/repository and
  private-state sentinels, and offline snapshot/resumption. Evidence:
  `/tmp/folio-stage07-profile2-interactive.log`,
  `/tmp/folio-stage07-profile2-output/zsh-session.log`. A diagnostic guest reset
  restored its damaged test backdoor; this is not system power acceptance evidence.
- Final full affected gate is running at `/tmp/folio-stage07-profile-gate5.log`;
  final package/config check at `/tmp/folio-stage07-tools-final.log`. No Stage 07
  commit or full guest pass yet. Stage 06 evidence is unchanged.

## Completion record (2026-10-19)

- Completed ordered work 1–8. Changed `modules/terminal`, new `git`, `emacs`,
  `codex`, public manager composition/defaults, system shell selection, README
  and task records. The terminal's previous Foot font fallback is preserved.
- Final package/config gate passed:
  `nix build --no-link --no-update-lock-file --max-jobs 2 --print-out-paths -L .#checks.x86_64-linux.tools`.
  Log `/tmp/folio-stage07-tools-final.log`; output
  `/nix/store/a83hlv2y7z47vf4l4k0fizq4pidcjr7j-folio-developer-tools`.
  Shell history/cache modes, Git behavior, Codex version/completion/theme and all
  seven adapted Emacs tests passed. Codex was 0.162.1; no account login occurred.
- Full affected real user-profile gate passed in 86.16 seconds, cleanup 0.12
  seconds. Log `/tmp/folio-stage07-profile-gate5.log`; output
  `/nix/store/vmkfw14nisx8shrl06hjdqn7w8r06d99-vm-test-run-folio-tools-deployment`.
  Retained `tools-status.json` reports healthy configuration after selection and
  snapshot/resumption. This is not an application-account or physical-health claim.
- Gate command: the complete `tools-deployment.override` build in HANDOFF,
  using `/tmp/folio-stage07-legacy-store` with the archived real `6cec01f` source.
  No public Flatpak content was downloaded again.
- The guest exercised the hash-bound 2026-10-20 → 2026-10-21 terminal migration
  and new models, real build/apply, configured shell, Git/Codex delivery, disposable
  Org-roam notes/indexing, selective fzf and module removal, preserved repository,
  notes/index and private-state sentinels, and bounded offline snapshot/resumption.
- Fixed the one-second shared offline readiness probe, with direct timing evidence
  and affected real upgrade/snapshot checks. Reused unchanged earlier recovery,
  app and desktop gates rather than repeating their fault/GUI suites.
- `git diff --check` passed. No host activation, real authentication, reference
  checkout changes, private data import or Git push. Interactive guests are closed.
- Focused login-shell evaluation selected `zsh-5.9.2` and rejected absent system
  terminal registration: `/tmp/folio-stage07-login-shell-eval.json`. The default
  account remains Bash until its system record explicitly selects Zsh.
- Commit subject: `feat(tools): migrate terminal and developer environment`.
  Record the resulting SHA after commit. Next: Stage 08 network/system completion.
  Physical acceptance and exact GUI/TUI appearance remain separate limitations.
