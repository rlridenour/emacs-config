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

(defconst rr-emacs-dir (expand-file-name user-emacs-directory)
  "The path to the emacs.d directory.")

(defconst rr-cache-dir "~/.cache/emacs/"
  "The directory for Emacs activity files.")

(defconst rr-backup-dir (concat rr-cache-dir "backup/")
  "The directory for Emacs backup files.")

(defconst rr-org-dir "/Users/rlridenour/Library/Mobile Documents/com~apple~CloudDocs/org/"
  "The directory for my org files.")

(defconst rr-agenda-dir "/Users/rlridenour/Library/Mobile Documents/iCloud~com~appsonthemove~beorg/Documents/org/"
  "The directory for RR-Emacs note storage.")

(defconst rr-notes-dir "/Users/rlridenour/Library/Mobile Documents/com~apple~CloudDocs/Documents/notes/"
  "The directory for RR-Emacs note storage.")

;;;; Create directories if non-existing
(dolist (dir (list rr-cache-dir
		     rr-backup-dir))
  (unless (file-directory-p dir)
    (make-directory dir t)))

(setq create-lockfiles nil)

(unbind-key "s-m")

(use-package transient)

(use-package major-mode-hydra
  :commands (pretty-hydra-define)
  :bind
  ("s-m" . #'major-mode-hydra))

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

(use-package yasnippet
  :config
  :init
  (yas-global-mode 1)
  :custom
  (yas-snippet-dirs '("~/.config/emacs/snippets")))

(set-language-environment "UTF-8")
(set-default-coding-systems 'utf-8)

(setq sentence-end-double-space nil)

(setq-default tab-width 10)

(setq insert-directory-program "gls")

(setq message-kill-buffer-on-exit t)

(setf use-short-answers t)

(setopt ns-right-command-modifier 'hyper)
(setopt ns-right-alternate-modifier 'none)

(setq enable-recursive-minibuffers t)
(minibuffer-depth-indicate-mode 1)

(setq browse-url-browser-function 'browse-url-default-macosx-browser)
(setq browse-url-secondary-browser-function 'eww-browse-url)

(setq world-clock-list
	'(
	  ("America/Chicago" "Oklahoma City")
	  ("America/Los_Angeles" "Seattle")
	  ("Pacific/Honolulu" "Honolulu")
	  ("America/New_York" "New York")
	  ("Etc/UTC" "UTC")))

(setq world-clock-time-format "%a, %d %b %R %Z")

(setq calendar-location-name "Norman, OK"
	calendar-latitude 35.24371
	calendar-longitude -97.416797
	calendar-mark-holidays-flag t        ;colorize holidays in the calendar
	holiday-bahai-holidays nil           ;these religions have MANY holidays
	holiday-islamic-holidays nil         ;... that I don't get off
	holiday-hebrew-holidays nil         ;... that I don't get off
	)

(global-set-key (kbd "<f8>") #'calendar)

(line-number-mode)
(column-number-mode)

(global-visual-line-mode 1)

(global-hl-line-mode)
(setq hl-line-sticky-flag nil)
(setq global-hl-line-sticky-flag nil)

(setq display-time-24hr-format t)
(display-time-mode)

(setq ring-bell-function 'ignore)

(electric-pair-mode 1)
(show-paren-mode)
(setq show-paren-delay 0)

(use-package savehist
  :config
  (savehist-mode 1))

(setq read-extended-command-predicate
      #'command-completion-default-include-p)

(setq-default bidi-display-reordering 'left-to-right
	      bidi-paragraph-direction 'left-to-right)
(setq bidi-inhibit-bpa t)

(setq redisplay-skip-fontification-on-input t)

(setq read-process-output-max (* 4 1024 1024)) ; 4MB

(setq kill-do-not-save-duplicates t)

(setq savehist-additional-variables
      '(search-ring regexp-search-ring kill-ring))

(add-hook 'savehist-save-hook
	  (lambda ()
	    (setq kill-ring
		  (mapcar #'substring-no-properties
			  (cl-remove-if-not #'stringp kill-ring)))))

(setq reb-re-syntax 'string)

(setq ffap-machine-p-known 'reject)

(setq window-combination-resize t)

(setq set-mark-command-repeat-pop t)

(use-package modus-themes
  :demand
  :bind
  (("<f9>" . #'modus-themes-toggle))
  :config
  ;; Add all your customizations prior to loading the themes
  (setq modus-themes-italic-constructs t
	  modus-themes-mixed-fonts t
	  modus-themes-variable-pitch-ui t
	  modus-themes-italic-constructs t
	  modus-themes-bold-constructs t)

  ;; Maybe define some palette overrides, such as by using our presets
  (setq modus-themes-common-palette-overrides
	  modus-themes-preset-overrides-faint)

  ;; Load the theme of your choice.
  (load-theme 'modus-operandi t))

(defun rlr/customize-org-headings ()
  "Make Org headings larger."
  (set-face-attribute 'org-level-1 nil :height 1.3 :weight 'bold :inherit 'fixed-pitch)
  (set-face-attribute 'org-level-2 nil :height 1.2 :weight 'bold :inherit 'fixed-pitch)
  (set-face-attribute 'org-level-3 nil :height 1.1 :weight 'bold :inherit 'fixed-pitch)
  (set-face-attribute 'org-level-4 nil :height 1.0 :weight 'bold :inherit 'fixed-pitch)
  (set-face-attribute 'org-level-5 nil :height 1.0 :weight 'bold :inherit 'fixed-pitch)
  (set-face-attribute 'org-level-6 nil :height 1.0 :weight 'bold :inherit 'fixed-pitch)
  (set-face-attribute 'org-level-7 nil :height 1.0 :weight 'bold :inherit 'fixed-pitch)
  (set-face-attribute 'org-level-8 nil :height 1.0 :weight 'bold :inherit 'fixed-pitch)
  ;; Make the document title a bit bigger
  (set-face-attribute 'org-document-title nil :weight 'bold :height 1.5))

(add-hook 'modus-themes-after-load-theme-hook #'rlr/customize-org-headings)

(recentf-mode)
(setopt recentf-max-menu-items 1000
	  recentf-max-saved-items 1000)

(setq save-place-file (expand-file-name "saveplaces" rr-cache-dir))
(save-place-mode)

(require 'uniquify)

(global-auto-revert-mode 1)
(setq global-auto-revert-non-file-buffers t
	dired-auto-revert-buffer t
	auto-revert-verbose nil)

(setq ibuffer-expert t)

(add-hook 'ibuffer-mode-hook
	    #'(lambda ()
		(ibuffer-auto-mode 1)
		(ibuffer-switch-to-saved-filter-groups "home")))

(setq savehist-file (expand-file-name "savehist" rr-cache-dir))
(savehist-mode)

(setq large-file-warning-threshold nil)

(add-hook 'before-save-hook 'time-stamp)

(defadvice save-buffers-kill-emacs (around no-query-kill-emacs activate)
  (cl-flet ((process-list ())) ad-do-it))

(setq kill-buffer-query-functions nil)

(add-to-list 'display-buffer-alist
	       (cons "\\*Async Shell Command\\*.*" (cons #'display-buffer-no-window nil)))

(defun make-parent-directory ()
  "Make sure the directory of `buffer-file-name' exists."
  (make-directory (file-name-directory buffer-file-name) t))
(add-hook 'find-file-not-found-functions #'make-parent-directory)

(defun nuke-all-buffers ()
  "Kill all the open buffers except the current one.
	      Leave *scratch*, *dashboard* and *Messages* alone too."
  (interactive)
  (mapc
   (lambda (buffer)
     (unless (or
		(string= (buffer-name buffer) "*scratch*")
		(string= (buffer-name buffer) "*Org Agenda*")
		(string= (buffer-name buffer) "*Messages*")
		(string= (buffer-name buffer) "*mu4e-main*")
		)
	 (kill-buffer buffer)))
   (buffer-list))
  (delete-other-windows)
  (tab-bar-close-other-tabs)
  ;; (goto-dashboard)
  )

(defun rlr/kill-other-buffers ()
  (interactive)
  (crux-kill-other-buffers)
  (tab-bar-close-other-tabs))

(defun goto-emacs-init ()
  (interactive)
  (find-file (concat rr-emacs-dir "/init.org")))

(defun goto-shell-init ()
  (interactive)
  (find-file "~/.config/fish/functions/"))

(setq save-interprogram-paste-before-kill t)

(setq default-input-method 'TeX)

(delete-selection-mode 1)

;; When there is a "Time-stamp: <>" string in the first 10 lines of the file,
;; Emacs will write time-stamp information there when saving the file.
;; (Borrowed from http://home.thep.lu.se/~karlf/emacs.html)
(setq time-stamp-active t          ; Do enable time-stamps.
	time-stamp-line-limit 10     ; Check first 10 buffer lines for Time-stamp: <>
	time-stamp-format "Last changed %Y-%02m-%02d %02H:%02M:%02S by %u")
(add-hook 'write-file-hooks 'time-stamp) ; Update when saving.

(global-set-key (kbd "C-x C-b") #'ibuffer)
(global-set-key (kbd "s-o") #'find-file)
(global-set-key (kbd "s-k") #'kill-current-buffer)
(global-set-key (kbd "M-s-k") #'kill-buffer-and-window)
(global-set-key (kbd "s-K") #'nuke-all-buffers)

(use-package ace-window
  :ensure
  :config
  (setq aw-dispatch-always t)
  :bind
  (("M-O" . #'ace-window)
   ("M-o" . #'rlr/quick-window-jump)))

(defun rlr/quick-window-jump ()
  "If only one window, switch to previous buffer, otherwise call ace-window."
  (interactive)
  (let* ((window-list (window-list nil 'no-mini)))
    (if (< (length window-list) 3)
	  ;; If only one window, switch to previous buffer. If only two, jump directly to other window.
	  (if (one-window-p)
	      (switch-to-buffer nil)
	(other-window 1))
	(ace-window t))))

(defun delete-window-balance ()
  "Delete window and rebalance the remaining ones."
  (interactive)
  (delete-window)
  (balance-windows))

(defun split-window-below-focus ()
  "Split window horizontally and move focus to other window."
  (interactive)
  (split-window-below)
  (balance-windows)
  (other-window 1))

(defun split-window-right-focus ()
  "Split window vertically and move focus to other window."
  (interactive)
  (split-window-right)
  (balance-windows)
  (other-window 1))

(defun rlr/find-file-right ()
  "Split window vertically and select recent file."
  (interactive)
  (split-window-right-focus)
  (consult-buffer))

(defun rlr/find-file-below ()
  "Split window horizontally and select recent file."
  (interactive)
  (split-window-below-focus)
  (consult-buffer))

(defun toggle-window-split ()
  (interactive)
  (if (= (count-windows) 2)
	(let* ((this-win-buffer (window-buffer))
	       (next-win-buffer (window-buffer (next-window)))
	       (this-win-edges (window-edges (selected-window)))
	       (next-win-edges (window-edges (next-window)))
	       (this-win-2nd (not (and (<= (car this-win-edges)
					   (car next-win-edges))
				       (<= (cadr this-win-edges)
					   (cadr next-win-edges)))))
	       (splitter
		(if (= (car this-win-edges)
		       (car (window-edges (next-window))))
		    'split-window-horizontally
		  'split-window-vertically)))
	  (delete-other-windows)
	  (let ((first-win (selected-window)))
	    (funcall splitter)
	    (if this-win-2nd (other-window 1))
	    (set-window-buffer (selected-window) this-win-buffer)
	    (set-window-buffer (next-window) next-win-buffer)
	    (select-window first-win)
	    (if this-win-2nd (other-window 1))))))

(defun toggle-frame-maximized-undecorated ()
  (interactive)
  (let* (
	   (frame (selected-frame))
	   (on? (and (frame-parameter frame 'undecorated) (eq (frame-parameter frame 'fullscreen) 'maximized)))
	   (geom (frame-monitor-attribute 'geometry))
	   (x (nth 0 geom))
	   (y (nth 1 geom))
	   (display-height (nth 3 geom))
	   (display-width (nth 2 geom))
	   (cut (if on? (if ns-auto-hide-menu-bar 26 50) (if ns-auto-hide-menu-bar 4 26))))
    (set-frame-position frame x y)
    (set-frame-parameter frame 'fullscreen-restore 'maximized)
    (set-frame-parameter nil 'fullscreen 'maximized)
    (set-frame-parameter frame 'undecorated (not on?))
    (set-frame-height frame (- display-height cut) nil t)
    (set-frame-width frame (- display-width 20) nil t)
    (set-frame-position frame x y)))

(defun rlr/delete-tab-or-frame ()
  "Delete current tab. If there is only one tab, then delete current frame."
  (interactive)
  (if
	(not (one-window-p))
	(delete-window)
    (condition-case nil
	  (tab-close)
	(error (delete-frame)))))

(defun rlr/kill-buffer-delete-tab-or-frame ()
  "Kill current buffer and delete its tab. If there is only one tab, then delete current frame."
  (interactive)
  (kill-buffer)
  (if
	(not (one-window-p))
	(delete-window)
    (condition-case nil
	  (tab-close)
	(error (delete-frame)))))

(global-set-key (kbd "s-0") #'delete-window)
(global-set-key (kbd "s-1") #'delete-other-windows)
(global-set-key (kbd "s-2") #'rlr/find-file-below)
(global-set-key (kbd "s-3") #'rlr/find-file-right)
(global-set-key (kbd "s-4") #'split-window-below-focus)
(global-set-key (kbd "s-5") #'split-window-right-focus)
(global-set-key (kbd "s-6") #'toggle-window-split)
(global-set-key (kbd "S-C-<left>") #'shrink-window-horizontally)
(global-set-key (kbd "S-C-<right>") #'enlarge-window-horizontally)
(global-set-key (kbd "S-C-<down>") #'shrink-window)
(global-set-key (kbd "S-C-<up>") #'enlarge-window)
(global-set-key (kbd "C-x w") #'delete-frame)
;; (global-set-key (kbd "M-o") #'crux-other-window-or-switch-buffer)
(global-set-key (kbd "s-\"") #'previous-window-any-frame)
(global-set-key (kbd "s-t") #'tab-new)
(global-set-key (kbd "s-T") #'rlr/find-file-new-tab)
(global-set-key (kbd "s-w") #'rlr/delete-tab-or-frame)
(global-set-key (kbd "s-W") #'rlr/kill-buffer-delete-tab-or-frame)

(defun insert-date-string ()
  "Insert current date yyyymmdd."
  (interactive)
  (insert (format-time-string "%Y%m%d")))

(defun insert-standard-date ()
  "Inserts standard date time string."
  (interactive)
  (insert (format-time-string "%B %e, %Y")))

(defun insert-blog-date ()
  (interactive)
  (insert (format-time-string "%Y-%m-%d-")))

(defun rr/wrap-at-sentences ()
  "Fills the current paragraph, but starts each sentence on a new line."
  (interactive)
  (save-excursion
    ;; Select the entire paragraph.
    (mark-paragraph)
    ;; Move to the start of the paragraph.
    (goto-char (region-beginning))
    ;; Record the location of the end of the paragraph.
    (setq end-of-paragraph (region-end))
    ;; Wrap lines with hard newlines.
    (let ((use-hard-newlines 't))
	;; Loop over each sentence in the paragraph.
	(while (< (point) end-of-paragraph)
	  ;; Move to end of sentence.
	  (forward-sentence)
	  ;; Delete spaces after sentence.
	  (just-one-space)
	  ;; Delete preceding space.
	  (delete-char -1)
	  ;; Insert a newline before the next sentence.
	  (insert "\n")
	  ))))

(defun dos2unix ()
  "Replace DOS eolns CR LF with Unix eolns CR"
  (interactive)
  (goto-char (point-min))
  (while (search-forward (string ?\C-m) nil t) (replace-match "\n")))

(defun strip-url-tracking (url)
  "Strip common tracking parameters from URL."
  (let* ((tracking-params '("utm_source" "utm_medium" "utm_campaign"
			      "utm_term" "utm_content" "utm_id"
			      "fbclid" "gclid" "gad_source"
			      "mc_cid" "mc_eid" "ref" "source"
			      "_ga" "_gl" "msclkid" "twclid"))
	   (parsed (url-generic-parse-url url))
	   (query (url-filename parsed)))
    (if (string-match "\\?" query)
	  (let* ((path (substring query 0 (match-beginning 0)))
		 (qs (substring query (match-end 0)))
		 (params (split-string qs "&"))
		 (clean (seq-filter
			 (lambda (p)
			   (not (member (car (split-string p "="))
					tracking-params)))
			 params))
		 (new-qs (string-join clean "&"))
		 (new-file (if (string-empty-p new-qs)
			       path
			     (concat path "?" new-qs))))
	    (setf (url-filename parsed) new-file)
	    (url-recreate-url parsed))
	url)))

(defun strip-url-tracking-at-point ()
  "Strip tracking params from URL at point or read from minibuffer."
  (interactive)
  (let* ((url (or (thing-at-point 'url t)
		    (read-string "URL: ")))
	   (clean (strip-url-tracking url)))
    (message "Clean URL: %s" clean)
    (kill-new clean)))

(defun strip-url-tracking-region (beg end)
  "Strip tracking params from all URLs in region."
  (interactive "r")
  (let ((text (buffer-substring-no-properties beg end)))
    (replace-regexp-in-region
     "https?://[^\s\n\"]+"
     (lambda (url) (strip-url-tracking url))
     beg end)))

(defun delete-extra-blank-lines ()
  (interactive)
  (save-excursion)
  (beginning-of-buffer)
  (replace-regexp "^\n\n+" "\n"))

(defun rr/insert-unicode (unicode-name)
  "Same as C-x 8 enter UNICODE-NAME."
  (insert-char (gethash unicode-name (ucs-names))))

(defun push-mark-no-activate ()
    "Pushes `point' to `mark-ring' and does not activate the region
     Equivalent to \\[set-mark-command] when \\[transient-mark-mode] is disabled"
    (interactive)
    (push-mark (point) t nil)
    (message "Pushed mark to ring"))

;;  (general-define-key "C-`" #'push-mark-no-activate) ;
;;  (general-define-key "M-`" #'consult-mark)

; Don't break out a separate frame for ediff
(setq ediff-window-setup-function 'ediff-setup-windows-plain)

				; Horizontal splitting really ought to be the default, honestly.
(setq ediff-split-window-function 'split-window-horizontally)

(use-package crux
  :bind
  (("s-p" . #'crux-create-scratch-buffer)
   ("s-j" . #'crux-top-join-line)
   ("<S-return>" . #'crux-smart-open-line)
   ("<C-S-return>" . #'crux-smart-open-line-above)
   ("<escape>" . #'crux-keyboard-quit-dwim)))

(use-package dired
  :ensure nil
  :bind
  (:map dired-mode-map
	  ("M-<RET>" . #'crux-open-with)))

(define-key (current-global-map) [remap keyboard-quit] #'crux-keyboard-quit-dwim)

(use-package evil-nerd-commenter
  :bind
  ("M-;" . #'evilnc-comment-or-uncomment-lines))

(use-package magit
  :after transient
  :bind ("C-x g" . magit-status)
  :custom
  (magit-git-executable "/opt/homebrew/bin/git")
  :init
  (setq magit-process-connection-type nil)
  :config
  (setq magit-refresh-verbose t)
  )

(use-package jinx
  :init
  (setenv "PKG_CONFIG_PATH" (concat "/opt/homebrew/opt/glib/lib/pkgconfig/:" (getenv "PKG_CONFIG_PATH")))
  :config
  (setq ispell-silently-savep t)
  :hook (emacs-startup . global-jinx-mode)
  :bind
  (([remap ispell-word] . #'jinx-correct)
   ("<f7>" . #'jinx-correct)
   ("S-<f7>" . #'jinx-correct-all)))

(global-set-key (kbd "<s-up>") #'beginning-of-buffer)
(global-set-key (kbd "<s-down>")  #'end-of-buffer)
(global-set-key (kbd "<s-right>") #'end-of-visual-line)
(global-set-key (kbd "<s-left>") #'beginning-of-visual-line)
(global-set-key (kbd "<M-down>") #'forward-paragraph)
(global-set-key (kbd "<M-up>") #'backward-paragraph)
(global-set-key (kbd "M-u") #'upcase-dwim)
(global-set-key (kbd "M-l") #'downcase-dwim)
(global-set-key (kbd "M-c") #'capitalize-dwim)
(global-set-key (kbd "RET") #'newline-and-indent)
(global-set-key (kbd "M-/") #'hippie-expand)
(global-set-key (kbd "<s-backspace>") #'kill-whole-line)
(global-set-key (kbd "<C-d d>") #'insert-standard-date)
(global-set-key (kbd "M-q") #'reformat-paragraph)
(global-set-key (kbd "M-#") #'dictionary-lookup-definition)

(use-package org
  :ensure nil
  :init
  ;; (setq org-directory "/Users/rlridenour/Library/Mobile Documents/com~apple~CloudDocs/org/")
  (setq org-directory "/Users/rlridenour/Library/Mobile Documents/com~apple~CloudDocs/org/")
  :config
  (setq org-modules '(org-id org-attach)) ;; Recommended by Boris
  (setq org-list-allow-alphabetical t)
  (setq org-highlight-latex-and-related '(latex script entities))
  (setq org-startup-indented nil)
  (setq org-adapt-indentation nil)
  (setq org-hide-leading-stars nil)
  (setq org-hide-emphasis-markers t)
  (setq org-list-indent-offset 2)
  (setq org-use-speed-commands t)

  (setq org-deadline-warning-days 1)

  ;; Hide drawers
  (setopt org-cycle-hide-drawer-startup t)
  (setopt org-startup-folded 'nofold)

  (set-face-attribute 'org-level-1 nil :height 1.3 :weight 'bold :inherit 'fixed-pitch)
  (set-face-attribute 'org-level-2 nil :height 1.2 :weight 'bold :inherit 'fixed-pitch)
  (set-face-attribute 'org-level-3 nil :height 1.1 :weight 'bold :inherit 'fixed-pitch)
  (set-face-attribute 'org-level-4 nil :height 1.0 :weight 'bold :inherit 'fixed-pitch)
  (set-face-attribute 'org-level-5 nil :height 1.0 :weight 'bold :inherit 'fixed-pitch)
  (set-face-attribute 'org-level-6 nil :height 1.0 :weight 'bold :inherit 'fixed-pitch)
  (set-face-attribute 'org-level-7 nil :height 1.0 :weight 'bold :inherit 'fixed-pitch)
  (set-face-attribute 'org-level-8 nil :height 1.0 :weight 'bold :inherit 'fixed-pitch)

  ;; Make the document title a bit bigger
  (set-face-attribute 'org-document-title nil :weight 'bold :height 1.5)

  ;; Make LaTeX previews larger.
  (plist-put org-format-latex-options :scale 1.5)

  ;; (setq org-support-shift-select t)
  (setq org-special-ctrl-a/e t)
  ;; (setq org-footnote-section nil)
  (setq org-html-validation-link nil)
  (setq org-time-stamp-rounding-minutes '(0 15))
  (setq org-log-done t)
  (setq org-todo-keyword-faces
	  '(("DONE" . "green4") ("TODO" . org-warning)))
  (setq org-agenda-files '("/Users/rlridenour/Library/Mobile Documents/iCloud~com~appsonthemove~beorg/Documents/org/"))
  (setq org-agenda-start-on-weekday nil)
  (setq org-agenda-window-setup 'current-window)
  (setq org-link-frame-setup
	  '((vm . vm-visit-folder-other-frame)
	(vm-imap . vm-visit-imap-folder-other-frame)
	(gnus . org-gnus-no-new-news)
	(file . find-file)
	(wl . wl-other-frame)))
  (require 'org-tempo)
  ;; Open directory links in Dired.
  (add-to-list 'org-file-apps '(directory . emacs)))

(setq org-export-backends '(ascii html icalendar latex odt md))
(require `ox-md)

(add-hook 'org-mode-hook #'variable-pitch-mode)
(add-hook 'markdown-mode-hook #'variable-pitch-mode)
(global-set-key (kbd "C-M-S-s-v") #'variable-pitch-mode)

(defun csm/org-word-count ()
  "Count words in region/buffer, estimate pages, and reading time.
Excludes lines beginning with * or #. Prints result in echo area."
  (interactive)
  (let* ((start (if (use-region-p) (region-beginning) (point-min)))
	   (end (if (use-region-p) (region-end) (point-max)))
	   (word-count
	    (save-excursion
	      (goto-char start)
	      (let ((count 0)
		    (inhibit-field-text-motion t))
		(while (< (point) end)
		  (beginning-of-line)
		  (unless (looking-at-p "^[*#<]")
		    (let ((line-end (line-end-position)))
		      (while (re-search-forward "\\w+\\W*" line-end t)
			(setq count (1+ count)))))
		  (forward-line 1))
		count)))
	   (words-per-page 400)
	   (reading-speed 215)
	   (page-count (/ (+ word-count words-per-page -1) words-per-page))
	   (reading-time (/ (+ word-count reading-speed -1) reading-speed)))
    (message "%d words, ~%d pages, ~%d min read"
	       word-count page-count reading-time)))

(defun cc/yank-markdown-as-org ()
  "Yank Markdown text as Org.

This command will convert Markdown text in the top of the `kill-ring'
and convert it to Org using the pandoc utility."
  (interactive)
  (save-excursion
    (with-temp-buffer
	(yank)
	(shell-command-on-region
	 (point-min) (point-max)
	 "pandoc -f markdown -t org --wrap=preserve" t t)
	(kill-region (point-min) (point-max)))
    (yank)))

(defun mb/org-copy-region-as-markdown ()
  "Copy the region (in Org) to the system clipboard as Markdown."
  (interactive)
  (if (use-region-p)
	(let* ((region
		(buffer-substring-no-properties
		 (region-beginning)
		 (region-end)))
	       (markdown
		(org-export-string-as region 'md t '(:with-toc nil))))
	  (gui-set-selection 'CLIPBOARD markdown))))

(use-package org-appear
  :after org
  :commands (org-appear-mode)
  ;; :hook     (org-mode . org-appear-mode)
  :config
  (setq org-hide-emphasis-markers t)  ; Must be activated for org-appear to work
  (setq org-appear-autoemphasis   t   ; Show bold, italics, verbatim, etc.
	  org-appear-autolinks      t   ; Show links
	  org-appear-autosubmarkers t)) ; Show sub and superscripts

(use-package org-modern
  :after org
  :config
  (add-hook 'org-agenda-finalize-hook #'org-modern-agenda)
  )

(require 'ox-beamer)
(with-eval-after-load 'ox-latex
  (add-to-list 'org-latex-classes
		 '("org-article"
		   "\\documentclass{article}
			      [NO-DEFAULT-PACKAGES]
			      [NO-PACKAGES]"
	       ("\\section{%s}" . "\\section*{%s}")
	       ("\\subsection{%s}" . "\\subsection*{%s}")
	       ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
	       ("\\paragraph{%s}" . "\\paragraph*{%s}")
	       ("\\subparagraph{%s}" . "\\subparagraph*{%s}")))
  (add-to-list 'org-latex-classes
	     '("org-handout"
	       "\\documentclass{pdfhandout}
			      [NO-DEFAULT-PACKAGES]
			      [NO-PACKAGES]"
	       ("\\section{%s}" . "\\section*{%s}")
	       ("\\subsection{%s}" . "\\subsection*{%s}")
	       ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
	       ("\\paragraph{%s}" . "\\paragraph*{%s}")
	       ("\\subparagraph{%s}" . "\\subparagraph*{%s}")))
  (add-to-list 'org-latex-classes
	     '("org-obu-letter"
	       "\\documentclass{obuletter}
			      [NO-DEFAULT-PACKAGES]
			      [NO-PACKAGES]"
	       ("\\section{%s}" . "\\section*{%s}")
	       ("\\subsection{%s}" . "\\subsection*{%s}")
	       ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
	       ("\\paragraph{%s}" . "\\paragraph*{%s}")
	       ("\\subparagraph{%s}" . "\\subparagraph*{%s}")))
  (add-to-list 'org-latex-classes
	     '("org-my-letter"
	       "\\documentclass{myletter}
			      [NO-DEFAULT-PACKAGES]
			      [NO-PACKAGES]"
	       ("\\section{%s}" . "\\section*{%s}")
	       ("\\subsection{%s}" . "\\subsection*{%s}")
	       ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
	       ("\\paragraph{%s}" . "\\paragraph*{%s}")
	       ("\\subparagraph{%s}" . "\\subparagraph*{%s}")))
  (add-to-list 'org-latex-classes
	     '("org-beamer"
	       "\\documentclass{beamer}
			      [NO-DEFAULT-PACKAGES]
			      [NO-PACKAGES]"
	       ("\\section{%s}" . "\\section*{%s}")
	       ("\\subsection{%s}" . "\\subsection*{%s}")
	       ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
	       ("\\paragraph{%s}" . "\\paragraph*{%s}")
	       ("\\subparagraph{%s}" . "\\subparagraph*{%s}")))
  (add-to-list 'org-latex-classes
	     '("org-ltx-talk"
	       "\\documentclass{ltx-talk}
			      [NO-DEFAULT-PACKAGES]
			      [NO-PACKAGES]"
	       ("\\section{%s}" . "\\section*{%s}")
	       ("\\subsection{%s}" . "\\subsection*{%s}")
	       ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
	       ("\\paragraph{%s}" . "\\paragraph*{%s}")
	       ("\\subparagraph{%s}" . "\\subparagraph*{%s}"))))
(setq org-export-with-smart-quotes t)
(with-eval-after-load 'ox-latex
  (add-to-list 'org-export-smart-quotes-alist
	     '("en-us"
	       (primary-opening   :utf-8 "“" :html "&ldquo;" :latex "\\enquote{"  :texinfo "``")
	       (primary-closing   :utf-8 "”" :html "&rdquo;" :latex "}"           :texinfo "''")
	       (secondary-opening :utf-8 "‘" :html "&lsquo;" :latex "\\enquote*{" :texinfo "`")
	       (secondary-closing :utf-8 "’" :html "&rsquo;" :latex "}"           :texinfo "'")
	       (apostrophe        :utf-8 "’" :html "&rsquo;"))))

;; (setq org-latex-pdf-process '("arara %f"))
(setq org-latex-pdf-process '("mkl %f"))

(defun rlr/org-mkpdf ()
  "Make PDF with pdf latexmk."
  (interactive)
  (save-buffer)
  (org-latex-export-to-latex)
  (async-shell-command-no-window (concat "mkp " (shell-quote-argument(file-name-nondirectory (file-name-with-extension buffer-file-name "tex"))))))

(defun rlr/org-open-pdf ()
  "Open PDF in background with default viewer."
  (interactive)
  (async-shell-command-no-window (concat "open -g " (shell-quote-argument(file-name-nondirectory (file-name-with-extension buffer-file-name "pdf"))))))

(defun rlr/org-mklua ()
  "Make PDF with lua latexmk."
  (interactive)
  (save-buffer)
  (org-latex-export-to-latex)
  (async-shell-command-no-window (concat "mkl " (shell-quote-argument(file-name-nondirectory (file-name-with-extension buffer-file-name "tex"))))))

(defun rlr/org-arara ()
  "Make PDF with Arara."
  (interactive)
  (save-buffer)
  (org-arara-export-to-latex)
  (async-shell-command-no-window (concat "mkarara " (shell-quote-argument(file-name-sans-extension (buffer-file-name)))".tex")))

(defun rlr/org-date ()
  "Update existing date: timestamp on a Hugo post."
  (interactive)
  (save-excursion (
		     goto-char 1)
		    (re-search-forward "^#\\+date:")
		    (let ((beg (point)))
		      (end-of-line)
		      (delete-region beg (point)))
		    (insert (concat " " (format-time-string "%B %e, %Y")))))

(setopt
 org-latex-to-html-convert-command "latexmlc literal:%i --profile=math 2>/dev/null"
 org-html-with-latex 'html)

(use-package org-auto-tangle
  :hook (org-mode . org-auto-tangle-mode))

;; Org-capture
(setq org-capture-templates
	'(
	  ("t" "Todo" entry (file+headline "/Users/rlridenour/Library/Mobile Documents/iCloud~com~appsonthemove~beorg/Documents/org/tasks.org" "Inbox")
	   "** TODO %?\n  %i\n  %a")
	  ("e" "Event" entry (file+headline "/Users/rlridenour/Library/Mobile Documents/iCloud~com~appsonthemove~beorg/Documents/org/events.org" "Future")
	   "** %? %T")
	  ("b" "Bookmark" entry (file+headline "/Users/rlridenour/Library/Mobile Documents/com~apple~CloudDocs/org/bookmarks.org" "Inbox")
	   "* %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n\n" :empty-lines 1)
	  ("c" "Quick note" entry (file "/Users/rlridenour/Library/Mobile Documents/com~apple~CloudDocs/Documents/notes/quick-notes.org")
	   "* %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n\n" :empty-lines 1)
	  ("j" "Journelly Entry" entry
	   (file "/Users/rlridenour/Library/Mobile Documents/iCloud~com~xenodium~Journelly/Documents/Journelly.org")
	   "* %U @ -\n%?" :prepend t)))

(with-eval-after-load 'org-capture
  (add-to-list 'org-capture-templates
		 '("n" "New note (with Denote)" plain
		   (file denote-last-path)
		   #'denote-org-capture
		   :no-save t
		   :immediate-finish nil
		   :kill-buffer t
		   :jump-to-captured t)))

(setq org-refile-targets
	'((nil :maxlevel . 1)
	  (org-agenda-files :maxlevel . 1)))

(define-key global-map "\C-cc" 'org-capture)

(defun rlr/org-sort ()
  (mark-whole-buffer)
  (org-sort-entries nil ?a))

(add-to-list 'safe-local-variable-values
	       '(before-save-hook . (rlr/org-sort)))

(use-package org-super-agenda
  :after org
  :config
  (setq org-agenda-skip-scheduled-if-done t
	  org-agenda-skip-deadline-if-done t
	  setq org-agenda-skip-scheduled-if-deadline-is-shown t
	  org-agenda-skip-deadline-prewarning-if-scheduled t
	  org-agenda-include-deadlines t
	  org-deadline-warning-days 1
	  org-agenda-block-separator nil
	  org-agenda-compact-blocks t
	  org-agenda-start-day nil ;; i.e. today
	  org-agenda-span 1
	  org-agenda-window-setup "current-window"
	  org-agenda-include-diary nil
	  org-agenda-start-on-weekday nil)
  (setq org-agenda-time-grid
	  '((daily today remove-match)
	()
	"......"
	""))
  (org-super-agenda-mode))

(setq org-agenda-custom-commands
	'(("d" "Agenda for today" agenda ""
	   ((org-agenda-overriding-header "Today's agenda")
	    (org-agenda-span 'day)
	    ))))

(defun today-agenda ()
  "Display today's agenda"
  (interactive)
  (org-agenda nil "d")
  )
(today-agenda)

(with-eval-after-load 'org
  (add-to-list
   'org-agenda-custom-commands
   `("c" "Today - Full View"
     ((agenda ""
		((org-agenda-entry-types '(:timestamp :sexp))
		 (org-agenda-overriding-header
		  (concat "CALENDAR Today "
			  (format-time-string "%a %d" (current-time))))
		 (org-agenda-span 'day)))
	(tags-todo "LEVEL=1+inbox"
		   ((org-agenda-overriding-header "INBOX (Unscheduled)")))
	(tags-todo "DEADLINE<\"<+1d>\"+DEADLINE>\"<-1d>\""
		   ((org-agenda-overriding-header "DUE TODAY")
		    (org-agenda-skip-function
		     '(org-agenda-skip-entry-if 'notdeadline))
		    (org-agenda-sorting-strategy '(priority-down))))
	(tags-todo "DEADLINE<\"<today>\""
		   ((org-agenda-overriding-header "OVERDUE")
		    (org-agenda-skip-function
		     '(org-agenda-skip-entry-if 'notdeadline))
		    (org-agenda-sorting-strategy '(priority-down))))
	(agenda ""
		((org-agenda-entry-types '(:scheduled))
		 (org-agenda-overriding-header "SCHEDULED")
		 (org-agenda-skip-function
		  '(org-agenda-skip-entry-if 'todo 'done))
		 (org-agenda-sorting-strategy
		  '(priority-down time-down))
		 (org-agenda-span 'day)
		 (org-agenda-start-on-weekday nil)))
	(todo "DONE"
	      ((org-agenda-overriding-header "COMPLETED"))))
     ((org-agenda-format-date "")
	(org-agenda-start-with-clockreport-mode nil))) t))

(defun agenda-home ()
  (interactive)
  (org-agenda-list 1)
  (delete-other-windows))

(add-hook 'server-after-make-frame-hook #'agenda-home)

(defun refresh-agenda-periodic-function ()
  "Recompute the Org Agenda buffer(s) periodically."
  (ignore-errors
    (when (get-buffer "*Org Agenda*")
	(with-selected-window (get-buffer-window "*Org Agenda*")
	  (org-agenda-redo-all)))))

;; Refresh agenda every 600 seconds (10 minutes)
(run-with-timer 60 60 'refresh-agenda-periodic-function)

(setq org-agenda-current-time-string "now - - - - - - -")

(custom-set-faces
 '(org-agenda-current-time ((t (:foreground "red3")))))

(global-set-key (kbd "s-d") #'agenda-home)

(defun rlr/agenda-links ()
  (end-of-buffer)
  (insert-file-contents "/Users/rlridenour/Library/Mobile Documents/com~apple~CloudDocs/org/agenda-links.org")
  (while (org-activate-links (point-max))
    (goto-char (match-end 0)))
  ;; (end-of-buffer)
  ;; (insert (concat "\n\n" (get-votd)))
  (beginning-of-buffer))

(add-hook 'org-agenda-finalize-hook #'rlr/agenda-links)

(setq org-return-follows-link t)

(setopt org-link-elisp-skip-confirm-regexp "rlr.*")

(setq appt-time-msg-list nil)    ;; clear existing appt list
;; (setq appt-message-warning-time '15)  ;; send first warning 15 minutes before appointment
(org-agenda-to-appt) ;; generate the appt list from org agenda files on emacs launch
(run-at-time "24:01" 3600 'org-agenda-to-appt) ;; update appt list hourly
(add-hook 'org-finalize-agenda-hook 'org-agenda-to-appt) ;; update appt list on agenda view

(use-package org-contrib
:after org
    :config
    (require 'ox-extra)
    (ox-extras-activate '(ignore-headlines))
    (require 'org-tempo)
    ;; (require 'ox-rss)
)

(use-package org-autolist
  :hook (org-mode . org-autolist-mode))

(use-package org-bulletproof)

(defun my/org-toggle-emphasis (type)
  "Toggle org emphasis TYPE (a character) at point."
  (cl-labels ((in-emph (re)
		  "See if in org emphasis given by RE."
		  (and (org-in-regexp re 2)
		       (>= (point) (match-beginning 3))
		       (<= (point) (match-end 4))))
		(de-emphasize ()
		  "Remove most recently matched org emphasis markers."
		  (save-excursion
		    (replace-match "" nil nil nil 3)
		    (delete-region (match-end 4) (1+ (match-end 4))))))
    (let* ((res (vector org-emph-re org-verbatim-re))
	     (idx (cl-case type (?/ 0) (?* 0) (?_ 0) (?+ 0) (?= 1) (?~ 1)))
	     (re (aref res idx))
	     (other-re (aref res (- 1 idx)))
	     (type-re (string-replace (if (= idx 1) "=~" "*/_+")
				      (char-to-string type) re))
	     add-bounds offset is-word)
	(save-match-data
	  (if (region-active-p)
	      (if (in-emph type-re) (de-emphasize) (org-emphasize type))
	    (if (eq (char-before) type) (backward-char))
	    (if (in-emph type-re)       ;nothing marked, in emph text?
		(de-emphasize)
	      (setq add-bounds          ; check other flavors
		    (if (or (in-emph re) (in-emph other-re))
			(cons (match-beginning 4) (match-end 4))
		      (setq is-word t)
		      (bounds-of-thing-at-point 'symbol))))
	    (if add-bounds
		(let ((off (- (point) (car add-bounds)))
		      (at-end (= (point) (cdr add-bounds))))
		  (set-mark (car add-bounds))
		  (goto-char (cdr add-bounds))
		  (org-emphasize type)  ;deletes marked region!
		  (unless is-word       ; delete extra spaces
		    (goto-char (car add-bounds))
		    (when (eq (char-after) ?\s) (delete-char 1))
		    (goto-char (+ 2 (cdr add-bounds)))
		    (when (eq (char-after) ?\s) (delete-char 1)))
		  (goto-char (+ (car add-bounds) off
				(cond ((= off 0) 0) (at-end 2) (t 1)))))
	      (if is-word (org-emphasize type))))))))

(use-package org-upcoming-modeline
  :after org                               ; if you don't want it to start until org has been loaded
  :config
  (org-upcoming-modeline-mode))

(use-package org-people
  :after org)

(use-package org-mac-link
:defer 1)

(use-package org-web-tools
  :defer 10)

(defun rlr/save-web-page-as-org-file ()
  (interactive)
  (org-mac-link-safari-get-frontmost-url)
  (setq rlr-org-link (current-kill 0 t))
  (setq rlr-org-link (s-chop-left 2 rlr-org-link))
  (setq rlr-org-link (s-chop-right 2 rlr-org-link))
  (setq rlr-org-link (s-split "\\]\\[" rlr-org-link))
  (setq rlr-org-url (pop rlr-org-link))
  (setq rlr-org-title (pop rlr-org-link))
  (setq rlr-org-title (s-replace-all '(("." . "") (":" . "") ("/" . "")) rlr-org-title))
  (setq rlr-org-filename (s-dashed-words rlr-org-title))
  (org-web-tools-read-url-as-org rlr-org-url)
  (write-file (concat "~/icloud/web-saves/" rlr-org-title ".org")))

(defvar rlrt-filename)

(defun rlrt-make-filename (string)
  (s-downcase  (s-join "-" (s-split " " (replace-regexp-in-string "\\bthe \\b\\|\\band \\b\\|\\b[a-z]\\b \\|\\b[a-z][a-z]\\b \\|[[:punct:]]" "" string)))))

(defun rlrt-new-handout (rlrt-title)
  (interactive "sTitle: ")

  ;; Make filename
  (setq rlrt-filename (rlrt-make-filename rlrt-title))

  ;; Create directory
  (make-directory rlrt-filename)

  ;; Create main org file
  (find-file (s-concat rlrt-filename "/" rlrt-filename "-handout.org"))
  (insert (s-concat "#+TITLE: " rlrt-title) ?\n"#+AUTHOR: Dr. Randy Ridenour" ?\n "#+DATE: "(format-time-string "%B %e, %Y") ?\n)
  (insert-file-contents "~/.config/emacs/teaching-templates/handout/handout.org")
  (goto-char (point-max))
  (save-buffer))

(defun rlrt-new-syllabus (rlrt-title)
  (interactive "sTitle: ")

  ;; Make filename
  (setq rlrt-filename (rlrt-make-filename rlrt-title))

  ;; Create directory
  (make-directory rlrt-filename)

  ;; Create main org file
  (find-file (s-concat rlrt-filename "/" rlrt-filename "-syllabus.org"))
  (insert-file-contents "~/.config/emacs/teaching-templates/syllabus/syllabus.org")
  (goto-char (point-max))
  (insert (s-concat "#+include: \"" rlrt-filename "-data.org\" :minlevel 1"))
  (save-buffer)
  (kill-buffer)

  ;; Create Canvas file
  (find-file (s-concat rlrt-filename "/canvas.org"))
  (insert-file-contents "~/.config/emacs/teaching-templates/syllabus/canvas.org")
  (save-buffer)
  (kill-buffer)

  ;; Create data file
  (find-file (s-concat rlrt-filename "/" rlrt-filename "-data.org")))

(defun rlrt-new-lecture (rlrt-title)
  (interactive "sTitle: ")

  ;; Make filename
  (setq rlrt-filename (rlrt-make-filename rlrt-title))

  ;; Create directory
  (make-directory rlrt-filename)

(find-file (s-concat rlrt-filename "/" rlrt-filename "-slides.org"))
(insert-file-contents "~/.config/emacs/teaching-templates/lecture/slides.org")
(goto-char (point-max))
(insert (s-concat "#+include: \"" rlrt-filename "-data.org\" :minlevel 1"))
(save-buffer)
(kill-buffer)

(find-file (s-concat rlrt-filename "/" rlrt-filename "-notes.org"))
(insert-file-contents "~/.config/emacs/teaching-templates/lecture/notes.org")
(goto-char (point-max))
(insert (s-concat "#+include: \"" rlrt-filename "-data.org\" :minlevel 1"))
(save-buffer)
(kill-buffer)

(find-file (s-concat rlrt-filename "/canvas.org"))
(insert-file-contents "~/.config/emacs/teaching-templates/lecture/canvas.org")
(goto-char (point-max))
(save-buffer)
(kill-buffer)

(find-file (s-concat rlrt-filename "/" rlrt-filename "-data.org"))
(insert (s-concat "#+TITLE: " rlrt-title) ?\n)
(yas-expand-snippet (yas-lookup-snippet "beamer-data")))

(defun make-slides ()
  (async-shell-command-no-window "mkslides"))

(defun make-notes ()
  (async-shell-command-no-window "mknotes"))

(defun lecture-slides ()
  "publish org data file as beamer slides"
  (interactive)
  (save-buffer)
  (find-file "*-slides.org" t)
  (org-beamer-export-to-latex)
  (kill-buffer)
  (make-slides)
  (find-file "*-data.org" t))

(defun rlr/create-frametitle ()
  "Convert title to frametitle."
  (interactive)
  (goto-char 1)
  (while (ignore-errors
	     (re-search-forward "begin{frame}.*]"))
    (insert "\n \\frametitle")))

(defun lecture-notes ()
  "publish org data file as beamer notes"
  (interactive)
  (save-buffer)
  (find-file "*-notes.org" t)
  (org-beamer-export-to-latex)
  (kill-buffer)
  (find-file "*-notes.tex" t)
  (rlr/create-frametitle)
  (save-buffer)
  (kill-buffer)
  (make-notes)
  (find-file "*-data.org" t))

(defun canvas-copy ()
  "Copy html for canvas pages"
  (interactive)
  (save-buffer)
  (org-html-export-to-html)
  (shell-command "canvas"))

(defun canvas-notes ()
  "Copy HTML slide notes for Canvas"
  (interactive)
  (save-buffer)
  (shell-command "canvas-notes")
  (find-file "canvas.org")
  (canvas-copy)
  (kill-buffer)
  (delete-file "canvas-data.org"))

(defun make-handout ()
  "publish org data file as LaTeX handout and Canvas HTML"
  (interactive)
  (save-buffer)
  ;; (find-file "*-handout.org" t)
  (rlr/org-mklua)
  ;; (kill-buffer)
  ;; (shell-command "canvas-notes")
  ;; (find-file "canvas.org" t)
  (org-html-export-to-html)
  (shell-command "canvas-handout"))

(defun make-html ()
  (interactive)
  (save-buffer)
  (org-html-export-to-html)
  (shell-command "canvas-handout"))

(defun make-syllabus ()
  "publish org data file as LaTeX syllabus and Canvas HTML"
  (interactive)
  (save-buffer)
  (find-file "*-syllabus.org" t)
  (rlr/org-mklua)
  (kill-buffer)
  (shell-command "canvas-notes")
  (find-file "canvas.org" t)
  (org-html-export-to-html)
  (shell-command "canvas")
  (kill-buffer)
  (delete-file "canvas-data.org")
  (find-file "*-data.org" t))

(defun  create-args ()
  (interactive)
  (kill-ring-save (region-beginning) (region-end))
  (exchange-point-and-mark)
  (yas-expand-snippet (yas-lookup-snippet "arg-wrap-tex"))
  (previous-line)
  ;; (previous-line)
  (org-beginning-of-line)
  (forward-word)
  (forward-char)
  (forward-char)
  (insert "\\underline{")
  (org-end-of-line)
  (insert "}")
  (next-line)
  (org-beginning-of-line)
  (forward-word)
  (insert "[\\phantom{\\(\\therefore\\)}]")
  (next-line)
  (next-line)
  (org-return)
  (org-return)
  (org-yank)
  (exchange-point-and-mark)
  (yas-expand-snippet (yas-lookup-snippet "arg-wrap-html")))

(defun  create-tex-arg ()
  (interactive)
  (yas-expand-snippet (yas-lookup-snippet "arg-wrap-tex"))
  (previous-line)
  (previous-line)
  (forward-word)
  (forward-char)
  (forward-char)
  (insert "\\underline{")
  (org-end-of-line)
  (insert "}")
  (next-line)
  (org-beginning-of-line)
  (forward-word)
  (insert "[\\phantom{\\(\\therefore\\)}]")
  (next-line)
  (next-line)
  (org-return)
  (org-return))

(defun duplicate-slide-note ()
  (interactive)
  (search-backward ":END:")
  (next-line)
  (kill-ring-save (point)
		    (progn
		      (search-forward "** ")
		      (beginning-of-line)
		      (point))
		    )
  (yas-expand-snippet (yas-lookup-snippet "beamer article notes"))
  (yank))

(defun duplicate-all-slide-notes ()
  (interactive)
  (save-excursion
    (end-of-buffer)
    (newline)
    (newline)
    ;; Need a blank slide at the end to convert the last note.
    (insert "** ")
    (beginning-of-buffer)
    (while (ignore-errors
	       (search-forward ":BEAMER_ENV: note"))
	(next-line)
	(next-line)
	(kill-ring-save (point)
			(progn
			  (search-forward "** ")
			  (beginning-of-line)
			  (point))
			)
	(yas-expand-snippet (yas-lookup-snippet "beamer article notes"))
	(yank))
    ;; Delete the blank slide that was added earlier.
    (end-of-buffer)
    (search-backward "**")
    (kill-line)
    )
  (save-buffer))

(defun rlrt-new-article (rlrt-title)
  (interactive "sTitle: ")

  ;; Make filename
  (setq rlrt-filename (rlrt-make-filename rlrt-title))

  ;; Create directory
  (make-directory rlrt-filename)

  (find-file (s-concat rlrt-filename "/" rlrt-filename ".org"))
  (insert (s-concat "#+TITLE: " rlrt-title) ?\n)
  (yas-expand-snippet (yas-lookup-snippet "rlrt-lua-article")))

(defun convert-qti-nyit ()
  (interactive)
  ;; Copy all to a temp buffer and set to text mode.
  (let ((old-buffer (current-buffer)))
    (with-temp-buffer
	(insert-buffer-substring old-buffer)
	(text-mode)
	;; convert multiple correct answer and essay questions
	(beginning-of-buffer)
	(while (re-search-forward "^[:space:]*-" nil t)
	  (replace-match ""))
	;; Change correct multiple answer options to "*"
	(beginning-of-buffer)
	(let ((case-fold-search nil))
	  (while (re-search-forward "\[X\]" nil t)
	    (replace-match "*")))
	;; Mark short answer responses with "**"
	(beginning-of-buffer)
	(while (re-search-forward "+" nil t)
	  (replace-match "*"))
	;; remove whitespace at beginning of lines
	(beginning-of-buffer)
	(while (re-search-forward "^\s-*" nil t)
	  (replace-match ""))
	(beginning-of-buffer)
	(while (re-search-forward "\\(^[0-9]\\)" nil t)
	  (replace-match "\n\\1"))
	;; move correct answer symbol to beginning of line
	(beginning-of-buffer)
	(while (re-search-forward "\\(^.*\\)\\(\*$\\)" nil t)
	  (replace-match "\*\\1"))
	(delete-trailing-whitespace)
	;; delete empty line at end and beginning
	(end-of-buffer)
	(delete-char -1)
	(beginning-of-buffer)
	(kill-line)
	;; Copy result to clipboard
	(clipboard-kill-ring-save (point-min) (point-max))
	)
    )
  (browse-url "https://www.nyit.edu/its/canvas_exam_converter")
  )

(defun create-roll-sheet ()
  (interactive)
  ;; Append signature cells to each line.
  (goto-char (point-min))
  (replace-regexp "$" " |  | ")
  ;; kill bottom half of buffer and move to top
  (setq lines (count-lines (point-min) (point-max)))
  (setq lines (+ lines (% lines 2) ))
  (setq midpoint (+ (/ lines 2) 1))
  (goto-line midpoint)
  (kill-region (point) (point-max))
  (beginning-of-buffer)
  ;; Append each line from kill-ring to remaining lines.
  (dolist (cur-line-to-insert (split-string (current-kill 0) "\n"))
    (if (eobp)
	(newline)
      (move-end-of-line nil))
    (insert cur-line-to-insert)
    (forward-line))
  ;; Prepend pipe character to each line and kill last line.
  (goto-char (point-min))
  (replace-regexp "^" "| ")
  (kill-whole-line)
  ;; insert LaTeX table format and header lines
  (goto-char (point-min))
  (insert "#+ATTR_LATEX: :environment tblr :align hline{3-Z}={solid},row{2-Z}={f,10mm},colspec={XXXX}\n| *Name*              | *Signature* | *Name*              | *Signature* | \n")
  ;; Clean up table.
  (org-ctrl-c-ctrl-c)
  ;; Insert LaTeX header.
  (goto-char (point-min))
  (yas-expand-snippet (yas-lookup-snippet "roll-sheet")))

(defun formatted-copy ()
  "Export region to HTML, and copy it to the clipboard."
  (interactive)
  (save-window-excursion
    (let* ((buf (org-export-to-buffer 'html "*Formatted Copy*" nil nil t t))
	     (html (with-current-buffer buf (buffer-string))))
	(with-current-buffer buf
	  (shell-command-on-region
	   (point-min)
	   (point-max)
	   "textutil -stdin -format html -convert rtf -stdout | pbcopy"))
	(kill-buffer buf))))

;; (global-set-key (kbd "H-w") 'formatted-copy)

(major-mode-hydra-define org-mode
  (:quit-key "q")
  ("Export"
   (
    ("m" rlr/org-mklua "Make PDF with LuaLaTeX")
    ("p" rlr/org-mkpdf "Make PDF with PDFLaTeX")
    ("o" rlr/org-open-pdf "View PDF")
    ("h" make-html "HTML")
    ("el" org-latex-export-to-latex "Org to LaTeX")
    ("eb" org-beamer-export-to-pdf "Org to Beamer-PDF")
    ("eB" org-beamer-export-to-latex "Org to Beamer-LaTeX")
    ("s" lecture-slides "Lecture slides")
    ("n" lecture-notes "Lecture notes")
    ("ep" present "Present slides")
    ("ec" canvas-copy "Copy HTML for Canvas")
    ("es" canvas-notes "HTML Canvas notes")
    ("eS" make-syllabus "Syllabus")
    ("eh" make-handout "Handout")
    ("c" tex-clean "clean aux")
    ("C" tex-clean-all "clean all"))
   "Edit"
   (("dd" org-deadline "deadline")
    ("ds" org-schedule "schedule")
    ("r" org-refile "refile")
    ("du" rlr/org-date "update date stamp")
    ;; ("fn" org-footnote-new "insert footnote")
    ("ff" org-footnote-action "edit footnote")
    ("fc" citar-insert-citation "citation")
    ("il" org-mac-link-safari-insert-frontmost-url "insert safari link")
    ("s" org-insert-structure-template "insert structure block")
    ("w" csm/org-word-count "word count")
    ("y" yankpad-set-category "set yankpad"))
   "View"
   (("va" org-appear-mode :toggle t)
    ("vl" org-toggle-link-display :toggle t)
    ("vv" visible-mode :toggle t)
    ("vi" consult-org-heading "iMenu")
    ("vu" org-toggle-pretty-entities "org-pretty")
    ("vI" org-toggle-inline-images "Inline images"))
   "Blog"
   (("bn" rlrt-new-post "New draft")
    ("bt" orgblog-add-tag "Add tag")
    ("bi" orgblog-insert-image "Insert image")
    ("bp" orgblog-publish-draft "Publish draft")
    ("bb" orgblog-build "Build site")
    ("bs" orgblog-serve "Serve site")
    ("bd" orgblog-push "Push to Github"))
   "Notes"
   (("1" denote-link "link to note"))))

(use-package tex
  :ensure auctex
  :init
  (setq TeX-parse-self t
	  TeX-auto-save t
	  TeX-electric-math nil
	  LaTeX-electric-left-right-brace nil
	  TeX-electric-sub-and-superscript nil
	  LaTeX-item-indent 0
	  TeX-quote-after-quote nil
	  TeX-clean-confirm nil
	  TeX-source-correlate-mode t
	  TeX-source-correlate-method 'synctex
	  TeX-view-program-selection '((output-pdf "PDF Viewer"))
	  TeX-view-program-list
	  '(("PDF Viewer" "/Applications/Skim.app/Contents/SharedSupport/displayline -b -g %n %o %b"))))

(defun raise-emacs-on-aqua()
  (shell-command "osascript -e 'tell application \"Emacs\" to activate' "))
(add-hook 'server-switch-hook 'raise-emacs-on-aqua)
(defun tex-clean ()
  (interactive)
  (shell-command "latexmk -c"))

(defun tex-clean-all ()
  (interactive)
  (shell-command "latexmk -C"))

(defun arara-all ()
  (interactive)
  (async-shell-command "mkall"))

(defun rlr/tex-mkpdf ()
  "Compile with pdf latexmk."
  (interactive)
  (save-buffer)
  (async-shell-command-no-window (concat "mkp " (shell-quote-argument(file-name-nondirectory buffer-file-name))))
  (TeX-view))

(defun rlr/tex-mktc ()
  "Compile continuously with pdf latexmk."
  (interactive)
  (async-shell-command-no-window (concat "mkpc " (shell-quote-argument(file-name-nondirectory buffer-file-name)))))

(defun rlr/tex-mklua ()
  "Compile with lua latexmk."
  (interactive)
  (save-buffer)
  (async-shell-command-no-window (concat "mkl " (shell-quote-argument(file-name-nondirectory buffer-file-name))))
  (TeX-view))

(defun rlr/tex-mkluac ()
  "Compile continuously with lua latexmk."
  (interactive)
  (async-shell-command-no-window (concat "mklc " (shell-quote-argument(file-name-nondirectory buffer-file-name)))))

(defun latex-word-count ()
  (interactive)
  (let* ((this-file (buffer-file-name))
	   (word-count
	    (with-output-to-string
	      (with-current-buffer standard-output
		(call-process "texcount" nil t nil "-brief" this-file)))))
    (string-match "\n$" word-count)
    (message (replace-match "" nil nil word-count))))

(defalias 'mcq-item
   (kmacro "C-a C-k \\ c h o i c e SPC { C-y <down>"))

(defun mcq-wrap-line ()
  "Wrap the current line in \choice{}"
  (interactive)
  (beginning-of-line)
  (skip-chars-forward " \t")
  (insert "\\choice{")
  (end-of-line)
  (insert "}"))

(defun mcq-wrap-selection ()
  "Wrap the selected text in \choice{}"
  (interactive)
  (if (use-region-p)
      (let ((begin (region-beginning))
	    (end (region-end)))
	(save-excursion
	  (goto-char end)
	  (insert "}")
	  (goto-char begin)
	  (insert "\\choice{")))
    (insert "\\choice{}")
    (backward-char)))

(defun convert-quiz-claude-to-org ()
"Convert markdown-style quiz questions from Claude to Org mode format. Operates on the current buffer or active region."
  (interactive)
  (let ((start (if (use-region-p) (region-beginning) (point-min)))
	(end   (if (use-region-p) (region-end)       (point-max)))
	(question-num 0))
    (save-excursion
      ;; Remove '---' separator lines
      (goto-char start)
      (while (re-search-forward "^---\n?" end t)
	(replace-match ""))

      ;; Convert **Question N:** to "N."
      (goto-char start)
      (while (re-search-forward "^\\*\\*Question [0-9]+:\\*\\* " end t)
	(setq question-num (1+ question-num))
	(replace-match (format "%d. " question-num)))

      ;; Convert "- A)" "- B)" etc. to "     a)" "     b)" etc.
      (goto-char start)
      (while (re-search-forward "^- \\([A-D]\\))" end t)
	(replace-match (format "     %s)" (downcase (match-string 1)))))

      ;; Remove blank lines
      (goto-char start)
      (while (re-search-forward "^[[:blank:]]*\n" end t)
	(replace-match "")))))

(defun rlr/org-mc-to-latex-questions (beg end)
  "Convert org-mode multiple choice questions in region to LaTeX format. Questions are numbered lines followed by lettered choices (a-z). Correct answers are marked with * after the choice text."
  (interactive "r")
  (let* ((text (buffer-substring-no-properties beg end))
	   (lines (split-string text "\n"))
	   (result '())
	   (in-question nil))
    (dolist (line lines)
	(cond
	 ;; Numbered question line: "2. Question text"
	 ((string-match "^[[:space:]]*[0-9]+\\.[[:space:]]+\\(.+\\)$" line)
	  (when in-question
	    (push "  \\end{question}" result)
	(push "" result))
	  (push "  \\begin{question}" result)
	  (push (format "    %s" (match-string 1 line)) result)
	  (setq in-question t))
	 ;; Choice line: "  a) Choice text" or "  a) Choice text*"
	 ((string-match "^[[:space:]]*[a-z])[[:space:]]+\\(.+?\\)\\(*\\)?[[:space:]]*$" line)
	  (let* ((text (match-string 1 line))
		 (correct (match-string 2 line))
		 (tag (if correct "\\choice[!]" "\\choice")))
	    (push (format "    %s {%s}" tag text) result)))))
    (when in-question
	(push "  \\end{question}" result))
    (let ((output (mapconcat #'identity (nreverse result) "\n")))
	(goto-char beg)
	(delete-region beg end)
	(insert output))))

(defun rlr/copy-mcq-to-scratch ()
  "Copy the multiple choice question at point to the *scratch* buffer."
  (interactive)
  (save-excursion
    (let* ((question-start
	    (progn
	      (end-of-line)
	      (if (re-search-backward "^[0-9]+\\." nil t)
		  (point)
		(error "No question found at point"))))
	   (question-end
	    (progn
	      (goto-char question-start)
	      (forward-line 1)
	      (if (re-search-forward "^[0-9]+\\." nil t)
		  (match-beginning 0)
		(point-max))))
	   (text (buffer-substring-no-properties question-start question-end)))
      (with-current-buffer (get-buffer-create "*scratch*")
	(goto-char (point-max))
	(insert text)))))

(defun rlr/delete-mcq-at-point ()
  "Delete the multiple choice question at point, including all its choices."
  (interactive)
  (save-excursion
    (beginning-of-line)
    ;; If on a choice line, move up to the question line first
    (unless (looking-at "[[:space:]]*[0-9]+\\.")
	(re-search-backward "^[[:space:]]*[0-9]+\\." nil t))
    (let ((start (line-beginning-position))
	    (end (progn
		   (forward-line 1)
		   (if (re-search-forward "^[[:space:]]*[0-9]+\\." nil t)
		       (match-beginning 0)
		     (point-max)))))
	(kill-region start end)))
  (org-list-repair))

(use-package citar
  :bind
  (("C-c C-b" . #'citar-insert-citation)
  :map minibuffer-local-map
	  ("M-b" . #'citar-insert-preset))
  :custom
  (org-cite-global-bibliography '("~/Dropbox/bibtex/rlr.bib"))
  (citar-bibliography '("~/Dropbox/bibtex/rlr.bib"))
  (org-cite-csl-styles-dir "/usr/local/texlive/2025/texmf-dist/tex/latex/citation-style-language/styles")
  (org-cite-export-processors
   '((md . (csl "chicago-author-date.csl"))
     (latex biblatex)
     (odt . (csl "chicago-author-date.csl"))
     (t . (csl "chicago-author-date.csl")))))

(use-package ebib
  :commands (ebib)
  :config
  (setq ebib-bibtex-dialect 'biblatex)
  ;;(evil-set-initial-state 'ebib-index-mode 'emacs)
  ;;(evil-set-initial-state 'ebib-entry-mode 'emacs)
  ;;(evil-set-initial-state 'ebib-log-mode 'emacs)
  :custom
  (ebib-preload-bib-files '("~/Dropbox/bibtex/rlr.bib")))

(use-package denote
    :config
    (setq denote-directory "/Users/rlridenour/Library/Mobile Documents/com~apple~CloudDocs/Documents/notes/denote/")
    (setq denote-infer-keywords t)
    (setq denote-sort-keywords t)
    (setq denote-prompts '(title keywords))
    (setq denote-date-format nil)
:commands denote)

(use-package consult-denote
  :bind
  ("C-c n f" . #'consult-denote-find)
  ("C-c n g" . #'consult-denote-grep)
  :config
  (consult-denote-mode 1))

(use-package denote-org
  :commands
  ;; I list the commands here so that you can discover them more
  ;; easily.  You might want to bind the most frequently used ones to the `org-mode-map'.
  ( denote-org-link-to-heading
    denote-org-backlinks-for-heading

    denote-org-extract-org-subtree

    denote-org-convert-links-to-file-type
    denote-org-convert-links-to-denote-type

    denote-org-dblock-insert-files
    denote-org-dblock-insert-links
    denote-org-dblock-insert-backlinks
    denote-org-dblock-insert-missing-links
    denote-org-dblock-insert-files-as-headings))

(use-package consult-notes
  :after (consult denote)
  :config
  (consult-notes-denote-mode))

(use-package citar-denote
  :after (citar denote)
  :config
  (citar-denote-mode)
  (setq citar-open-always-create-notes t))

(use-package denote-menu
  :after denote)

(use-package denote-search
  :custom
  ;; Disable help string (set it once you learn the commands)
  ;; (denote-search-help-string "")
  ;; Display keywords in results buffer
  (denote-search-format-heading-function #'denote-search-format-heading-with-keywords)
  :commands (denote-search))

(use-package grove
  :bind-keymap ("C-c v" . grove-command-map)
  :custom
  (grove-directory "/Users/rlridenour/Library/Mobile Documents/com~apple~CloudDocs/Documents/notes/grove/")
  :config
  (global-grove-mode 1))

(defvar orgblog-directory "~/sites/orgblog/" "Path to the Org mode blog.")
(defvar orgblog-public-directory "~/sites/orgblog/docs/" "Path to the blog public directory.")
(defvar orgblog-posts-directory "~/sites/orgblog/posts/" "Path to the blog public directory.")
(defvar orgblog-drafts-directory "~/sites/orgblog/drafts/" "Path to the blog public directory.")

(defun rlrt-new-post (rlrt-title)
  (interactive "sTitle: ")
  ;; Make filename
  (setq rlrt-filename (rlrt-make-filename rlrt-title))
  (find-file (s-concat orgblog-drafts-directory (format-time-string "%Y-%m-%d-") rlrt-filename ".org"))
  (insert (s-concat "#+TITLE: " rlrt-title) ?\n)
  (yas-expand-snippet (yas-lookup-snippet "orgblogt")))

(defun orgblog-insert-image ()
  (interactive)
  (insert "#+begin_center
#+ATTR_HTML: :width 100% :height
")
  (insert "[[" (file-relative-name (read-file-name "Insert file name: " "~/sites/orgblog/images/posts/")) "]]
#+end_center

")
  )

(defun orgblog-publish-draft ()
  (interactive)
  (save-buffer)
  (copy-file (buffer-file-name) "~/sites/orgblog/posts/")
  (delete-file (buffer-file-name) t)
  (kill-buffer)
  (dired "~/sites/orgblog/posts"))

(defun orgblog-build ()
  (interactive)
  (progn
    (find-file "~/sites/orgblog/publish.el")
    (eval-buffer)
    (org-publish-all)
    (webfeeder-build "atom.xml"
		       "./docs"
		       "https://randyridenour.net/"
		       (let ((default-directory (expand-file-name "./docs")))
			 (remove "posts/index.html"
				 (directory-files-recursively "posts"
							      ".*\\.html$")))
		       :title "Randy Ridenour"
		       :description "Blog posts by Randy Ridenour")
    (kill-buffer))
  (message "Build complete!"))

(defun orgblog-serve ()
  (interactive)
  (progn
    (async-shell-command "orgblog-serve")
    (sleep-for 2)
    (async-shell-command "open http://localhost:3000")))

(defun orgblog-push ()
  (interactive)
  (async-shell-command "orgblog-push"))

(setq org-html-footnotes-section "<div id=\"footnotes\">
<h2 class=\"footnotes\">%s</h2>
<div id=\"text-footnotes\">
%s
</div>
</div>")

(defvar yt-iframe-format
  ;; You may want to change your width and height.
  (concat "<iframe width=\"440\""
	    " height=\"335\""
	    " src=\"https://www.youtube.com/embed/%s\""
	    " frameborder=\"0\""
	    " allowfullscreen>%s</iframe>"))

(org-add-link-type
 "yt"
 (lambda (handle)
   (browse-url
    (concat "https://www.youtube.com/embed/"
	      handle)))
 (lambda (path desc backend)
   (cl-case backend
     (html (format yt-iframe-format
		     path (or desc "")))
     (latex (format "\href{%s}{%s}"
		      path (or desc "video"))))))

(use-package website2org
:vc (:url "https://github.com/rtrppl/website2org")
  :config
  (setq website2org-directory "~/icloud/web-saves/website2org/") ;; if needed, see below
  (setq website2org-additional-meta nil)
  :bind
  ("C-M-s-<down>" . #'website2org)
   ("C-M-s-<up>" . #'website2org-temp))

(use-package htmlize
  :commands (htmlize-file))

(use-package eww
  :config
  (defun rlr/open-eww-link-new-buffer ()
    (interactive)
    (link-hint-copy-link)
    (tab-new)
    (setq new-buffer-url (current-kill 0 t))
    (switch-to-buffer (generate-new-buffer "*eww*"))
    (eww-mode)
    (eww new-buffer-url))
  (defun rlr/eww-toggle-images ()
    "Toggle whether images are loaded and reload the current page from cache."
    (interactive)
    (setq-local shr-inhibit-images (not shr-inhibit-images))
    (eww-reload t)
    (message "Images are now %s"
	       (if shr-inhibit-images "off" "on")))
  ;; (define-key eww-mode-map (kbd "I") #'rlr/eww-toggle-images)
  ;; (define-key eww-link-keymap (kbd "I") #'rlr/eww-toggle-images)
  ;; minimal rendering by default
  (setq-default shr-inhibit-images t)   ; toggle with `I`
  (setq-default shr-use-fonts t)      ; toggle with `F`
  (defun rrnet ()
    (interactive)
    (eww-browse-url "randyridenour.net")
    )
  (defun sep ()
    (interactive)
    (eww-browse-url "plato.stanford.edu")
    )
  :bind
  (nil
  :map eww-mode-map
	      ("I" . #'rlr/eww-toggle-images)
	      ("f" . #'link-hint-open-link)
	      ("F" . #'rlr/open-eww-link-new-buffer)
	      ("T" . #'eww-toggle-fonts)))

(defun jao-eww-to-org (&optional dest)
  "Render the current eww buffer using org markup.
 If DEST, a buffer, is provided, insert the markup there."
  (interactive)
  (unless (org-region-active-p)
    (let ((shr-width 80)) (eww-readable)))
  (let* ((start (if (org-region-active-p) (region-beginning) (point-min)))
	    (end (if (org-region-active-p) (region-end) (point-max)))
	    (buff (or dest (generate-new-buffer "*eww-to-org*")))
	    (link (eww-current-url))
	    (title (or (plist-get eww-data :title) "")))
    (with-current-buffer buff
	 (insert "#+title: " title "\n#+link: " link "\n\n")
	 (org-mode))
    (save-excursion
	 (goto-char start)
	 (while (< (point) end)
	   (let* ((p (point))
		  (props (text-properties-at p))
		  (k (seq-find (lambda (x) (plist-get props x))
			       '(shr-url image-url outline-level face)))
		  (prop (and k (list k (plist-get props k))))
		  (next (if prop
			    (next-single-property-change p (car prop) nil end)
			  (next-property-change p nil end)))
		  (txt (buffer-substring (point) next))
		  (txt (replace-regexp-in-string "\\*" "·" txt)))
	     (with-current-buffer buff
	       (insert
		(pcase prop
		  ((and (or `(shr-url ,url) `(image-url ,url))
			(guard (string-match-p "^http" url)))
		   (let ((tt (replace-regexp-in-string "\n\\([^$]\\)" " \\1" txt)))
		     (org-link-make-string url tt)))
		  (`(outline-level ,n)
		   (concat (make-string (- (* 2 n) 1) ?*) " " txt "\n"))
		  ('(face italic) (format "/%s/ " (string-trim txt)))
		  ('(face bold) (format "*%s* " (string-trim txt)))
		  (_ txt))))
	     (goto-char next))))
    (pop-to-buffer buff)
    (goto-char (point-min))))

(defun rlr/open-safari-page-in-eww ()
  (interactive)
  (org-mac-link-safari-get-frontmost-url)
  (setq rlr-org-link (current-kill 0 t))
  (setq rlr-org-link (s-chop-left 2 rlr-org-link))
  (setq rlr-org-link (s-chop-right 2 rlr-org-link))
  (setq rlr-org-link (s-split "\\]\\[" rlr-org-link))
  (setq rlr-org-url (pop rlr-org-link))
  (eww rlr-org-url))

(defun nrsv-open-eww ()
  (interactive)
  (setq nrsv-passage (read-string "Passage: "))
  (setq nrsv-passage (s-replace " " "%20" oremus-passage))
  (setq oremus-link (concat "https://bible.oremus.org/?version=NRSV&passage=" oremus-passage "&vnum=NO&fnote=NO&omithidden=YES"))
  (eww-browse-url oremus-link))

(defun nrsv-open-default-browser ()
  (interactive)
  (setq nrsv-passage (read-string "Passage: "))
  (setq nrsv-passage (s-replace " " "%20" oremus-passage))
  (setq oremus-link (concat "https://bible.oremus.org/?version=NRSV&passage=" oremus-passage "&vnum=NO&fnote=NO&omithidden=YES"))
  (browse-url oremus-link))

(defun oremus-eww-cleanup ()
  (interactive)
  (beginning-of-buffer)
  (while (re-search-forward "" nil t)
    (replace-match "\""))
  (beginning-of-buffer)
  (while (re-search-forward "" nil t)
    (replace-match "\""))
  (beginning-of-buffer)
  (while (re-search-forward "" nil t)
    (replace-match "\'"))
  (beginning-of-buffer)
  (while (re-search-forward "" nil t)
    (replace-match "\'"))
  (beginning-of-buffer)
  (while (re-search-forward "" nil t)
    (replace-match "\'"))
  (beginning-of-buffer)
  (while (re-search-forward "" nil t)
    (replace-match "—"))
  )

(defun nrsv-insert-passage ()
  (interactive)
  (setq oremus-passage (read-string "Passage: "))
  (setq oremus-passage (s-replace " " "%20" oremus-passage))
  (setq oremus-link (concat "https://bible.oremus.org/?version=NRSV&passage=" oremus-passage "&vnum=NO&fnote=NO&omithidden=YES"))
  (switch-to-buffer (url-retrieve-synchronously oremus-link))
  (beginning-of-buffer)
  (search-forward "passageref\">")
  (kill-region (point) 1)
  (search-forward "</div><!-- class=\"bibletext\" -->")
  (beginning-of-line)
  (kill-region (point) (point-max))
  (beginning-of-buffer)
  (while (re-search-forward "<p>" nil t)
    (replace-match "\n"))
  (beginning-of-buffer)
  (while (re-search-forward "<!.+?->" nil t)
    (replace-match ""))
  (beginning-of-buffer)
  (while (re-search-forward "<.+?>" nil t)
    (replace-match ""))
  (beginning-of-buffer)
  (while (re-search-forward "&nbsp;" nil t)
    (replace-match " "))
  (beginning-of-buffer)
  (while (re-search-forward "&#147;" nil t)
    (replace-match "\""))
  (beginning-of-buffer)
  (while (re-search-forward "&#148;" nil t)
    (replace-match "\""))
  (beginning-of-buffer)
  (while (re-search-forward "&#145;" nil t)
    (replace-match "\'"))
  (beginning-of-buffer)
  (while (re-search-forward "&#146;" nil t)
    (replace-match "\'"))
  (beginning-of-buffer)
  (while (re-search-forward "&#151;" nil t)
    (replace-match "---"))
  (delete-extra-blank-lines)
  (clipboard-kill-ring-save (point-min) (point-max))
  (kill-buffer)
  (yank))

(use-package link-hint
  :bind
  ("s-," . #'link-hint-open-link)
   ("C-c l o" . #'link-hint-open-link)
   ("C-c l c" . #'link-hint-copy-link))

(defun rlr/link-hint-open-link-in-secondary-browser ()
  (interactive)
  (let ((browse-url-browser-function  browse-url-secondary-browser-function))
    (link-hint-open-link)))

(use-package fish-mode
  :defer t
  :mode "\\.fish\\'")

(use-package calc
:bind
("C-M-S-s-c" . #'calc))

(pretty-hydra-define hydra-toggle
  (:color teal :quit-key "q" :title "Toggle")
  (" "
   (("a" abbrev-mode "abbrev" :toggle t)
    ("b" toggle-debug-on-error "debug" (default value 'debug-on-error))
    ("d" global-devil-mode "devil" :toggle t)
    ("e" evil-mode "evil" :toggle t)
    ("i" aggressive-indent-mode "indent" :toggle t)
    ("f" auto-fill-mode "fill" :toggle t)
    ("l" display-line-numbers-mode "linum" :toggle t)
    ("m" variable-pitch-mode "variable-pitch" :toggle t)
    ("p" smartparens-mode "smartparens" :toggle t)
    ("P" electric-pair-mode "electric-pair" :toggle t))
   " "
   (("t" toggle-truncate-lines "truncate" :toggle t)
    ("s" whitespace-mode "whitespace" :toggle t)
    ("c" cdlatex-mode "cdlatex" :toggle t)
    ("o" olivetti-mode "olivetti" :toggle t)
    ("r" read-only-mode "read-only" :toggle t)
    ("v" view-mode "view" :toggle t)
    ("W" wc-mode "word-count" :toggle t)
    ("S" auto-save-visited-mode "auto-save" :toggle t)
    ("C" cua-selection-mode "rectangle" :toggle t))))

(pretty-hydra-define hydra-buffer
  (:color teal :quit-key "q" :title "Buffers and Files")
  ("Open"
   (("b" ibuffer "ibuffer")
    ("m" consult-bookmark "bookmark")
    ("w" consult-buffer-other-window "other window")
    ("f" consult-buffer-other-frame "other frame")
    ("d" crux-recentf-find-directory "recent directory")
    ("a" crux-open-with "open in default app"))
   "Actions"
   (("D" crux-delete-file-and-buffer "delete file")
    ("R" crux-rename-file-and-buffer "rename file")
    ("K" rlr/kill-other-buffers "kill other buffers")
    ("N" nuke-all-buffers "Kill all buffers")
    ("c" crux-cleanup-buffer-or-region "fix indentation"))
   "Misc"
   (("t" crux-visit-term-buffer "ansi-term")
    ("T" iterm-goto-filedir-or-home "iTerm2")
    ("i" crux-find-user-init-file "init.el")
    ("s" crux-find-shell-init-file "fish config"))
   ))

(pretty-hydra-define hydra-locate
  (:color teal :quit-key "q" title: "Search")
  ("Buffer"
   (("c" pulsar-highlight-pulse "find cursor")
    ("h" consult-org-heading "org heading")
    ("l" consult-goto-line "goto-line")
    ("i" consult-imenu "imenu")
    ("m" consult-mark "mark")
    ("o" consult-outline "outline"))
   "Global"
   (("M" consult-global-mark "global-mark")
    ("n" consult-notes "notes")
    ("r" consult-ripgrep "ripgrep")
    ("d" rlr/consult-rg "rg from dir")
    ("f" rlr/consult-fd "find from dir"))
   "Files"
   (("e" rr/open-init-file "Emacs init")
    ("s" goto-shell-init "Fish functions"))
   ))

(pretty-hydra-define hydra-window
  (:color teal :quit-key "q" title: "Windows")
  ("Windows"
   (("w m" minimize-window "minimize window")
    ("w s" crux-transpose-windows "swap windows")
    ("w S" shrink-window-if-larger-than-buffer "shrink to fit")
    ("w b" balance-windows "balance windows")
    ("w t" toggle-window-split "toggle split")
    ("w v" enlarge-window" grow taller" :exit nil)
    ("w h" enlarge-window-horizontally "grow wider" :exit nil))
   "Frames"
   (("f m" iconify-frame "minimize frame")
    ("f d" delete-other-frames "delete other frames"))
   "Tabs"
   (("t c" tab-close-other "close other tabs")
    ("t m" tab-move "move tab right")
    ("t b" tab-bar-history-back "restore previous windows")
    ("t f" tab-bar-history-forward "undo restore windows"))
   "Writeroom"
   (("W" writeroom-mode "toggle writeroom")
    ("M" writeroom-toggle-mode-line "toggle modeline"))))

(pretty-hydra-define hydra-new
  (:color teal :quit-key "q" title: "New")
  ("Frame"
   (("f" make-frame-command "new frame"))
   "Denote"
   (("c" org-capture "capture")
    ("n" denote "note")
    ("v" denote-menu-list-notes "view notes")
    ("j" denote-journal-extras-new-or-existing-entry "journal"))
   "Writing"
   (("b" rlrt-new-post "blog post")
    ("a" rlrt-new-article "article"))
   "Teaching"
   (("l" rlrt-new-lecture "lecture")
    ("h" rlrt-new-handout "handout")
    ("s" rlrt-new-syllabus "syllabus"))
   ))

(pretty-hydra-define hydra-logic
  (:color pink :quit-key "0" :title "Logic")
  ("Operators"
   (
    ;; ("1" (rr/insert-unicode "NOT SIGN") "¬")
    ("1" (rr/insert-unicode "TILDE OPERATOR") "∼")
    ;; ("2" (rr/insert-unicode "AMPERSAND") "&")
    ("2" (rr/insert-unicode "BULLET") "•")
    ("3" (rr/insert-unicode "LOGICAL OR") "v")
    ("4" (rr/insert-unicode "SUPERSET OF") "⊃")
    ;; ("4" (rr/insert-unicode "RIGHTWARDS ARROW") "→")
    ("5" (rr/insert-unicode "IDENTICAL TO") "≡")
    ;; ("5" (rr/insert-unicode "LEFT RIGHT ARROW") "↔")
    ("6" (rr/insert-unicode "THERE EXISTS") "∃")
    ("7" (rr/insert-unicode "FOR ALL") "∀")
    ("8" (rr/insert-unicode "WHITE MEDIUM SQUARE") "□")
    ("9" (rr/insert-unicode "LOZENGE") "◊")
    ("`" (rr/insert-unicode "NOT EQUAL TO") "≠"))
   "Space"
   (("?" (rr/insert-unicode "MEDIUM MATHEMATICAL SPACE") "Narrow space"))
   "Quit"
   (("0" quit-window "quit" :color blue))
   ))

(pretty-hydra-define hydra-math
  (:color pink :quit-key "?" :title "Math")
  ("Operators"
   (("1" (rr/insert-unicode "NOT SIGN") "¬")
    ("2" (rr/insert-unicode "AMPERSAND") "&")
    ("3" (rr/insert-unicode "LOGICAL OR") "v")
    ("4" (rr/insert-unicode "RIGHTWARDS ARROW") "→")
    ("5" (rr/insert-unicode "LEFT RIGHT ARROW") "↔")
    ("6" (rr/insert-unicode "THERE EXISTS") "∃")
    ("7" (rr/insert-unicode "FOR ALL") "∀")
    ("8" (rr/insert-unicode "WHITE MEDIUM SQUARE") "□")
    ("9" (rr/insert-unicode "LOZENGE") "◊"))
   "Sets"
   (("R" (rr/insert-unicode "DOUBLE-STRUCK CAPITAL R") "ℝ real")
    ("N" (rr/insert-unicode "DOUBLE-STRUCK CAPITAL N") "ℕ natural")
    ("Z" (rr/insert-unicode "DOUBLE-STRUCK CAPITAL Z") "ℤ integer")
    ("Q" (rr/insert-unicode "DOUBLE-STRUCK CAPITAL Q") "ℚ rational")
    ("Q" (rr/insert-unicode "DOUBLE-STRUCK CAPITAL Q") "ℚ rational")
    ("Q" (rr/insert-unicode "DOUBLE-STRUCK CAPITAL Q") "ℚ rational")
    )
   "Space"
   (("?" (rr/insert-unicode "MEDIUM MATHEMATICAL SPACE") "Narrow space"))
   "Quit"
   (("?" quit-window "quit" :color blue))
   ))

(pretty-hydra-define hydra-hydras
  (:color teal :quit-key "q" :title "Hydras")
  ("System"
   (("t" hydra-toggle/body)
    ("b" hydra-buffer/body)
    ("h" hydra-hugo/body)
    ("p" powerthesaurus-hydra/body))
   "Unicode"
   (("l" hydra-logic/body "logic")
    ("m" hydra-math/body))))

(pretty-hydra-define hydra-surround
  (:color teal :quit-key "q" :title "Surround")
  ("Surround"
   (("s" surround-insert "surround insert")
    ("c" surround-change "surround change")
    ("k" surround-kill "kill inner")
    ("K" surround-kill-outer "kill outer")
    ("M" surround-mark-outer "mark outer")
    ("m" surround-mark "mark inner")
    ("d" surround-delete "surround delete")
    )))

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
