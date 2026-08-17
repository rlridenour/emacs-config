;;; canvas-quiz.el --- Upload an Org quiz to Canvas -*- lexical-binding: t; -*-

;; This file lets `canvas-quiz-upload' push an Org-authored quiz straight into
;; Canvas via the Classic Quizzes API, parsing the buffer directly with
;; `org-element-parse-buffer' rather than going through the Org export
;; pipeline -- the supported Org subset is small and fixed, and deliberately
;; matches the format already used by ../../rlr-exam/elisp/ox-exam.el for
;; Org-to-Typst exams, so the same .org file can serve both tools:
;;
;;   #+QUIZ_NAME: Midterm Exam
;;   #+QUIZ_DESCRIPTION: Covers chapters 1-4.
;;
;;   1. This is the first question
;;      :PROPERTIES:
;;      :POINTS: 2
;;      :END:
;;      1. Incorrect option
;;      2. Correct option*
;;      3. Incorrect option
;;      4. Incorrect option
;;
;;   2. Explain photosynthesis.
;;      :ANSWER:
;;      Sunlight is converted into chemical energy in chloroplasts.
;;      :END:
;;
;; Question discovery does not require headline sections: any list item whose
;; enclosing plain-list is not itself nested inside another item counts as a
;; top-level question, whether or not it sits under a headline.  Items with a
;; nested numbered list are multiple-choice (the option ending in a literal
;; "*" is correct); items without one are essay questions.  `#+QUIZ_NAME:'
;; falls back to `#+EXAM_NAME:' if absent, so an existing rlr-exam file needs
;; no edits to also become a quiz.  An optional `:POINTS:' property (default
;; 1) sets points_possible; `:ANSWER:' (used by ox-exam.el for its answer key)
;; is read but not sent to Canvas.
;;
;; `canvas-quiz-preview' parses the buffer and shows what would be uploaded,
;; with no network call, so it's safe to run any time.
;; `canvas-quiz-upload' does the real thing: creates the quiz, then creates
;; each question in order.  Re-running it always creates a new quiz; there is
;; no support for updating an existing one.

;;; Code:

