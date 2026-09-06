;;; rlr-mosaic-scaffold.el --- Scaffold a new Mosaic presentation -*- lexical-binding: t; -*-

;; Creates a new Mosaic presentation directory containing a slug-prefixed
;; Org mode file and a directory for handouts associated with the lecture.

;; Usage: M-x rlr/new-mosaic-presentation

(require 'seq)

(defvar rlr/mosaic-slug-stopwords
  '("a" "an" "the"
    "and" "but" "or" "nor" "for" "so" "yet"
    "in" "on" "at" "of" "to" "from" "by" "as" "with"
    "into" "onto" "upon" "over" "under" "about" "above" "below"
    "after" "before" "between" "among" "against" "through" "during"
    "without" "within" "per" "via")
  "Words dropped when generating a slug from a title.")

(defun rlr/mosaic-slugify (title)
  "Build a lowercase, hyphenated filename slug from TITLE.
Words of two letters or fewer, and words in
`rlr/mosaic-slug-stopwords', are dropped, unless the word is all
numerals (e.g. \"1\"), which is always kept."
  (let ((words (split-string (downcase title) "[^a-z0-9]+" t)))
    (mapconcat #'identity
               (seq-filter (lambda (w)
                             (or (string-match-p "\\`[0-9]+\\'" w)
                                 (and (> (length w) 2)
                                      (not (member w rlr/mosaic-slug-stopwords)))))
                           words)
               "-")))

(defun rlr/mosaic--write-file (path content)
  "Write CONTENT to PATH, refusing to overwrite an existing file."
  (when (file-exists-p path)
    (user-error "File already exists: %s" path))
  (with-temp-file path
    (insert content)))

(defun rlr/mosaic-org-template (title)
  "Return the contents of an org file for a presentation titled TITLE.
Exported to content.typ via `rlr/org-export-to-mosaic-content' (see
ox-mosaic.el) -- edit this file and re-export rather than
hand-editing content.typ."
  (format "#+TITLE: %1$s
#+SUBTITLE: 
#+AUTHOR: Dr. Ridenour, Department of Philosophy, Oklahoma Baptist University
#+MOSAIC_PACKAGE: @local/mosaic-basic-theme:0.1.0
#+TYPST: #import \"@local/standard-form:0.2.0\": standard-form
#+MOSAIC_COLORS: m.variants.obu
#+MOSAIC_SETUP: logo: m.school-logo()
#+MOSAIC_OUTPUT: split
#+MOSAIC_NOTES: (split-inset: 10mm)
#+MOSAIC_PREAMBLE: #show label(\"mosaic-note-body\"): set text(size: 18pt, weight: \"regular\")
#+MOSAIC_PREAMBLE: #show label(\"mosaic-note-heading\"): set text(size: 18pt)

"
          title))







;;;###autoload
(defun rlr/new-mosaic-presentation (title dir)
  "Scaffold a new Mosaic presentation called TITLE inside DIR.

Creates a subdirectory of DIR (named after a slug derived from TITLE)
containing config.typ, a talk.org whose filename is also prefixed with
that slug (e.g. \"my-talk-talk.org\", so it's identifiable by name
alone when searching across many presentation directories that would
otherwise all just be called \"talk.org\"), a slides/handout pair with
the same slug prefix (e.g. \"my-talk-slides.typ\" and
\"my-talk-handout.typ\"), and content.typ -- generated from talk.org
via ox-mosaic.el (see `rlr/mosaic--generate-content-file'). The slug
is TITLE lower-cased, hyphenated, with the words \"the\" and \"and\",
and any two-letter-or-shorter words, removed."
  (interactive
   (let ((dir (read-directory-name "Create in directory: " default-directory)))
     (list (read-string "Presentation title: ") dir)))
  (let* ((slug (rlr/mosaic-slugify title)))
    (when (string-empty-p slug)
      (user-error "Title \"%s\" has no usable words for a filename" title))
    (let* ((project-dir (expand-file-name slug dir))
           (org-file (expand-file-name (concat slug ".org") project-dir))
           )
      (make-directory project-dir t)
      (rlr/mosaic--write-file org-file (rlr/mosaic-org-template title))
      (find-file org-file)
      (make-directory "handouts")
      (message "Created Mosaic presentation \"%s\" in %s" title project-dir))))

(provide 'rlr-mosaic-scaffold)
;;; rlr-mosaic-scaffold.el ends here
