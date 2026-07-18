;;; rlr-create-typst-bib.el --- Build a local sources.bib from cite keys -*- lexical-binding: t; -*-

;; Author: Randy Ridenour
;; Keywords: tools, bib, tex, org, typst

;;; Commentary:

;; Scans the current Org or Typst buffer for citation keys and
;; copies the corresponding BibTeX records from a master
;; bibliography file into a local "sources.bib" file in the same
;; directory as the visited file.
;;
;; Entry point: `rlr-create-typst-bib'.

;;; Code:

(defgroup rlr-create-typst-bib nil
  "Create a local sources.bib from cite keys in the current buffer."
  :group 'tools)

(defcustom rlr-create-typst-bib-main-bib-file "~/github/rlr-bib/rlr.bib"
  "Path to the master BibTeX file that cite keys are copied from."
  :type 'file
  :group 'rlr-create-typst-bib)

(defcustom rlr-create-typst-bib-output-file-name "sources.bib"
  "Name of the local BibTeX file to create/update."
  :type 'string
  :group 'rlr-create-typst-bib)

(defconst rlr-create-typst-bib--key-charset "[[:alnum:]:_.-]"
  "Character class matching a single character of a cite key.")

(defun rlr-create-typst-bib--collect-keys ()
  "Return a list of unique citation keys found in the current buffer.

Typst keys are matched inside angle brackets, e.g. <Sandel:2007vi>.
Org keys are matched after \"@\", e.g. [cite:@Sandel:2007vi]."
  (let ((ext (and buffer-file-name
                   (downcase (or (file-name-extension buffer-file-name) ""))))
        (keys nil))
    (save-excursion
      (goto-char (point-min))
      (cond
       ((string= ext "typ")
        (while (re-search-forward
                (concat "<\\(" rlr-create-typst-bib--key-charset "+\\)>") nil t)
          (push (match-string-no-properties 1) keys)))
       ((string= ext "org")
        (while (re-search-forward
                (concat "@\\(" rlr-create-typst-bib--key-charset "+\\)") nil t)
          (push (match-string-no-properties 1) keys)))
       (t (user-error "Buffer is not a .typ or .org file"))))
    (delete-dups (nreverse keys))))

(defun rlr-create-typst-bib--existing-keys (file)
  "Return the list of cite keys already present in FILE."
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (let (keys)
        (goto-char (point-min))
        (while (re-search-forward
                (concat "@[[:alpha:]]+[ \t]*{[ \t]*\\("
                        rlr-create-typst-bib--key-charset "+\\)[ \t]*,")
                nil t)
          (push (match-string-no-properties 1) keys))
        keys))))

(defun rlr-create-typst-bib--find-entry (key)
  "Return the full BibTeX entry text for KEY in the current buffer, or nil."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward
           (concat "@[[:alpha:]]+[ \t]*{[ \t]*" (regexp-quote key) "[ \t]*,")
           nil t)
      (let ((start (match-beginning 0))
            (depth 1))
        (goto-char (match-beginning 0))
        (search-forward "{")
        (while (and (> depth 0) (not (eobp)))
          (cond
           ((eq (char-after) ?\{) (setq depth (1+ depth)))
           ((eq (char-after) ?\}) (setq depth (1- depth))))
          (forward-char 1))
        (buffer-substring-no-properties start (point))))))

;;;###autoload
(defun rlr-create-typst-bib ()
  "Build a local sources.bib from cite keys in the current Org/Typst buffer.

Ensures a `sources.bib' file exists in the same directory as the
visited file, then scans the buffer for citation keys and copies
each corresponding BibTeX record from
`rlr-create-typst-bib-main-bib-file' into it.  Keys already present
in sources.bib are skipped."
  (interactive)
  (unless buffer-file-name
    (user-error "Buffer is not visiting a file"))
  (let* ((dir (file-name-directory buffer-file-name))
         (dest (expand-file-name rlr-create-typst-bib-output-file-name dir))
         (main-bib (expand-file-name rlr-create-typst-bib-main-bib-file))
         (keys (rlr-create-typst-bib--collect-keys))
         (existing-keys (rlr-create-typst-bib--existing-keys dest))
         (new-entries nil)
         (missing nil))
    (unless (file-exists-p main-bib)
      (user-error "Main bib file not found: %s" main-bib))
    (unless (file-exists-p dest)
      (write-region "" nil dest))
    (with-temp-buffer
      (insert-file-contents main-bib)
      (dolist (key keys)
        (unless (member key existing-keys)
          (let ((entry (rlr-create-typst-bib--find-entry key)))
            (if entry
                (progn
                  (push entry new-entries)
                  (push key existing-keys))
              (push key missing))))))
    (when new-entries
      (setq new-entries (nreverse new-entries))
      (with-temp-buffer
        (insert-file-contents dest)
        (goto-char (point-max))
        (unless (or (bobp) (bolp)) (insert "\n"))
        (dolist (entry new-entries)
          (insert entry "\n\n"))
        (write-region (point-min) (point-max) dest)))
    (message "sources.bib: %d entr%s added%s"
             (length new-entries)
             (if (= (length new-entries) 1) "y" "ies")
             (if missing
                 (format "; not found: %s"
                         (mapconcat #'identity (nreverse missing) ", "))
               ""))))

(provide 'rlr-create-typst-bib)
;;; rlr-create-typst-bib.el ends here
