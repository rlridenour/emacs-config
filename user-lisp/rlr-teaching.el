;;; rlr-teaching.el -*- lexical-binding: t; -*-

(require 'seq)
(require 'subr-x)

(defvar rlr/teaching-stopwords
  '("a" "an" "the"
    "and" "but" "or" "nor" "for" "so" "yet"
    "in" "on" "at" "of" "to" "from" "by" "as" "with"
    "into" "onto" "upon" "over" "under" "about" "above" "below"
    "after" "before" "between" "among" "against" "through" "during"
    "without" "within" "per" "via")
  "Words dropped when generating a slug from a title.")

(defun rlr/teaching--slugify (title)
  "Return a hyphen-separated slug for TITLE.
Words of two letters or fewer, and words in
`rlr/teaching-stopwords', are dropped."
  (let* ((words (split-string title))
         (cleaned (mapcar (lambda (w)
                             (downcase (replace-regexp-in-string "[^[:alnum:]]" "" w)))
                           words))
         (kept (seq-filter (lambda (w)
                              (and (> (length w) 2)
                                   (not (member w rlr/teaching-stopwords))))
                            cleaned)))
    (string-join kept "-")))

(defun rlr/teaching--today ()
  "Return today's date formatted as \"Month Day, Year\"."
  (format-time-string "%B %-d, %Y"))

(defun rlr/teaching--document-header (title)
  "Return the standard org header block for TITLE."
  (format "#+TITLE: %s
#+AUTHOR: Dr. Randy Ridenour
#+DATE: %s
"
          title (rlr/teaching--today)))

(defun rlr/teaching--handout-template (title)
  "Return the org template string for a handout named TITLE."
  (format "#+TITLE: %s
:drawer:
#+AUTHOR: Dr. Randy Ridenour
#+OPTIONS: toc:nil
#+OPTIONS: title:nil
#+TYPST: #set document(title: \"%s\")
#+TYPST: #set document(author: \"Dr. Randy Ridenour\")
#+TYPST: #set page(paper: \"us-letter\", margin: (x: 1.5in, y: 1.5in))
#+TYPST: #set text(font: \"Libertinus Serif\", size: 12pt,)
#+TYPST: #show title: set text(font: \"Libertinus Serif\", size: 12pt, weight: \"bold\")
#+TYPST: #show heading: set text(font: \"Libertinus Sans\", size: 12pt, weight: \"bold\")
#+TYPST: #show math.equation: set text(font: \"Libertinus Math\")
#+TYPST: #set heading(numbering: \"1.1\")
#+TYPST: #show heading: set block(above: 2em, below: 1em)
#+HTML_DOCTYPE: html5
#+OPTIONS: html-style:nil
#+OPTIONS: num:nil
#+HTML_HEAD: <link rel=\"stylesheet\" type=\"text/css\" href=\"https://randyridenour.net/css/canvas-handout.css\"/>

#+BEGIN_EXPORT typst
#title()
*Dr. Ridenour*\\
*%s*
#+END_EXPORT
:end:
"
          title title (rlr/teaching--today)))

(defun rlr/teaching--syllabus-template (title)
  "Return the org template string for a syllabus named TITLE."
  (rlr/teaching--document-header title))

(defun rlr/teaching--new-document (base-dir title template-fn)
  "Create a new document under BASE-DIR named after TITLE.
Slugifies TITLE, creates a subdirectory of BASE-DIR with that
slug, and writes a org file inside it populated by calling
TEMPLATE-FN with TITLE."
  (let ((slug (rlr/teaching--slugify title)))
    (when (string-empty-p slug)
      (user-error "Title produced an empty slug: %s" title))
    (let* ((doc-dir (expand-file-name slug base-dir))
           (file (expand-file-name (concat slug ".org") doc-dir)))
      (when (file-exists-p file)
        (user-error "File already exists: %s" file))
      (make-directory doc-dir t)
      (find-file file)
      (insert (funcall template-fn title))
      (save-buffer))))

(defun rlr/teaching-new-handout (base-dir title)
  "Create a new handout document.
Prompts for BASE-DIR (defaulting to the current directory) and
TITLE, then creates a slugified subdirectory of BASE-DIR
containing a new org file populated with the handout template."
  (interactive
   (list (read-directory-name "Directory: " default-directory nil t)
         (read-string "Title: ")))
  (rlr/teaching--new-document base-dir title #'rlr/teaching--handout-template))

(defun rlr/teaching-new-syllabus (base-dir title)
  "Create a new syllabus document.
Prompts for BASE-DIR (defaulting to the current directory) and
TITLE, then creates a slugified subdirectory of BASE-DIR
containing a new org file populated with the syllabus template."
  (interactive
   (list (read-directory-name "Directory: " default-directory nil t)
         (read-string "Title: ")))
  (rlr/teaching--new-document base-dir title #'rlr/teaching--syllabus-template))

(provide 'rlr-teaching)
;;; rlr-teaching.el ends here
