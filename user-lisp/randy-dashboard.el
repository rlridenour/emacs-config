;;; randy-dashboard.el --- Personal dashboard buffer -*- lexical-binding: t -*-

;;; Commentary:
;; A startup dashboard showing today's org-agenda and quick-access links.
;; Load with (require 'randy-dashboard) or (load "path/to/randy-dashboard.el")
;; then call M-x randy-dashboard-open, or add to your init:
;;   (add-hook 'emacs-startup-hook #'randy-dashboard-open)

;;; Configuration — edit these to match your paths:

(defvar randy-dashboard-org-files
  '(("Tasks"    . "~/org/tasks.org")
    ("Journal"  . "/Users/rlridenour/Library/Mobile Documents/iCloud~com~xenodium~Journelly/Documents/Journelly.org"))
  "Alist of (LABEL . PATH) for Org file quick links.")

(defvar randy-dashboard-project-dirs
  '(("Emacs config" . "~/.config/emacs/")
    ("Courses"      . "/Users/rlridenour/icloud/teaching"))
  "Alist of (LABEL . PATH) for project directory quick links.")

(defvar randy-dashboard-mu4e-bookmarks
  '(("Inbox"     . "maildir:/obu/INBOX OR maildir:/fastmail/INBOX OR maildir:/gmail/INBOX")
    ("Unread"    . "flag:unread AND NOT flag:trashed AND NOT maildir:/gmail/[Gmail]/Trash AND NOT maildir:/gmail/[Gmail]/Spam AND NOT maildir:/obu/Junk AND NOT maildir:/fastmail/Spam")
    ("Today"     . "date:today"))
  "Alist of (LABEL . MU4E-QUERY) for mail quick links.")

(defvar randy-dashboard-agenda-days 1
  "Number of days to show in the agenda section (1 = today only).")

(defvar randy-dashboard-clock-format "%-I:%M %p"
  "`format-time-string' spec for the clock section time.")

