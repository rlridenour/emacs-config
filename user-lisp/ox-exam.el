;;; ox-exam.el --- Convert an Org exam to Typst source + answer key -*- lexical-binding: t; -*-

;; This file defines a minimal Org export backend (`exam') so that
;; `org-exam-export-to-typst' and `org-exam-export-to-pdf' show up in the
;; normal export dispatcher (`C-c C-e').  The actual conversion does not go
;; through the standard Org export pipeline (`org-export-as'); it parses the
;; buffer directly with `org-element-parse-buffer' and renders Typst source
;; by hand, because the supported Org subset is small and fixed:
;;
;;   #+COURSE_NUMBER: MATH 101
;;   #+COURSE_NAME: Calculus I
;;   #+EXAM_NAME: Midterm 1
;;   #+DATE: 2026-07-18
;;
;;   * Multiple Choice
;;   1. This is the first question
;;      1. Incorrect option
;;      2. Correct option*
;;      3. Incorrect option
;;
;;   * Short Essay
;;   1. Explain photosynthesis.
;;      :PROPERTIES:
;;      :SPACE: 3in
;;      :END:
;;      :ANSWER:
;;      Sunlight is converted into chemical energy.
;;      :END:
;;
;; Each level-1 headline is a section.  Items in its top-level list are
;; either multiple-choice questions (they contain a nested list of options,
;; the correct one ending in a literal "*") or essay questions (no nested
;; list; a :SPACE: property gives the blank space to leave on the exam, and
;; an :ANSWER: drawer gives the text to print in the key).
;;
;; Output pairs with the Typst package in ../typst/lib.typ: for
;; "foo.org" this produces "foo-exam.typ" and "foo-key.typ", each of which
;; imports that package and calls its `exam-doc', `section', `mcq', and
;; `essay' functions.

;;; Code:

(require 'org)
(require 'org-element)
(require 'ox)
(require 'cl-lib)
(require 'seq)

(defgroup org-exam nil
  "Convert Org exam files to Typst."
  :group 'org-export)

(defcustom org-exam-typst-import "@local/exam:0.1.0"
  "Typst import path for the exam package.

The default assumes the package in ../typst has been installed as a
local Typst package (see the Makefile in this repository).  Set this
to a relative path such as \"../typst/lib.typ\" to import it directly
from the repository instead."
  :type 'string
  :group 'org-exam)

(defconst org-exam--typst-special-chars
  '("\\" "#" "$" "_" "*" "`" "@" "<" ">" "[" "]" "{" "}")
  "Characters with special meaning in Typst markup that must be escaped
when they occur in literal (non-markup) text.")

(defun org-exam--escape-typst (str)
  "Escape Typst markup special characters in STR."
  (replace-regexp-in-string
   (regexp-opt org-exam--typst-special-chars)
   (lambda (m) (concat "\\" m))
   str t t))

(defun org-exam--collapse-whitespace (str)
  "Collapse runs of whitespace (including newlines) in STR to a single space."
  (string-trim (replace-regexp-in-string "[ \t\n\r]+" " " str)))

;;; Inline markup: Org objects -> Typst markup

(defun org-exam--object-to-typst (obj)
  "Convert one Org paragraph object (a string or element) to Typst markup."
  (if (stringp obj)
      (org-exam--escape-typst obj)
    ;; Org strips the whitespace that trails an object (e.g. the space
    ;; after a closing "*bold*" marker) out of the following plain-text
    ;; string and records how many characters into :post-blank instead of
    ;; leaving them in the buffer text we'd otherwise see -- put it back.
    (let ((post-blank (or (org-element-property :post-blank obj) 0))
          (body (pcase (org-element-type obj)
                  ('bold (concat "*" (org-exam--contents-to-typst (org-element-contents obj)) "*"))
                  ('italic (concat "_" (org-exam--contents-to-typst (org-element-contents obj)) "_"))
                  ((or 'code 'verbatim) (concat "`" (org-element-property :value obj) "`"))
                  ('latex-fragment (org-exam--escape-typst (or (org-element-property :value obj) "")))
                  ('entity (org-exam--escape-typst (or (org-element-property :utf-8 obj) "")))
                  ('subscript (concat "#sub[" (org-exam--contents-to-typst (org-element-contents obj)) "]"))
                  ('superscript (concat "#super[" (org-exam--contents-to-typst (org-element-contents obj)) "]"))
                  (_ (org-exam--contents-to-typst (org-element-contents obj))))))
      (concat body (make-string post-blank ?\s)))))

(defun org-exam--contents-to-typst (objs)
  "Convert a list of Org paragraph objects OBJS to a Typst markup string."
  (mapconcat #'org-exam--object-to-typst objs ""))

;;; Extracting question/option text, with correct-answer detection

(defun org-exam--strip-correct-marker (objs)
  "If the last object in OBJS (a paragraph's contents) is a string ending
in a literal \"*\", return (STRIPPED-OBJS . t); otherwise (OBJS . nil)."
  (if (null objs)
      (cons objs nil)
    (let* ((butlast-objs (butlast objs))
           (last-obj (car (last objs))))
      (if (and (stringp last-obj)
               (string-match "\\`\\(.*[^ \t\n]\\)?[ \t\n]*\\*[ \t\n]*\\'" last-obj)
               (match-string 1 last-obj))
          (cons (append butlast-objs (list (match-string 1 last-obj))) t)
        (if (and (stringp last-obj)
                 (string-match "\\`[ \t\n]*\\*[ \t\n]*\\'" last-obj))
            ;; Whole trailing string is just "*" (with whitespace) -- the
            ;; marker attaches to a preceding non-string object instead.
            (cons butlast-objs t)
          (cons objs nil))))))

(defun org-exam--first-paragraph (contents)
  "Return the first `paragraph' element among Org element list CONTENTS."
  (seq-find (lambda (el) (eq (org-element-type el) 'paragraph)) contents))

(defun org-exam--find-drawer (contents name)
  "Return the drawer named NAME among Org element list CONTENTS, or nil."
  (seq-find (lambda (el)
              (and (eq (org-element-type el) 'drawer)
                   (equal (org-element-property :drawer-name el) name)))
            contents))

(defun org-exam--paragraph-to-typst (para)
  "Convert paragraph element PARA to a collapsed, escaped Typst markup string."
  (if (null para)
      ""
    (org-exam--collapse-whitespace
     (org-exam--contents-to-typst (org-element-contents para)))))

;;; Parsing one list item into an mcq or essay question plist

(defun org-exam--parse-mcq-option (item)
  "Parse one option ITEM of an mcq nested list.
Return a plist (:text TYPST-STRING :correct BOOLEAN)."
  (let* ((para (org-exam--first-paragraph (org-element-contents item))))
    (unless para
      (user-error "Option item has no text"))
    (let* ((stripped (org-exam--strip-correct-marker (org-element-contents para)))
           (objs (car stripped))
           (correct (cdr stripped))
           (text (org-exam--collapse-whitespace (org-exam--contents-to-typst objs))))
      (list :text text :correct correct))))

(defun org-exam--parse-mcq (question-text nested-list)
  "Build an mcq question plist from QUESTION-TEXT and its NESTED-LIST of options."
  (let* ((option-items (seq-filter (lambda (el) (eq (org-element-type el) 'item))
                                    (org-element-contents nested-list)))
         (options (mapcar #'org-exam--parse-mcq-option option-items))
         (correct-indices (cl-loop for i from 0
                                    for o in options
                                    when (plist-get o :correct) collect i)))
    (cond
     ((null correct-indices)
      (user-error "MCQ %S: no option is marked correct (trailing *)" question-text))
     ((> (length correct-indices) 1)
      (user-error "MCQ %S: more than one option is marked correct" question-text)))
    (list :type 'mcq
          :text question-text
          :options (mapcar (lambda (o) (plist-get o :text)) options)
          :correct (car correct-indices))))

(defun org-exam--drawer-raw-text (drawer)
  "Return the raw (un-Typst-converted) text contents of DRAWER."
  (mapconcat
   (lambda (para)
     (mapconcat (lambda (o) (if (stringp o) o "")) (org-element-contents para) ""))
   (seq-filter (lambda (el) (eq (org-element-type el) 'paragraph))
               (org-element-contents drawer))
   ""))

(defun org-exam--drawer-property (drawer key)
  "Extract the value of \":KEY: value\" from the raw text of DRAWER, or nil."
  (when drawer
    (let ((raw (org-exam--drawer-raw-text drawer)))
      (when (string-match (format ":%s:[ \t]*\\([^\n]+\\)" (regexp-quote key)) raw)
        (string-trim (match-string 1 raw))))))

(defun org-exam--drawer-answer-text (drawer)
  "Convert the paragraph(s) inside ANSWER drawer DRAWER to Typst markup,
joined with blank lines between paragraphs."
  (when drawer
    (let ((paragraphs (seq-filter (lambda (el) (eq (org-element-type el) 'paragraph))
                                   (org-element-contents drawer))))
      (mapconcat #'org-exam--paragraph-to-typst paragraphs "\n\n"))))

(defconst org-exam--space-re
  "\\`[0-9]+\\(\\.[0-9]+\\)?\\(in\\|cm\\|mm\\|pt\\|em\\)\\'"
  "Valid Typst length literal, e.g. \"2in\" or \"3.5cm\".")

(defun org-exam--parse-essay (question-text item)
  "Build an essay question plist from QUESTION-TEXT and list ITEM."
  (let* ((contents (org-element-contents item))
         (props (org-exam--find-drawer contents "PROPERTIES"))
         (answer-drawer (org-exam--find-drawer contents "ANSWER"))
         (space (org-exam--drawer-property props "SPACE")))
    (unless space
      (user-error "Essay question %S is missing a :SPACE: property" question-text))
    (unless (string-match-p org-exam--space-re space)
      (user-error "Essay question %S has an invalid :SPACE: value %S (expected e.g. \"2in\", \"3.5cm\")"
                  question-text space))
    (list :type 'essay
          :text question-text
          :space space
          :answer (org-exam--drawer-answer-text answer-drawer))))

(defun org-exam--parse-item (item)
  "Parse a top-level question ITEM into an mcq or essay question plist."
  (let* ((contents (org-element-contents item))
         (para (org-exam--first-paragraph contents))
         (question-text (org-exam--paragraph-to-typst para))
         (nested-list (seq-find (lambda (el) (eq (org-element-type el) 'plain-list)) contents)))
    (if nested-list
        (org-exam--parse-mcq question-text nested-list)
      (org-exam--parse-essay question-text item))))

;;; Sections and metadata

(defun org-exam--top-level-list (headline)
  "Return the top-level `plain-list' directly inside HEADLINE's section, or nil."
  (let ((section (seq-find (lambda (el) (eq (org-element-type el) 'section))
                            (org-element-contents headline))))
    (when section
      (seq-find (lambda (el) (eq (org-element-type el) 'plain-list))
                (org-element-contents section)))))

(defun org-exam--collect-sections (tree)
  "Collect all level-1 headlines in TREE as a list of (:title STR :questions LIST)."
  (org-element-map tree 'headline
    (lambda (hl)
      (when (= (org-element-property :level hl) 1)
        (let ((plist (org-exam--top-level-list hl)))
          (unless plist
            (user-error "Section %S has no question list"
                        (org-element-property :raw-value hl)))
          (list :title (org-exam--escape-typst (org-element-property :raw-value hl))
                :questions (mapcar #'org-exam--parse-item
                                    (seq-filter (lambda (el) (eq (org-element-type el) 'item))
                                                (org-element-contents plist)))))))
    nil nil 'headline))

(defun org-exam--collect-metadata (tree)
  "Collect #+COURSE_NUMBER:, #+COURSE_NAME:, #+EXAM_NAME:, #+DATE: from TREE."
  (let (course-number course-name exam-name date)
    (org-element-map tree 'keyword
      (lambda (kw)
        (let ((key (org-element-property :key kw))
              (val (string-trim (or (org-element-property :value kw) ""))))
          (pcase key
            ("COURSE_NUMBER" (setq course-number val))
            ("COURSE_NAME" (setq course-name val))
            ("EXAM_NAME" (setq exam-name val))
            ("DATE" (setq date val))))))
    (dolist (pair `(("COURSE_NUMBER" . ,course-number)
                    ("COURSE_NAME" . ,course-name)
                    ("EXAM_NAME" . ,exam-name)
                    ("DATE" . ,date)))
      (when (null (cdr pair))
        (user-error "Missing required #+%s: keyword" (car pair))))
    (list :course-number course-number
          :course-name course-name
          :exam-name exam-name
          :date date)))

;;; Rendering Typst source

(defun org-exam--content (typst-markup)
  "Wrap already-converted Typst markup string as a Typst content literal."
  (concat "[" typst-markup "]"))

(defun org-exam--plain-content (raw-string)
  "Escape and wrap a plain (non-markup) string as a Typst content literal."
  (org-exam--content (org-exam--escape-typst raw-string)))

(defun org-exam--render-question (q key-p)
  "Render question plist Q as a Typst #mcq(...) or #essay(...) call."
  (pcase (plist-get q :type)
    ('mcq
     (format "  #mcq(%s, (%s,), correct: %d, key: %s)\n"
             (org-exam--content (plist-get q :text))
             (mapconcat (lambda (o) (org-exam--content o)) (plist-get q :options) ", ")
             (plist-get q :correct)
             (if key-p "true" "false")))
    ('essay
     (let ((answer (plist-get q :answer)))
       (format "  #essay(%s, space: %s, answer: %s, key: %s)\n"
               (org-exam--content (plist-get q :text))
               (plist-get q :space)
               (if (and answer (not (string-empty-p answer)))
                   (org-exam--content answer)
                 "none")
               (if key-p "true" "false"))))))

(defun org-exam--render (meta sections key-p)
  "Render the full Typst source for exam METADATA and SECTIONS.
KEY-P non-nil renders the answer key variant."
  (concat
   (format "#import \"%s\": *\n\n" org-exam-typst-import)
   "#show: exam-doc.with(\n"
   (format "  course-number: %s,\n" (org-exam--plain-content (plist-get meta :course-number)))
   (format "  course-name: %s,\n" (org-exam--plain-content (plist-get meta :course-name)))
   (format "  exam-name: %s,\n" (org-exam--plain-content (plist-get meta :exam-name)))
   (format "  date: %s,\n" (org-exam--plain-content (plist-get meta :date)))
   (format "  key: %s,\n" (if key-p "true" "false"))
   ")\n\n"
   (mapconcat
    (lambda (sec)
      (concat
       (format "#section(%s)[\n" (org-exam--content (plist-get sec :title)))
       (mapconcat (lambda (q) (org-exam--render-question q key-p))
                   (plist-get sec :questions) "")
       "]\n\n"))
    sections "")))

;;; Top-level export commands

(defun org-exam--source-file ()
  (or (buffer-file-name)
      (user-error "Buffer is not visiting a file")))

(defun org-exam--write-file (path content)
  (with-temp-file path (insert content))
  path)

(defun org-exam--do-export ()
  "Parse the current Org buffer and write out <name>-exam.typ and
<name>-key.typ next to it.  Return the list of file paths written."
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an Org buffer"))
  (let* ((tree (org-element-parse-buffer))
         (meta (org-exam--collect-metadata tree))
         (sections (org-exam--collect-sections tree))
         (base (file-name-sans-extension (org-exam--source-file)))
         (exam-file (concat base "-exam.typ"))
         (key-file (concat base "-key.typ")))
    (org-exam--write-file exam-file (org-exam--render meta sections nil))
    (org-exam--write-file key-file (org-exam--render meta sections t))
    (list exam-file key-file)))

(defun org-exam--typst-compile (typ-file)
  "Compile TYP-FILE to PDF with the `typst' command line tool."
  (unless (executable-find "typst")
    (user-error "`typst' executable not found on PATH"))
  (let* ((default-directory (file-name-directory typ-file))
         (name (file-name-nondirectory typ-file))
         (buf (get-buffer-create "*org-exam-typst*")))
    (unless (zerop (call-process "typst" nil buf nil "compile" name))
      (pop-to-buffer buf)
      (user-error "Typst compilation failed for %s (see *org-exam-typst* buffer)" name))
    (concat (file-name-sans-extension typ-file) ".pdf")))

;;;###autoload
(defun org-exam-export-to-typst (&optional _async _subtreep _visible-only)
  "Export the current Org exam buffer to Typst source.
Writes <name>-exam.typ and <name>-key.typ next to the Org file."
  (interactive)
  (let ((files (org-exam--do-export)))
    (message "org-exam: wrote %s" (mapconcat #'file-name-nondirectory files ", "))
    files))

;;;###autoload
(defun org-exam-export-to-pdf (&optional _async _subtreep _visible-only)
  "Export the current Org exam buffer to Typst source and compile it to PDF."
  (interactive)
  (let* ((typ-files (org-exam--do-export))
         (pdf-files (mapcar #'org-exam--typst-compile typ-files)))
    (message "org-exam: wrote %s" (mapconcat #'file-name-nondirectory pdf-files ", "))
    pdf-files))

;; Register with the export dispatcher (`C-c C-e') purely for discoverability;
;; the commands above do their own parsing rather than going through
;; `org-export-as'.
(org-export-define-backend 'exam
  '((template . (lambda (contents _info) contents)))
  :menu-entry
  '(?X "Export to exam (Typst)"
       ((?t "As Typst source (.typ)" org-exam-export-to-typst)
        (?p "As Typst source, compiled to PDF" org-exam-export-to-pdf))))

(provide 'ox-exam)
;;; ox-exam.el ends here
