{ }:
''
  (require 'consult)
  (require 'vertico)
  (require 'orderless)
  (require 'marginalia)
  (fido-vertical-mode -1)
  (fido-mode -1)
  (icomplete-mode -1)
  (vertico-mode 1)
  (marginalia-mode 1)
  (setq completion-styles '(orderless basic)
        completion-category-defaults nil
        completion-category-overrides '((file (styles partial-completion basic))))

  (defun folio-emacs-search-notes ()
    "Search saved text across the configured notes directory."
    (interactive)
    (consult-ripgrep org-roam-directory))
  (defun folio-emacs-find-note-file ()
    "Find a file within the configured notes directory."
    (interactive)
    (consult-fd org-roam-directory))
  (define-prefix-command 'folio-emacs-search-map)
  (global-set-key (kbd "C-c s") 'folio-emacs-search-map)
  (dolist (binding '(("s" . consult-line)
                     ("n" . folio-emacs-search-notes)
                     ("p" . consult-ripgrep)
                     ("f" . folio-emacs-find-note-file)
                     ("o" . consult-outline)
                     ("l" . consult-goto-line)
                     ("b" . consult-buffer)
                     ("r" . consult-recent-file)))
    (define-key folio-emacs-search-map (kbd (car binding)) (cdr binding)))
  (global-set-key (kbd "C-x b") #'consult-buffer)
  ;; Ctrl+Space belongs to the input method in the account's desktop.
  (global-set-key (kbd "C-c SPC") #'set-mark-command)
  (easy-menu-define folio-search-menu global-map "Search and navigation."
    '("Search"
      ["Search current document" consult-line t]
      ["Search all saved notes" folio-emacs-search-notes t]
      ["Find note file" folio-emacs-find-note-file t]
      ["Search project or directory" consult-ripgrep t]
      ["Jump to heading" consult-outline t]
      ["Jump to line" consult-goto-line t]
      ["Switch document" consult-buffer t]
      ["Recent files" consult-recent-file t]
      "--"
      ["Start selection" set-mark-command t]))

  (require 'org-modern)
  (setq org-startup-with-inline-images t
        org-image-actual-width '(480)
        org-pretty-entities t
        org-ellipsis " ▾"
        org-fontify-whole-heading-line t
        org-src-fontify-natively t
        org-src-tab-acts-natively t
        ;; Preserve the existing indentation and reliable monospace tables.
        org-modern-table nil
        org-modern-block-fringe nil)
  (add-hook 'org-mode-hook #'org-modern-mode)
  (define-key org-mode-map (kbd "C-c n v") #'org-toggle-inline-images)
  (easy-menu-add-item global-map '("Notes")
                      ["Toggle inline images" org-toggle-inline-images
                       (derived-mode-p 'org-mode)])
  (easy-menu-add-item global-map '("Notes")
                      ["Toggle modern Org display" org-modern-mode
                       :style toggle :selected (bound-and-true-p org-modern-mode)
                       :active (derived-mode-p 'org-mode)])
''