(defvar randy-dashboard-live-clock t
  "When non-nil, the clock ticks live via a repeating timer.
When nil, the clock is static and only updates on refresh (\\[randy-dashboard-open]).")

(defvar randy-dashboard-clock-interval 60
  "Seconds between live clock updates.
Use 60 when your format shows only minutes, or 1 for a seconds display.")

(defvar randy-dashboard-recent-files-count 5
  "Number of recent files to list in the Recent Files section.")

;;; Internal implementation

(defconst randy-dashboard-buffer-name "*Dashboard*")

(defface randy-dashboard-title-face
  '((t :inherit font-lock-keyword-face :height 1.4 :weight bold))
  "Face for the dashboard title.")

(defface randy-dashboard-section-face
  '((t :inherit font-lock-type-face :height 1.15 :weight bold :underline t))
  "Face for section headings.")

(defface randy-dashboard-label-face
  '((t :inherit font-lock-constant-face))
  "Face for link labels.")

(defface randy-dashboard-hint-face
  '((t :inherit font-lock-comment-face :slant italic))
  "Face for hint/footer text.")

(defun randy-dashboard--insert-rule ()
  "Insert a subtle horizontal rule."
  (insert (propertize (concat "\n" (make-string 60 ?─) "\n\n")
                      'face 'font-lock-comment-face)))

(defun randy-dashboard--insert-header ()
  "Insert the dashboard title and timestamp."
  (let* ((title "  ✦  Randy Ridenour")
         (date  (format-time-string "%A, %B %-d, %Y")))
    (insert (propertize title 'face 'randy-dashboard-title-face))
    (insert "\n")
    (insert (propertize (concat "  " date "\n") 'face 'randy-dashboard-hint-face))
    (randy-dashboard--insert-rule)))

(defun randy-dashboard--insert-section (title)
  "Insert a section heading TITLE."
  (insert (propertize (concat "  " title "\n\n") 'face 'randy-dashboard-section-face)))

(defun randy-dashboard--insert-link (label action &optional hint)
  "Insert a clickable link with LABEL that runs ACTION (a thunk).
Optional HINT is displayed in comment face after the label."
  (insert "    ")
  (insert-button
   (format "%-22s" label)
   'action (lambda (_) (funcall action))
   'follow-link t
   'face 'randy-dashboard-label-face
   'mouse-face 'highlight
   'help-echo (format "Open %s" label))
  (when hint
    (insert (propertize hint 'face 'randy-dashboard-hint-face)))
  (insert "\n"))

(defun randy-dashboard--insert-org-links ()
  "Insert the Org files section."
  (randy-dashboard--insert-section "Org Files")
  (dolist (entry randy-dashboard-org-files)
    (let ((label (car entry))
          (path  (cdr entry)))
      (randy-dashboard--insert-link
       label
       (lambda () (find-file (expand-file-name path)))
       ;; (abbreviate-file-name (expand-file-name path))
       )))
  (insert "\n"))

(defun randy-dashboard--insert-project-links ()
  "Insert the Projects section."
  (randy-dashboard--insert-section "Projects")
  (dolist (entry randy-dashboard-project-dirs)
    (let ((label (car entry))
          (path  (cdr entry)))
      (randy-dashboard--insert-link
       label
       (lambda () (dired (expand-file-name path)))
       ;; (abbreviate-file-name (expand-file-name path))
       )))
  (insert "\n"))

(defun randy-dashboard--insert-mu4e-links ()
  "Insert the Mail section."
  (randy-dashboard--insert-section "Mail")
  (dolist (entry randy-dashboard-mu4e-bookmarks)
    (let ((label (car entry))
          (query (cdr entry)))
      (randy-dashboard--insert-link
       label
       (lambda ()
         (if (fboundp 'mu4e)
             (progn (mu4e)
                    (mu4e-search query))
           (message "mu4e is not available."))))))
  (insert "\n"))

(defun randy-dashboard--agenda-string ()
  "Return today's org-agenda as a plain string."
  (require 'org-agenda)
  (save-window-excursion
    (let ((org-agenda-window-setup 'current-window)
          (org-agenda-sticky nil))
      ;; org-agenda-list builds and switches to the agenda buffer
      (org-agenda-list nil nil randy-dashboard-agenda-days)
      (prog1
          (buffer-substring-no-properties (point-min) (point-max))
        ;; Clean up the agenda buffer we just created
        (when (string= (buffer-name) org-agenda-buffer-name)
          (kill-buffer))))))

(defun randy-dashboard--insert-agenda ()
  "Insert today's org-agenda."
  (randy-dashboard--insert-section "Today's Agenda")
  (condition-case err
      (let ((agenda-text (randy-dashboard--agenda-string)))
        (if (string-blank-p (string-trim agenda-text))
            (insert (propertize "    Nothing scheduled today.\n" 'face 'randy-dashboard-hint-face))
          ;; Indent each agenda line and strip the org-agenda header cruft
          (dolist (line (split-string agenda-text "\n"))
            (unless (or (string-match-p "^Week-agenda" line)
                        (string-match-p "^Press.*for help" line))
              (insert "  " line "\n")))))
    (error
     (insert (propertize (format "    Agenda unavailable: %s\n" (error-message-string err))
                         'face 'randy-dashboard-hint-face))))
  (insert "\n"))

(defface randy-dashboard-clock-face
  '((t :inherit font-lock-string-face :height 1.6 :weight bold))
  "Face for the clock time.")

(defvar-local randy-dashboard--clock-timer nil
  "Buffer-local repeating timer driving the live clock, or nil.")

(defvar-local randy-dashboard--clock-start nil
  "Marker at the start of the clock time text.")

(defun randy-dashboard--clock-text ()
  "Return the propertized clock line: time followed by timezone."
  (concat
   (propertize (format-time-string randy-dashboard-clock-format)
               'face 'randy-dashboard-clock-face)
   (propertize (format-time-string "   %Z") 'face 'randy-dashboard-hint-face)))

(defun randy-dashboard--insert-clock ()
  "Insert a clock section showing the current time.
Records a single start marker so the timer can replace the clock
line in place without any marker drift."
  (randy-dashboard--insert-section "Clock")
  (insert "    ")
  ;; One marker, default insertion type (nil): it stays anchored at the
  ;; start of the time text. Updates replace from here to end of line,
  ;; so nothing below the clock is ever touched.
  (setq randy-dashboard--clock-start (copy-marker (point) nil))
  (insert (randy-dashboard--clock-text))
  (insert "\n\n"))

(defun randy-dashboard--update-clock (buffer)
  "Refresh the clock line in BUFFER in place.
Replace from the start marker to the end of its line.  Cancel the
driving timer if BUFFER or its marker are no longer valid."
  (if (and (buffer-live-p buffer)
           (buffer-local-value 'randy-dashboard--clock-start buffer)
           (marker-buffer (buffer-local-value 'randy-dashboard--clock-start buffer)))
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (save-excursion
            (goto-char randy-dashboard--clock-start)
            (delete-region randy-dashboard--clock-start (line-end-position))
            (goto-char randy-dashboard--clock-start)
            (insert (randy-dashboard--clock-text)))))
    ;; Buffer or marker gone: stop ticking.
    (randy-dashboard--clock-teardown buffer)))

(defun randy-dashboard--clock-teardown (&optional buffer)
  "Cancel the live-clock timer for BUFFER (defaults to current buffer)."
  (let ((buf (or buffer (current-buffer))))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (when (timerp randy-dashboard--clock-timer)
          (cancel-timer randy-dashboard--clock-timer))
        (setq randy-dashboard--clock-timer nil)))))

(defun randy-dashboard--clock-initial-delay ()
  "Seconds until the next clock-interval boundary.
For a 60-second interval this is the time until the next minute, so
updates land on the minute rather than 60s after rendering."
  (let* ((interval randy-dashboard-clock-interval)
         (secs (string-to-number (format-time-string "%S")))
         (delay (- interval (mod secs interval))))
    ;; A boundary-aligned delay of 0 means fire a full interval later.
    (if (zerop delay) interval delay)))

(defun randy-dashboard--clock-start-timer ()
  "Start the live-clock timer for the current buffer.
Cancel any existing timer first so timers never stack.  The first
tick is aligned to the next interval boundary (see
`randy-dashboard--clock-initial-delay')."
  (randy-dashboard--clock-teardown)
  (when randy-dashboard-live-clock
    (let ((buffer (current-buffer)))
      (setq randy-dashboard--clock-timer
            (run-with-timer (randy-dashboard--clock-initial-delay)
                            randy-dashboard-clock-interval
                            #'randy-dashboard--update-clock
                            buffer))
      ;; Ensure the timer dies with the buffer.
      (add-hook 'kill-buffer-hook #'randy-dashboard--clock-teardown nil t))))

(defun randy-dashboard--recent-files ()
  "Return up to `randy-dashboard-recent-files-count' recent file paths."
  (require 'recentf)
  (unless recentf-mode (recentf-mode 1))
  (seq-take (seq-filter #'stringp recentf-list)
            randy-dashboard-recent-files-count))

(defun randy-dashboard--insert-recent-files ()
  "Insert the Recent Files section."
  (randy-dashboard--insert-section "Recent Files")
  (let ((files (randy-dashboard--recent-files)))
    (if (null files)
        (insert (propertize "    No recent files.\n" 'face 'randy-dashboard-hint-face))
      (dolist (path files)
        (randy-dashboard--insert-link
         (file-name-nondirectory path)
         (lambda () (find-file path))))))
  (insert "\n"))

(defun randy-dashboard--insert-footer ()
  "Insert key hints at the bottom."
  (randy-dashboard--insert-rule)
  (insert (propertize
           "  g  refresh    a  org-agenda    m  mu4e    q  quit\n"
           'face 'randy-dashboard-hint-face)))

(defun randy-dashboard--keymap ()
  "Return the dashboard keymap."
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "g") #'randy-dashboard-open)
    (define-key map (kbd "q") #'quit-window)
    (define-key map (kbd "a") #'org-agenda-list)
    (define-key map (kbd "m") (lambda () (interactive)
                                (if (fboundp 'mu4e) (mu4e)
                                  (message "mu4e not available"))))
    (define-key map (kbd "n") #'forward-button)
    (define-key map (kbd "p") #'backward-button)
    (define-key map (kbd "TAB") #'forward-button)
    (define-key map [backtab] #'backward-button)
    map))

;;;###autoload
(defun randy-dashboard-open ()
  "Open (or refresh) the personal dashboard buffer."
  (interactive)
  (let ((buf (get-buffer-create randy-dashboard-buffer-name)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "\n")
        (randy-dashboard--insert-header)
        (randy-dashboard--insert-clock)
        (randy-dashboard--insert-agenda)
        (randy-dashboard--insert-org-links)
        (randy-dashboard--insert-project-links)
        (randy-dashboard--insert-recent-files)
        (randy-dashboard--insert-mu4e-links)
        (randy-dashboard--insert-footer)
        (insert "\n"))
      (use-local-map (randy-dashboard--keymap))
      (setq-local cursor-type nil)
      (setq buffer-read-only t)
      (goto-char (point-min))
      ;; (Re)start the live clock; this cancels any prior timer first.
      (randy-dashboard--clock-start-timer))
    (switch-to-buffer buf)))

(provide 'randy-dashboard)
;;; randy-dashboard.el ends here
