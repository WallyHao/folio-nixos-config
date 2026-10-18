# Sylphy reference and reuse map

## Inspect before implementing

Reference found during planning: `/home/sylphy/Workspace/sylphy-nixos-config`,
normally `../sylphy-nixos-config`. Inspect relevant current files and local guidance.
Paths below were observed during planning; use rg to locate moved implementations.
Record the reference Git revision if accessible, otherwise paths and date.
If unavailable, report it and continue independent framework work; do not silently
reimplement the entire existing desktop or application environment.

Reuse working renderers, package definitions, preferences, resources, integration
and meaningful tests. Adapt the smallest useful portion into its Folio owner,
preserving notices/licenses where applicable. No blind whole-tree copy, nested
Flakes/locks, docs, Rust environments or dependency on the mutable reference.

## Ownership map

| Folio owner | Sylphy starting points | Adaptation focus |
| --- | --- | --- |
| manager | manager/nix/{environment,home-authority,home-publication,adoption,target-input,prerequisites,vm,vm-image}.nix; manager/tests/ | Profile authority, adoption, frozen inputs and guests; keep Folio's sysrepo/C/Bash design |
| system | host/portable/; modules/{users,locale,time-sync,tty,journald,zram,nix}/ | Policies/accounts; replace identity and never assume the same physical disk |
| network | modules/{network-manager,mihomo,firewall,openssh}/ | Preferences/services without real subscriptions, keys or network records |
| devices | modules/{pipewire,bluetooth,brightness,power-management,system-info}/ | Device policy/state with explicit scope ownership and no Panel dependency |
| vm | manager/nix/{vm,vm-image}.nix; modules/libvirt/ | Reuse guest/image ideas, implement direct QEMU/KVM/OVMF without libvirt |
| desktop | home/sylphy/desktop.nix; modules/{niri,waybar,mako,launcher,fuzzel,clipboard-history}/ | Geometry, shortcuts, notifications, bar, launcher, clipboard/screenshots |
| appearance | home/sylphy/{theme.json,theming.nix}; modules/{appearance,fonts,google-cursor,gtk}/ | Palette roles, fonts, cursor and GTK resources via public preferences |
| input | modules/fcitx5/; home/sylphy/desktop.nix | Fcitx5/Rime and session integration without private histories |
| terminal | home/sylphy/shell.nix; modules/{foot,zsh,typst,bat,btop,eza,fd,fzf,jq,ripgrep,zoxide,unzip,unrar,chsrc,just}/ | Existing renderers/preferences combined into one terminal capability |
| git | modules/git/ | Git/GitHub CLI defaults without personal identity or tokens |
| emacs | modules/emacs/src/ and tests/ | Emacs, Org, Org-roam, dashboard/theme and useful behavior checks |
| codex | modules/codex/src/ and tests/ | Packaging/preferences/theme, no authentication state or Rust CLI port |
| applications | home/sylphy/browser.nix; modules/zen-browser/src/{zen-browser,palette,theme,content-theme,upstream}.nix; modules/obs-studio/ | Supported browser CSS/preferences, OBS integration, actual user Flatpak paths |

## First concrete reuse

Sylphy's `modules/foot/src/config.nix` exposes rendering with font, padding,
palette roles and optional colors-file input. Inspect it with the selected home
preferences and `home/sylphy/theme.json`. Its standalone fallback font/padding
are not necessarily the selected user values. Adapt this renderer into Folio
terminal internals, consuming normalized settings/public preferences. Do not
invent a fresh Foot theme or hardcode a second live editable settings authority.

## Boundaries

- Adapt identity/home paths to folio; desired values belong in YANG/sysrepo.
- Replace copied private imports with local code or explicit public resources.
- Do not migrate Sylphy host/home trees, source registries, nested Flakes, Rust
  manager, Panel, Neovim or Noctalia as the Folio architecture.
- No copied credentials, browser profiles/databases, SSH keys or subscriptions.
- Reuse applicable behavior tests, removing old identity and Flake assumptions.
- Record substantial reuse or why an existing implementation was unsuitable;
  no need for a report per trivial line of code. Do not modify the reference.
