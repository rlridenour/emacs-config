;; early-init.el -*- lexical-binding: t; -*-

;;  (setq package-enable-at-startup nil)
  (setq inhibit-default-init nil)

(customize-set-variable 'native-comp-speed 2)
(customize-set-variable 'native-comp-deferred-compilation t)

(setq native-comp-async-report-warnings-errors nil)

(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 1.0)

(defconst rlr/gc-normal-threshold (* 64 1024 1024)) ;; 64MB
(defconst rlr/gc-normal-percentage 0.1)

(add-hook 'emacs-startup-hook
	  (lambda ()
	    (setq gc-cons-threshold rlr/gc-normal-threshold
		  gc-cons-percentage rlr/gc-normal-percentage)))

(add-hook 'minibuffer-setup-hook
	  (lambda () (setq gc-cons-threshold most-positive-fixnum)))

(add-hook 'minibuffer-exit-hook
	  (lambda () (setq gc-cons-threshold rlr/gc-normal-threshold
			   gc-cons-percentage rlr/gc-normal-percentage)))

(defvar rlr/file-name-handler-alist-backup file-name-handler-alist)
(setq file-name-handler-alist nil)
(add-hook 'emacs-startup-hook
	  (lambda ()
	    (setq file-name-handler-alist
		  (delete-dups (append file-name-handler-alist
				       rlr/file-name-handler-alist-backup)))))

(setq user-full-name "Randy Ridenour"
	user-mail-address "rlridenour@fastmail.com")

(tool-bar-mode -1)
(scroll-bar-mode -1)
(tooltip-mode -1)
(setq-default frame-inhibit-implied-resize t)
(setq-default inhibit-startup-screen t)
(setq-default inhibit-startup-message t)
(setq-default initial-scratch-message nil)
(setq use-dialog-box nil)

(setq frame-resize-pixelwise t)
(add-to-list 'default-frame-alist '(fullscreen . maximized))

(defun initd/bring-emacs-to-front ()
  "Using applescript, force the Emacs frame to be activated."
  (when (eq system-type 'darwin)
    (start-process "bring-emacs-to-front" nil
		     "osascript"
		     "-e"
		     "tell application \"Emacs\" to activate")))
(add-hook 'server-after-make-frame-hook #'initd/bring-emacs-to-front)

(setq frame-title-format
	'(buffer-file-name (:eval (abbreviate-file-name buffer-file-name))
			   (dired-directory dired-directory
					    "%b")))

(defun rr/focus-new-client-frame ()
  (select-frame-set-input-focus (selected-frame)))
(add-hook 'server-after-make-frame-hook #'rr/focus-new-client-frame)

;; Main typeface
(set-face-attribute 'default nil :family "SF Mono" :height 160 :weight 'medium)
;; Proportionately spaced typeface
(set-face-attribute 'variable-pitch nil :family "SF Pro Text" :height 1.0 :weight 'medium)
;; Monospaced typeface
(set-face-attribute 'fixed-pitch nil :family "SF Mono" :height 1.0 :weight 'medium)

(set-face-attribute 'default nil :height 160)

(setq-default line-spacing 0.25)

;; Local Variables:
;; no-byte-compile: t
;; no-native-compile: t
;; no-update-autoloads: t
;; End:
