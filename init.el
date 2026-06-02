;;; init.el -*- lexical-binding: t; -*-

(with-eval-after-load 'package
  (add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t))

(setq use-package-always-ensure t)

(setq custom-file (concat user-emacs-directory "custom.el"))
(load custom-file)

(global-set-key (kbd "C-x c") #'save-buffers-kill-emacs)

(use-package exec-path-from-shell
  :config
  (exec-path-from-shell-initialize))

(setq create-lockfiles nil)

(use-package emacs
  :config
  (require 'bookmark)
  (bookmark-bmenu-list)
  (setq bookmark-save-flag 1))

(setq delete-by-moving-to-trash t
	trash-directory "~/.Trash/emacs")

(defun rr/open-init-file ()
  (interactive)
  (progn (find-file "~/.config/emacs/config.org")
	   (variable-pitch-mode -1)))

(defun open-fish-functions ()
  (interactive)
  (dired "~/.config/fish/functions"))

;; Enable Vertico.
(use-package vertico

  :custom
  (vertico-cycle t)
  ;; (vertico-scroll-margin 0) ;; Different scroll margin
  ;; (vertico-count 20) ;; Show more candidates
  ;; (vertico-resize t) ;; Grow and shrink the Vertico minibuffer
  ;; (vertico-cycle t) ;; Enable cycling for `vertico-next/previous'
  :init
  (vertico-mode)
  :config
  (vertico-multiform-mode 1)
  (setq vertico-multiform-categories
	  '((file grid)
	    ;; (jinx grid (vertico-grid-annotate . 20))
	    ;; (citar buffer)
	    ))
  :bind
  (:map vertico-map
	  ;; keybindings to cycle through vertico results.
	  ("C-h" . #'+minibuffer-up-dir)
	  ("<backspace>" . #'vertico-directory-delete-char)
	  ("RET" . #'vertico-directory-enter)))

;; Persist history over Emacs restarts. Vertico sorts by history position.
(use-package savehist
  :init
  (savehist-mode))

;; Emacs minibuffer configurations.
(use-package emacs
  :custom
  ;; Enable context menu. `vertico-multiform-mode' adds a menu in the minibuffer
  ;; to switch display modes.
  (context-menu-mode t)
  ;; Support opening new minibuffers from inside existing minibuffers.
  (enable-recursive-minibuffers t)
  ;; Hide commands in M-x which do not work in the current mode.  Vertico
  ;; commands are hidden in normal buffers. This setting is useful beyond
  ;; Vertico.
  (read-extended-command-predicate #'command-completion-default-include-p)
  ;; Do not allow the cursor in the minibuffer prompt
  (minibuffer-prompt-properties
   '(read-only t cursor-intangible t face minibuffer-prompt)))

(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles partial-completion)))))

(use-package marginalia
  :ensure
  :config (marginalia-mode))

(use-package consult
  :ensure
  :demand
  :bind
  (("C-x b" . #'consult-buffer)
   ("s-f" . #'consult-line)
   ("s-r" . #'consult-buffer)
   ("M-y" . #'consult-yank-pop)))

(defun rlr/consult-rg ()
  "Function for consult-ripgrep with the universal-argument."
  (interactive)
  (consult-ripgrep (list 4)))

(defun rlr/consult-fd ()
  "Function for consult-find with the universal-argument."
  (interactive)
  (consult-find (list 4)))

(defun reload-user-init-file()
  (interactive)
  (load-file user-init-file))

(defun rlr/display-startup-time ()
  (message "Emacs loaded in %s with %d garbage collections."
	     (format "%.2f seconds"
		     (float-time
		(time-subtract after-init-time before-init-time)))
	     gcs-done))

(add-hook 'emacs-startup-hook #'rlr/display-startup-time)

(setq default-directory "~/")

;; Local Variables:
;; no-byte-compile: t
;; no-native-compile: t
;; no-update-autoloads: t
;; End:
