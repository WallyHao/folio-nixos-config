{ }:
''
  ;; Built-in editing aids; keep utility and backlinks buffers uncluttered.
  (setq-default display-line-numbers-type t
                display-line-numbers-width 3
                indicate-empty-lines t
                line-spacing 0.15)
  (setq frame-title-format '("%b — Emacs")
        show-paren-delay 0.1
        which-key-idle-delay 0.7
        use-dialog-box nil)
  (dolist (hook '(text-mode-hook prog-mode-hook))
    (add-hook hook #'display-line-numbers-mode)
    (add-hook hook #'hl-line-mode))
  (line-number-mode 1)
  (column-number-mode 1)
  (size-indication-mode 1)
  (transient-mark-mode 1)
  (show-paren-mode 1)
  (which-key-mode 1)
  (menu-bar-mode -1)
  (defun folio-emacs-toggle-menu-bar ()
    "Toggle the menu bar without depending on toolkit function-key handling."
    (interactive)
    (menu-bar-mode 'toggle))
  (global-set-key (kbd "<f10>") #'folio-emacs-toggle-menu-bar)
  (global-set-key (kbd "C-c t m") #'folio-emacs-toggle-menu-bar)
  (global-tab-line-mode 1)
  (save-place-mode 1)
  (savehist-mode 1)
  (recentf-mode 1)

  ;; Clickable actions complement the existing Org-roam key bindings.
  (require 'easymenu)
  (easy-menu-define folio-notes-menu global-map "Note editing actions."
    '("Notes"
      ["Find or create note" org-roam-node-find t]
      ["Insert note link" org-roam-node-insert t]
      ["Show backlinks" org-roam-buffer-toggle t]
      ["Today's note" org-roam-dailies-capture-today t]
      "--"
      ["Save document" save-buffer t]
      ["Open recent file" recentf-open-files t]
      ["Synchronize note index" org-roam-db-sync t]
      "--"
      ["Toggle line numbers" display-line-numbers-mode
       :style toggle :selected display-line-numbers-mode]
      ["Emacs tutorial" help-with-tutorial t]))
''
