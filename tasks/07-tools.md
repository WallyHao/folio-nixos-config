# Stage 07: Terminal tools, Git, Emacs and Codex

Dependencies: 06.
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
