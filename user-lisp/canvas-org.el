;;; canvas-org.el --- Shared Org -> HTML conversion for Canvas uploads -*- lexical-binding: t; -*-

;; Both canvas-page.el and canvas-assignment.el turn freeform Org prose into
;; the HTML body of a Canvas object, and both read their settings from
;; `#+KEYWORD:' lines or `:PROPERTY:' drawers.  That shared middle layer lives
;; here: the export options Canvas wants, the post-processing that keeps
;; re-uploads from churning revision histories, and two small helpers for
;; reading metadata.
;;
;; canvas-quiz.el does not use the export pipeline -- its Org subset is small
;; and fixed, so it converts inline markup by hand -- but it does share the
;; metadata helpers below, so that a `#+QUIZ_DUE:' date is read exactly the
;; way an `#+ASSIGNMENT_DUE:' one is.

;;; Code:

(require 'org)
(require 'ox-html)
(require 'seq)

(defgroup canvas-org nil
  "Org-to-HTML conversion for Canvas uploads."
  :group 'canvas)

(defcustom canvas-org-export-options
  '(:with-toc nil
    :section-numbers nil
    :html-toplevel-hlevel 2
    :html-self-link-headlines nil
    :html-container "div")
  "Extra export options passed to the HTML exporter for Canvas bodies.
A plist in the form `org-export-as' accepts as its EXT-PLIST argument.
The defaults suit Canvas: no table of contents, no section numbers, and
headlines starting at <h2> because Canvas renders the page or assignment
title as the <h1>."
  :type '(plist)
  :group 'canvas-org)

(defcustom canvas-org-strip-generated-ids t
  "When non-nil, drop Org's auto-generated `id=\"orgXXXXXXX\"' anchors.
Org mints those anchors afresh on every export, so leaving them in makes
each upload differ from the last even when the Org source has not changed,
cluttering the object's revision history in Canvas.  Explicit `#+NAME:' and
`CUSTOM_ID' anchors are untouched, so internal links still work."
  :type 'boolean
  :group 'canvas-org)

;;; Metadata helpers

(defun canvas-org-keyword (key)
  "Return the value of buffer keyword #+KEY:, or nil if absent or empty."
  (let ((val (cdr (assoc key (org-collect-keywords (list key))))))
    (when val
      (let ((s (string-trim (mapconcat #'identity val " "))))
        (unless (string-empty-p s) s)))))

(defun canvas-org-truthy (str)
  "Return non-nil if STR is an Org-ish spelling of true."
  (and str (member (downcase (string-trim str)) '("t" "true" "yes" "y" "1"))))

(defun canvas-org-split-list (str)
  "Split STR, a comma- or space-separated list, into trimmed non-empty parts."
  (when str
    (seq-remove #'string-empty-p
                (mapcar #'string-trim (split-string str "[,[:space:]]+" t)))))

(defcustom canvas-org-default-due-time "23:59"
  "Time of day, \"HH:MM\", given to a due or lock date written without one.
An Org date such as `<2026-09-15 Tue>' otherwise means midnight at the
*start* of that day, which is rarely what a due date means.  Unlock dates
are left at midnight, where the start of the day is what is wanted.  Set
to nil to take Org's midnight for every date."
  :type '(choice (const :tag "Midnight" nil) string)
  :group 'canvas-org)

(defun canvas-org-parse-time (str keyword end-of-day)
  "Convert STR, an Org timestamp or date string, to an ISO 8601 string.
KEYWORD names the setting it came from, for error messages.  With
END-OF-DAY, a date carrying no time of day gets
`canvas-org-default-due-time' rather than midnight."
  (when str
    (let* ((bare (string-trim (replace-regexp-in-string "\\`[<[]\\|[]>]\\'" "" (string-trim str))))
           (has-time (string-match-p "[0-9]\\{1,2\\}:[0-9]\\{2\\}" bare))
           (bare (if (or has-time (not end-of-day) (not canvas-org-default-due-time))
                     bare
                   (concat bare " " canvas-org-default-due-time)))
           (time (condition-case nil
                     (org-time-string-to-time bare)
                   (error
                    (user-error "Cannot read %s as a date: %S (try an Org timestamp, e.g. <2026-09-15 Tue 17:00>)"
                                keyword str)))))
      (format-time-string "%Y-%m-%dT%H:%M:%S%:z" time))))

(defun canvas-org-number (str keyword)
  "Convert STR to a number, erroring against KEYWORD if it is not one."
  (when str
    (let ((s (string-trim str)))
      (unless (string-match-p "\\`-?[0-9]+\\(\\.[0-9]+\\)?\\'" s)
        (user-error "%s must be a number, not %S" keyword s))
      (string-to-number s))))

;;; Org -> HTML

(defun canvas-org-clean-html (html)
  "Post-process exported HTML for Canvas.
Currently just honours `canvas-org-strip-generated-ids'."
  (if canvas-org-strip-generated-ids
      (replace-regexp-in-string
       " id=\"\\(?:outline-container-\\|text-\\)?org[0-9a-f]+\"" "" html t t)
    html))

(defun canvas-org-export-body (subtreep)
  "Export the current buffer (or, with SUBTREEP, the subtree at point) to HTML.
Returns the body HTML only -- no <html>, <head>, title, or postamble."
  (let ((org-export-with-broken-links t))
    (canvas-org-clean-html
     (string-trim
      (org-export-as 'html subtreep nil t canvas-org-export-options)))))

(provide 'canvas-org)
;;; canvas-org.el ends here