(require 'org)
(require 'org-element)
(require 'cl-lib)
(require 'seq)
(require 'canvas-api)

(defgroup canvas-quiz nil
  "Upload Org-authored quizzes to Canvas."
  :group 'canvas)

;; The domain and default course ID moved to canvas-api.el when canvas-page.el
;; started needing them too; the old names still work.
(define-obsolete-variable-alias 'canvas-quiz-domain 'canvas-domain "canvas-quiz 1.1")
(define-obsolete-variable-alias 'canvas-quiz-default-course-id 'canvas-default-course-id "canvas-quiz 1.1")

(defcustom canvas-quiz-default-type "assignment"
  "Default Canvas quiz_type for uploaded quizzes.
One of \"practice_quiz\", \"assignment\", \"graded_survey\", \"survey\"."
  :type 'string
  :group 'canvas-quiz)

;;; Inline markup: Org objects -> HTML

(defun canvas-quiz--escape-html (str)
  "Escape HTML special characters &, <, > in STR."
  (replace-regexp-in-string
   "[&<>]"
   (lambda (m) (pcase m ("&" "&amp;") ("<" "&lt;") (">" "&gt;")))
   str t t))

(defun canvas-quiz--collapse-whitespace (str)
  "Collapse runs of whitespace (including newlines) in STR to a single space.
Also strips text properties (Org's parser attaches a :parent property to
buffer text, which would otherwise leak into error messages and requests)."
  (substring-no-properties
   (string-trim (replace-regexp-in-string "[ \t\n\r]+" " " str))))

(defun canvas-quiz--object-to-html (obj)
  "Convert one Org paragraph object (a string or element) OBJ to HTML."
  (if (stringp obj)
      (canvas-quiz--escape-html obj)
    (let ((post-blank (or (org-element-property :post-blank obj) 0))
          (body (pcase (org-element-type obj)
                  ('bold (concat "<strong>" (canvas-quiz--contents-to-html (org-element-contents obj)) "</strong>"))
                  ('italic (concat "<em>" (canvas-quiz--contents-to-html (org-element-contents obj)) "</em>"))
                  ((or 'code 'verbatim) (concat "<code>" (canvas-quiz--escape-html (or (org-element-property :value obj) "")) "</code>"))
                  ('latex-fragment (canvas-quiz--escape-html (or (org-element-property :value obj) "")))
                  ('entity (canvas-quiz--escape-html (or (org-element-property :utf-8 obj) "")))
                  ('subscript (concat "<sub>" (canvas-quiz--contents-to-html (org-element-contents obj)) "</sub>"))
                  ('superscript (concat "<sup>" (canvas-quiz--contents-to-html (org-element-contents obj)) "</sup>"))
                  (_ (canvas-quiz--contents-to-html (org-element-contents obj))))))
      (concat body (make-string post-blank ?\s)))))

(defun canvas-quiz--contents-to-html (objs)
  "Convert a list of Org paragraph objects OBJS to an HTML string."
  (mapconcat #'canvas-quiz--object-to-html objs ""))

;;; Extracting question/option text, with correct-answer detection

(defun canvas-quiz--strip-correct-marker (objs)
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

(defun canvas-quiz--first-paragraph (contents)
  "Return the first `paragraph' element among Org element list CONTENTS."
  (seq-find (lambda (el) (eq (org-element-type el) 'paragraph)) contents))

(defun canvas-quiz--find-drawer (contents name)
  "Return the drawer named NAME among Org element list CONTENTS, or nil."
  (seq-find (lambda (el)
              (and (eq (org-element-type el) 'drawer)
                   (equal (org-element-property :drawer-name el) name)))
            contents))

(defun canvas-quiz--paragraph-to-html (para)
  "Convert paragraph element PARA to a collapsed, escaped HTML string."
  (if (null para)
      ""
    (canvas-quiz--collapse-whitespace
     (canvas-quiz--contents-to-html (org-element-contents para)))))

(defun canvas-quiz--drawer-raw-text (drawer)
  "Return the raw (un-HTML-converted) text contents of DRAWER."
  (mapconcat
   (lambda (para)
     (mapconcat (lambda (o) (if (stringp o) o "")) (org-element-contents para) ""))
   (seq-filter (lambda (el) (eq (org-element-type el) 'paragraph))
               (org-element-contents drawer))
   ""))

(defun canvas-quiz--drawer-property (drawer key)
  "Extract the value of \":KEY: value\" from the raw text of DRAWER, or nil."
  (when drawer
    (let ((raw (canvas-quiz--drawer-raw-text drawer)))
      (when (string-match (format ":%s:[ \t]*\\([^\n]+\\)" (regexp-quote key)) raw)
        (string-trim (match-string 1 raw))))))

(defun canvas-quiz--question-name (text)
  "Derive a Canvas question_name from HTML question TEXT.
Strips tags, collapses whitespace, and truncates to 60 characters."
  (let* ((plain (canvas-quiz--collapse-whitespace
                 (replace-regexp-in-string "<[^>]+>" "" text))))
    (if (> (length plain) 60)
        (concat (substring plain 0 60) "…")
      plain)))

;;; Parsing one list item into an mcq or essay question plist

(defun canvas-quiz--parse-mcq-option (item)
  "Parse one option ITEM of an mcq nested list.
Return a plist (:text HTML-STRING :correct BOOLEAN)."
  (let* ((para (canvas-quiz--first-paragraph (org-element-contents item))))
    (unless para
      (user-error "Option item has no text"))
    (let* ((stripped (canvas-quiz--strip-correct-marker (org-element-contents para)))
           (objs (car stripped))
           (correct (cdr stripped))
           (text (canvas-quiz--collapse-whitespace (canvas-quiz--contents-to-html objs))))
      (list :text text :correct correct))))

(defun canvas-quiz--parse-mcq (question-text points nested-list)
  "Build an mcq question plist from QUESTION-TEXT, POINTS, and NESTED-LIST."
  (let* ((option-items (seq-filter (lambda (el) (eq (org-element-type el) 'item))
                                    (org-element-contents nested-list)))
         (options (mapcar #'canvas-quiz--parse-mcq-option option-items))
         (correct-indices (cl-loop for i from 0
                                    for o in options
                                    when (plist-get o :correct) collect i)))
    (cond
     ((null correct-indices)
      (user-error "MCQ %S: no option is marked correct (trailing *)" question-text))
     ((> (length correct-indices) 1)
      (user-error "MCQ %S: more than one option is marked correct" question-text)))
    (list :type 'mcq
          :name (canvas-quiz--question-name question-text)
          :text question-text
          :points points
          :options (mapcar (lambda (o) (plist-get o :text)) options)
          :correct (car correct-indices))))

(defun canvas-quiz--parse-essay (question-text points)
  "Build an essay question plist from QUESTION-TEXT and POINTS."
  (list :type 'essay
        :name (canvas-quiz--question-name question-text)
        :text question-text
        :points points))

(defun canvas-quiz--parse-item (item)
  "Parse a top-level question ITEM into an mcq or essay question plist."
  (let* ((contents (org-element-contents item))
         (para (canvas-quiz--first-paragraph contents))
         (question-text (canvas-quiz--paragraph-to-html para))
         (props (canvas-quiz--find-drawer contents "PROPERTIES"))
         (points-str (canvas-quiz--drawer-property props "POINTS"))
         (points (if points-str (string-to-number points-str) 1))
         (nested-list (seq-find (lambda (el) (eq (org-element-type el) 'plain-list)) contents)))
    (if nested-list
        (canvas-quiz--parse-mcq question-text points nested-list)
      (canvas-quiz--parse-essay question-text points))))

;;; Discovering top-level question items anywhere in the buffer

(defun canvas-quiz--top-level-question-items (tree)
  "Return every `item' element in TREE that is a top-level question.
An item counts as top-level if its enclosing `plain-list' is not itself
nested inside another item (which would make it a nested option list)."
  (org-element-map tree 'item
    (lambda (item)
      (let* ((plain-list (org-element-property :parent item))
             (grandparent (and plain-list (org-element-property :parent plain-list))))
        (unless (and grandparent (eq (org-element-type grandparent) 'item))
          item)))
    nil nil 'item))

;;; Metadata

(defun canvas-quiz--collect-metadata (tree)
  "Collect #+QUIZ_NAME: (or #+EXAM_NAME: as a fallback) and
#+QUIZ_DESCRIPTION: from TREE.
Return a plist (:title STR :description STR-OR-NIL)."
  (let (quiz-name exam-name description)
    (org-element-map tree 'keyword
      (lambda (kw)
        (let ((key (org-element-property :key kw))
              (val (string-trim (or (org-element-property :value kw) ""))))
          (pcase key
            ("QUIZ_NAME" (setq quiz-name val))
            ("EXAM_NAME" (setq exam-name val))
            ("QUIZ_DESCRIPTION" (setq description val))))))
    (let ((title (or quiz-name exam-name)))
      (unless title
        (user-error "Missing required #+QUIZ_NAME: (or #+EXAM_NAME:) keyword"))
      (list :title title :description description))))

;;; Canvas

(defun canvas-quiz--create-quiz (course-id title description type published)
  "Create a quiz named TITLE in COURSE-ID. Return the parsed quiz alist."
  (canvas-api-request
   "POST"
   (format "courses/%s/quizzes" course-id)
   `(("quiz" . (("title" . ,title)
                ("description" . ,(or description ""))
                ("quiz_type" . ,type)
                ("published" . ,(if published "true" "false")))))))

(defun canvas-quiz--question-params (question)
  "Build the `question[...]' params alist for QUESTION plist."
  (let* ((type (plist-get question :type))
         (base `(("question_name" . ,(plist-get question :name))
                  ("question_text" . ,(plist-get question :text))
                  ("points_possible" . ,(plist-get question :points))
                  ("question_type" . ,(if (eq type 'mcq) "multiple_choice_question" "essay_question")))))
    (if (eq type 'mcq)
        (let* ((options (plist-get question :options))
               (correct (plist-get question :correct))
               (answers (cl-loop for text in options
                                  for i from 0
                                  collect `(("answer_html" . ,text)
                                            ("answer_weight" . ,(if (= i correct) 100 0))))))
          (append base `(("answers" . ,answers))))
      base)))

(defun canvas-quiz--create-question (course-id quiz-id question)
  "Create QUESTION (a plist from `canvas-quiz--parse-item') on QUIZ-ID."
  (canvas-api-request
   "POST"
   (format "courses/%s/quizzes/%s/questions" course-id quiz-id)
   `(("question" . ,(canvas-quiz--question-params question)))))

;;; Top-level commands

(defun canvas-quiz--parse-buffer ()
  "Parse the current Org buffer into (:title :description :questions)."
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an Org buffer"))
  (let* ((tree (org-element-parse-buffer))
         (meta (canvas-quiz--collect-metadata tree))
         (items (canvas-quiz--top-level-question-items tree))
         (questions (mapcar #'canvas-quiz--parse-item items)))
    (unless questions
      (user-error "No questions found in buffer"))
    (append meta (list :questions questions))))

;;;###autoload
(defun canvas-quiz-preview ()
  "Parse the current Org buffer and show what `canvas-quiz-upload' would send.
Makes no network calls."
  (interactive)
  (let* ((quiz (canvas-quiz--parse-buffer))
         (buf (get-buffer-create "*canvas-quiz-preview*")))
    (with-current-buffer buf
      (erase-buffer)
      (insert (format "Quiz: %s\n" (plist-get quiz :title)))
      (when (plist-get quiz :description)
        (insert (format "Description: %s\n" (plist-get quiz :description))))
      (insert (format "\n%d question(s):\n\n" (length (plist-get quiz :questions))))
      (cl-loop for q in (plist-get quiz :questions)
               for i from 1
               do (insert (format "%d. [%s, %s pt%s] %s\n"
                                   i (plist-get q :type) (plist-get q :points)
                                   (if (= (plist-get q :points) 1) "" "s")
                                   (plist-get q :name)))
               (insert (format "   %s\n" (plist-get q :text)))
               (when (eq (plist-get q :type) 'mcq)
                 (cl-loop for opt in (plist-get q :options)
                          for j from 0
                          do (insert (format "     %s %s\n"
                                              (if (= j (plist-get q :correct)) "*" "-")
                                              opt))))
               (insert "\n")))
    (pop-to-buffer buf)))

;;;###autoload
(defun canvas-quiz-upload (&optional publish)
  "Upload the current Org buffer to Canvas as a new quiz.
With a prefix argument PUBLISH, publish the quiz immediately; otherwise
it is created unpublished for review."
  (interactive "P")
  (let* ((quiz (canvas-quiz--parse-buffer))
         (course-id (canvas-api-read-course-id))
         (questions (plist-get quiz :questions))
         (n (length questions)))
    (message "Creating quiz %S..." (plist-get quiz :title))
    (let* ((created (canvas-quiz--create-quiz
                      course-id (plist-get quiz :title) (plist-get quiz :description)
                      canvas-quiz-default-type publish))
           (quiz-id (cdr (assq 'id created))))
      (cl-loop for q in questions
                for i from 1
                do (message "Uploading question %d/%d..." i n)
                (canvas-quiz--create-question course-id quiz-id q))
      (message "Uploaded %d question(s) to %s" n (cdr (assq 'html_url created))))))

(provide 'canvas-quiz)
;;; canvas-quiz.el ends here
