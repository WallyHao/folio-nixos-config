# Replace only the editor selection. Never read, move or delete personal files.
."folio-environment:environment".modules |= (
  if any(.[]; .name == "emacs") and any(.[]; .name == "neovim") then
    error("Both Emacs and Neovim selections exist; resolve them before migration")
  else map(
    if .name == "emacs" then
      .name = "neovim" |
      if has("folio-emacs:emacs") then
        ."folio-neovim:neovim" = ."folio-emacs:emacs" | del(."folio-emacs:emacs")
      else . end
    else . end)
  end)
