{ }:
''
  ;;; Managed Org-roam environment -*- lexical-binding: t; -*-
  (require 'org)
  (require 'org-roam)
  (require 'org-roam-dailies)

  (setq inhibit-startup-screen t
        initial-scratch-message "Welcome to Org-roam. C-c n f finds or creates a note; C-c n b shows backlinks.\nC-h t opens the Emacs tutorial.\n"
        ring-bell-function #'ignore
        org-startup-indented t
        org-hide-emphasis-markers t
        org-return-follows-link t
        org-roam-directory (expand-file-name "~/Documents/documents")
        org-roam-completion-everywhere t)
  (when (fboundp 'tool-bar-mode) (tool-bar-mode -1))
  (when (fboundp 'scroll-bar-mode) (scroll-bar-mode -1))
  (column-number-mode 1)
  (delete-selection-mode 1)
  (electric-pair-mode 1)
  (fido-vertical-mode 1)
  (add-hook 'org-mode-hook #'visual-line-mode)

  ;; Keep mutable editor state and the rebuildable index outside the Nix store.
  (let ((state (expand-file-name "folio/emacs/"
                                  (or (getenv "XDG_STATE_HOME") "~/.local/state"))))
    (make-directory state t)
    (make-directory (expand-file-name "backups/" state) t)
    (setq recentf-save-file (expand-file-name "recentf" state)
          savehist-file (expand-file-name "history" state)
          save-place-file (expand-file-name "places" state)
          org-roam-db-location (expand-file-name "org-roam.db" state)
          backup-directory-alist `(("." . ,(expand-file-name "backups/" state)))
          auto-save-file-name-transforms `((".*" ,state t))))

  ${import ./interface.nix { }}

  (load (expand-file-name "folio/emacs/settings.el"
                          (or (getenv "XDG_CONFIG_HOME") "~/.config")) t t)
  (make-directory org-roam-directory t)
  (setq org-roam-directory (file-truename org-roam-directory)
        org-roam-dailies-directory "daily/"
        org-roam-capture-templates
        '(("d" "default" plain "%?"
           :target (file+head "%<%Y%m%d%H%M%S>-''${slug}.org" "#+title: ''${title}\n")
           :unnarrowed t)))
  (org-roam-db-autosync-mode 1)

  (global-set-key (kbd "C-c n f") #'org-roam-node-find)
  (global-set-key (kbd "C-c n i") #'org-roam-node-insert)
  (global-set-key (kbd "C-c n b") #'org-roam-buffer-toggle)
  (global-set-key (kbd "C-c n c") #'org-roam-capture)
  (global-set-key (kbd "C-c n d") #'org-roam-dailies-capture-today)
  (global-set-key (kbd "C-c n s") #'org-roam-db-sync)
  (add-to-list 'display-buffer-alist
               '("\\*org-roam\\*" (display-buffer-in-side-window)
                 (side . right) (window-width . 0.33)))

  ;; Standalone defaults use the account's existing Everforest dark colors.
  (unless (boundp 'folio-emacs-colors)
    (setq folio-emacs-colors '("#272e33" "#2e383c" "#d3c6aa" "#859289"
                                "#a7c080" "#7fbbb3" "#dbbc7f" "#4c3743" "#e67e80")))
  (pcase-let ((`(,bg ,surface ,fg ,muted ,green ,blue ,yellow ,selection ,red)
                folio-emacs-colors))
    (custom-set-faces
     `(default ((t (:background ,bg :foreground ,fg))))
     `(cursor ((t (:background ,yellow))))
     `(fringe ((t (:background ,bg))))
     `(line-number ((t (:background ,bg :foreground ,muted))))
     `(line-number-current-line ((t (:background ,surface :foreground ,yellow :weight bold))))
     `(hl-line ((t (:background ,surface :extend t))))
     `(show-paren-match ((t (:background ,selection :foreground ,yellow :weight bold))))
     `(tab-line ((t (:background ,bg :foreground ,muted :height 0.9))))
     `(tab-line-tab ((t (:background ,surface :foreground ,fg :box nil))))
     `(tab-line-tab-current ((t (:background ,surface :foreground ,yellow :weight bold :box nil))))
     `(tab-line-tab-inactive ((t (:background ,bg :foreground ,muted :box nil))))
     `(region ((t (:background ,selection))))
     `(mode-line ((t (:background ,surface :foreground ,fg :box nil))))
     `(mode-line-inactive ((t (:background ,bg :foreground ,muted :box nil))))
     `(minibuffer-prompt ((t (:foreground ,yellow))))
     `(font-lock-comment-face ((t (:foreground ,muted))))
     `(font-lock-keyword-face ((t (:foreground ,green))))
     `(font-lock-string-face ((t (:foreground ,green))))
     `(link ((t (:foreground ,blue :underline t))))
     `(org-document-title ((t (:foreground ,green :weight bold :height 1.25))))
     `(org-level-1 ((t (:foreground ,green :weight bold))))
     `(org-level-2 ((t (:foreground ,yellow :weight bold))))
     `(org-block ((t (:background ,surface))))
     `(error ((t (:foreground ,red))))))
  (add-to-list 'default-frame-alist
               `(font . ,(if (boundp 'folio-emacs-font) folio-emacs-font "Maple Mono NF CN-16")))
  (when (display-graphic-p)
    (set-frame-font (cdr (assq 'font default-frame-alist)) nil t))
  ${import ./dashboard.nix { }}
  ${import ./documents.nix { }}
  ;; Optional personal additions; never managed or overwritten by this module.
  (load (expand-file-name "folio/emacs/local.el"
                          (or (getenv "XDG_CONFIG_HOME") "~/.config")) t t)
''
