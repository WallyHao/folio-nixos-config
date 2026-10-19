{ }:
''
  (require 'doom-modeline)
  (setq doom-modeline-height 30
        doom-modeline-bar-width 3
        doom-modeline-icon nil
        doom-modeline-buffer-file-name-style 'truncate-except-project
        doom-modeline-buffer-encoding t
        doom-modeline-total-line-number t
        doom-modeline-minor-modes nil
        doom-modeline-time nil
        doom-modeline-battery nil)
  (doom-modeline-mode 1)

  (require 'dashboard)
  (require 'project)
  (setq dashboard-banner-logo-title "Folio — Notes and Projects"
        dashboard-startup-banner 'official
        dashboard-center-content t
        dashboard-items '((recents . 8) (projects . 5) (bookmarks . 5))
        dashboard-projects-backend 'project-el
        dashboard-set-heading-icons nil
        dashboard-set-file-icons nil
        dashboard-startupify-list '(dashboard-insert-banner
                                    dashboard-insert-newline
                                    dashboard-insert-banner-title
                                    dashboard-insert-newline
                                    dashboard-insert-navigator
                                    dashboard-insert-newline
                                    dashboard-insert-items)
        dashboard-navigator-buttons
        '(((nil "Find note" "Find or create an Org-roam note"
            (lambda (&rest _) (org-roam-node-find)))
           (nil "Today's note" "Capture today's daily note"
            (lambda (&rest _) (org-roam-dailies-capture-today)))
           (nil "Notes folder" "Browse the notes directory"
            (lambda (&rest _) (dired org-roam-directory))))))
  ;; The Nix launcher supplies --load, so Dashboard's argument-count heuristic
  ;; cannot distinguish ordinary startup from opening a file.
  (defun folio-emacs-start-page ()
    "Show Dashboard on interactive startup unless a file is already open."
    (unless (or noninteractive
                (seq-some #'buffer-file-name (buffer-list)))
      (dashboard-open)))
  (add-hook 'emacs-startup-hook #'folio-emacs-start-page)
  (global-set-key (kbd "C-c n h") #'dashboard-open)
  (easy-menu-add-item global-map '("Notes")
                      ["Open start page" dashboard-open t])
  (pcase-let ((`(,bg ,surface ,fg ,muted ,green ,blue ,yellow ,selection ,red)
                folio-emacs-colors))
    (custom-set-faces
     `(doom-modeline-bar ((t (:background ,green))))
     `(doom-modeline-buffer-modified ((t (:foreground ,yellow :weight bold))))
     `(dashboard-heading ((t (:foreground ,green :weight bold))))
     `(dashboard-banner-logo-title ((t (:foreground ,fg :weight bold))))
     `(dashboard-navigator ((t (:foreground ,blue))))))
''
