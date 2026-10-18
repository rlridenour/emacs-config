;;; rlr-eww.el --- EWW and browsing helpers -*- lexical-binding: t; -*-

;;; Code:

(require 'subr-x)
(require 'seq)
(require 's)

(defvar eww-data)
(defvar shr-inhibit-images)
(defvar shr-width)
(declare-function delete-extra-blank-lines "init")
(declare-function eww "eww")
(declare-function eww-mode "eww")
(declare-function eww-browse-url "eww")
(declare-function eww-reload "eww")
(declare-function eww-readable "eww")
(declare-function eww-current-url "eww")
(declare-function link-hint-copy-link "link-hint")
(declare-function link-hint-open-link "link-hint")
(declare-function org-mac-link-safari-get-frontmost-url "org-mac-link")
(declare-function org-link-make-string "ol")
(declare-function org-region-active-p "org-compat")

;;;###autoload
(defun rlr/open-eww-link-new-buffer ()
  "Open the link selected with link-hint in EWW in a new tab."
  (interactive)
  (link-hint-copy-link)
  (tab-new)
  (let ((url (current-kill 0 t)))
    (switch-to-buffer (generate-new-buffer "*eww*"))
    (eww-mode)
    (eww url)))

;;;###autoload
(defun rlr/eww-toggle-images ()
  "Toggle whether images are loaded and reload the current page from cache."
  (interactive)
  (setq-local shr-inhibit-images (not shr-inhibit-images))
  (eww-reload t)
  (message "Images are now %s" (if shr-inhibit-images "off" "on")))

;;;###autoload
(defun rrnet ()
  "Open randyridenour.net in EWW."
  (interactive)
  (eww-browse-url "randyridenour.net"))

;;;###autoload
(defun sep ()
  "Open the Stanford Encyclopedia of Philosophy in EWW."
  (interactive)
  (eww-browse-url "plato.stanford.edu"))

;;;###autoload
(defun rlr/open-safari-page-in-eww ()
  "Open the frontmost Safari page in EWW."
  (interactive)
  (org-mac-link-safari-get-frontmost-url)
  (let* ((link (current-kill 0 t))
         (parts (s-split "\\]\\[" (s-chop-right 2 (s-chop-left 2 link)))))
    (eww (car parts))))

;;;###autoload
(defun rlr/link-hint-open-link-in-secondary-browser ()
  "Open a link-hint link with `browse-url-secondary-browser-function'."
  (interactive)
  (let ((browse-url-browser-function browse-url-secondary-browser-function))
    (link-hint-open-link)))

;;;###autoload
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

;;;; NRSV passages from the Oremus Bible Browser (https://bible.oremus.org/)

(defun nrsv--url (passage)
  "Return the Oremus URL for PASSAGE."
  (concat "https://bible.oremus.org/?version=NRSV&passage="
          (s-replace " " "%20" passage)
          "&vnum=NO&fnote=NO&omithidden=YES"))

;;;###autoload
(defun nrsv-open-eww ()
  "Open an NRSV passage in EWW."
  (interactive)
  (eww-browse-url (nrsv--url (read-string "Passage: "))))

;;;###autoload
(defun nrsv-open-default-browser ()
  "Open an NRSV passage in the default browser."
  (interactive)
  (browse-url (nrsv--url (read-string "Passage: "))))

;;;###autoload
(defun oremus-eww-cleanup ()
  "Replace Windows-1252 punctuation in the current buffer."
  (interactive)
  (dolist (pair '(("\u0093" . "\"") ("\u0094" . "\"")
                  ("\u0091" . "'") ("\u0092" . "'")
                  ("\u0097" . "—")))
    (goto-char (point-min))
    (while (search-forward (car pair) nil t)
      (replace-match (cdr pair) t t))))

;;;###autoload
(defun nrsv-insert-passage ()
  "Fetch an NRSV passage from Oremus and insert it as plain text."
  (interactive)
  (switch-to-buffer (url-retrieve-synchronously (nrsv--url (read-string "Passage: "))))
  (goto-char (point-min))
  (search-forward "passageref\">")
  (delete-region 1 (point))
  (search-forward "</div><!-- class=\"bibletext\" -->")
  (beginning-of-line)
  (delete-region (point) (point-max))
  (dolist (pair '(("<p>" . "\n")
                  ("<!.+?->" . "")
                  ("<.+?>" . "")
                  ("&nbsp;" . " ")
                  ("&#147;" . "\"")
                  ("&#148;" . "\"")
                  ("&#145;" . "'")
                  ("&#146;" . "'")
                  ("&#151;" . "---")))
    (goto-char (point-min))
    (while (re-search-forward (car pair) nil t)
      (replace-match (cdr pair))))
  (delete-extra-blank-lines)
  (clipboard-kill-ring-save (point-min) (point-max))
  (kill-buffer)
  (yank))

(provide 'rlr-eww)
;;; rlr-eww.el ends here
