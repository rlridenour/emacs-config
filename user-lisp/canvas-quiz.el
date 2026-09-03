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
;;   #+QUIZ_DUE: <2026-09-15 Tue>
;;   #+QUIZ_GROUP: Quizzes
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
;; Beyond the name and description, the quiz's own settings -- quiz type,
;; due, unlock, and lock dates, assignment group, publish state, allowed
;; attempts, and a default course ID -- come from `#+QUIZ_*:' keywords.  Those
;; the two share are spelled and parsed exactly as canvas-assignment.el spells
;; and parses its `#+ASSIGNMENT_*:' ones (see canvas-org.el for the dates).
;;
;; `canvas-quiz-preview' parses the buffer and shows what would be uploaded,
;; with no network call, so it's safe to run any time.
;; `canvas-quiz-upload' does the real thing: creates the quiz, creates each
;; question in order, and publishes last if it is to be published at all.
;;
;; Re-running it updates the quiz of the same title in place rather than
;; piling up copies, in three tiers, because a quiz is not one overwritable
;; blob the way a page or an assignment description is -- it is a record plus
;; a set of separately addressable questions:
;;
;;   - The quiz's own settings are always updated.
;;   - Its questions are replaced wholesale, after asking (see
;;     `canvas-quiz-confirm-question-replacement'), since an Org question
;;     carries no ID by which to match the Canvas question it means, and
;;     matching by position or by text breaks under exactly the edits that
;;     prompt a re-upload.
;;   - Unless students have already taken it, in which case the questions are
;;     left alone: replacing them would strand the submissions that refer to
;;     them, and Canvas offers no way to rescore what it has already graded.

;;; Code:

(require 'org)
(require 'org-element)
(require 'cl-lib)
(require 'seq)
(require 'canvas-api)
(require 'canvas-org)

(defgroup canvas-quiz nil
  "Upload Org-authored quizzes to Canvas."
  :group 'canvas)

;; The domain and default course ID moved to canvas-api.el when canvas-page.el
;; started needing them too; the old names still work.
(define-obsolete-variable-alias 'canvas-quiz-domain 'canvas-domain "canvas-quiz 1.1")
(define-obsolete-variable-alias 'canvas-quiz-default-course-id 'canvas-default-course-id "canvas-quiz 1.1")

(defcustom canvas-quiz-confirm-question-replacement t
  "When non-nil, ask before replacing the questions of an existing quiz.
Uploading to a quiz already in Canvas replaces its questions wholesale:
an Org question carries no ID, so there is no way to tell which Canvas
question it is meant to be, and matching by position or by text breaks
under exactly the edits that prompt a re-upload.  Wholesale replacement
discards anything the Org format cannot express -- question groups,
per-question comments, images, question-bank links -- so it asks first.
Set to nil when a quiz only ever comes from its Org file."
  :type 'boolean
  :group 'canvas-quiz)

(defconst canvas-quiz-types
  '(("assignment" . "Graded Quiz")
    ("practice_quiz" . "Practice Quiz")
    ("graded_survey" . "Graded Survey")
    ("survey" . "Ungraded Survey"))
  "The quiz types the Canvas quizzes API accepts, and their Canvas UI names.
Canvas takes the car of each pair; the cdr is what the Canvas UI calls it,
which is what a user writing `#+QUIZ_TYPE:' is likely to have in mind.")

(defconst canvas-quiz-type-aliases
  '(("graded" . "assignment")
    ("graded_quiz" . "assignment")
    ("quiz" . "assignment")
    ("practice" . "practice_quiz")
    ("ungraded_survey" . "survey"))
  "Spellings of a quiz type Canvas will not take, and what they mean.
Canvas\='s name for a Graded Quiz is \"assignment\", which is not a thing
anyone would guess from the Canvas UI, so `#+QUIZ_TYPE: graded quiz\=' is
read as one rather than rejected.")

(defcustom canvas-quiz-default-type "assignment"
  "Default Canvas `quiz_type' for a quiz whose file does not name one.
\"assignment\" is what Canvas calls a Graded Quiz: it is graded, it
appears in the gradebook, and it belongs to an assignment group.  Any of
`canvas-quiz-types'; `#+QUIZ_TYPE:' overrides it per file."
  :type '(choice (const :tag "Graded Quiz" "assignment")
                 (const :tag "Practice Quiz" "practice_quiz")
                 (const :tag "Graded Survey" "graded_survey")
                 (const :tag "Ungraded Survey" "survey"))
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

(defun canvas-quiz--keywords (tree)
  "Return an alist of the `#+KEY: VALUE' keywords in TREE.
Empty values are dropped, so a keyword left blank reads as absent; where
a keyword is repeated the last one in the buffer wins."
  (let (keywords)
    (org-element-map tree 'keyword
      (lambda (kw)
        (let ((key (org-element-property :key kw))
              (val (string-trim (or (org-element-property :value kw) ""))))
          (unless (string-empty-p val)
            ;; Pushed, so a later keyword shadows an earlier one in `assoc'.
            (push (cons key val) keywords)))))
    keywords))

(defun canvas-quiz--type (type)
  "Normalise TYPE and check it against `canvas-quiz-types'.
Matching ignores case and reads a hyphen or a space as an underscore, and
`canvas-quiz-type-aliases' accepts the names the Canvas UI uses, so
\"Graded Quiz\" means `assignment'."
  (let* ((key (replace-regexp-in-string "[- ]" "_" (downcase (string-trim type))))
         (key (or (cdr (assoc key canvas-quiz-type-aliases)) key)))
    (unless (assoc key canvas-quiz-types)
      (user-error "%S is not a Canvas quiz type; QUIZ_TYPE takes %s"
                  type
                  (mapconcat (lambda (pair) (format "%s (%s)" (car pair) (cdr pair)))
                             canvas-quiz-types ", ")))
    key))

(defun canvas-quiz--collect-metadata (tree)
  "Collect the quiz's `#+QUIZ_*:' settings from TREE.
`#+QUIZ_NAME:' is required, falling back to `#+EXAM_NAME:'; everything
else is optional, and the dates, group, and attempts mirror the
`#+ASSIGNMENT_*:' keywords of canvas-assignment.el."
  (let* ((keywords (canvas-quiz--keywords tree))
         (get (lambda (key) (cdr (assoc (concat "QUIZ_" key) keywords))))
         (title (or (funcall get "NAME") (cdr (assoc "EXAM_NAME" keywords)))))
    (unless title
      (user-error "Missing required #+QUIZ_NAME: (or #+EXAM_NAME:) keyword"))
    (list :title title
          :description (funcall get "DESCRIPTION")
          :quiz-type (canvas-quiz--type (or (funcall get "TYPE")
                                            canvas-quiz-default-type))
          :due (canvas-org-parse-time (funcall get "DUE") "QUIZ_DUE" t)
          :unlock (canvas-org-parse-time (funcall get "UNLOCK") "QUIZ_UNLOCK" nil)
          :lock (canvas-org-parse-time (funcall get "LOCK") "QUIZ_LOCK" t)
          :group (funcall get "GROUP")
          :published (canvas-org-truthy (funcall get "PUBLISHED"))
          :attempts (canvas-org-number (funcall get "ATTEMPTS") "QUIZ_ATTEMPTS")
          :course-id (canvas-org-number (funcall get "COURSE_ID") "QUIZ_COURSE_ID")
          :quiz-id (canvas-org-number (funcall get "ID") "QUIZ_ID"))))

;;; Canvas

(defun canvas-quiz--find-existing-id (course-id title)
  "Return the ID of the quiz in COURSE-ID titled TITLE, or nil."
  (let ((results (canvas-api-request
                  "GET" (format "courses/%s/quizzes" course-id)
                  (canvas-api-search-params title)
                  t)))
    (cl-loop with wanted = (downcase title)
             for quiz across (or results [])
             when (equal (downcase (or (alist-get 'title quiz) "")) wanted)
             return (alist-get 'id quiz))))

(defun canvas-quiz--fetch-quiz (course-id quiz-id)
  "Return the parsed quiz alist for QUIZ-ID in COURSE-ID, or nil if absent."
  (canvas-api-request
   "GET" (format "courses/%s/quizzes/%s" course-id quiz-id) nil t))

(defun canvas-quiz--taken-p (quiz)
  "Return non-nil if students have already taken QUIZ, a parsed quiz alist.
Canvas reports this as `unpublishable', which it sets to false exactly
when a quiz has student submissions.  A Canvas old enough not to send the
field at all counts as taken: when in doubt about whether there are
submissions, leaving the questions alone is the safe way to be wrong."
  (not (eq (alist-get 'unpublishable quiz :missing) t)))

(defun canvas-quiz--params (quiz group-id)
  "Build the `quiz[...]' params alist for QUIZ.
GROUP-ID is the resolved assignment group ID, or nil to leave the group
to Canvas.  `published' is deliberately absent: see
`canvas-quiz--create-quiz'."
  (let ((params `(("title" . ,(plist-get quiz :title))
                  ("description" . ,(or (plist-get quiz :description) ""))
                  ("quiz_type" . ,(plist-get quiz :quiz-type)))))
    (cl-flet ((add (key value) (when value (setq params (append params `((,key . ,value)))))))
      (add "due_at" (plist-get quiz :due))
      (add "unlock_at" (plist-get quiz :unlock))
      (add "lock_at" (plist-get quiz :lock))
      (add "assignment_group_id" group-id)
      (add "allowed_attempts" (plist-get quiz :attempts)))
    params))

(defun canvas-quiz--create-quiz (course-id quiz group-id)
  "Create QUIZ in COURSE-ID.  Return the parsed quiz alist.
The quiz is always created unpublished, whatever it is eventually to be:
Canvas works out a quiz's point total when the quiz is published, and
marks an already-published quiz as needing to be republished when its
questions change, so the questions go up first and
`canvas-quiz--publish-quiz' publishes afterwards."
  (canvas-api-request
   "POST"
   (format "courses/%s/quizzes" course-id)
   `(("quiz" . ,(canvas-quiz--params quiz group-id)))))

(defun canvas-quiz--update-quiz (course-id quiz-id quiz group-id)
  "Update QUIZ-ID in COURSE-ID from QUIZ, leaving its questions alone.
Only the quiz's own settings are sent; `published' is set separately,
after the questions are settled, by `canvas-quiz--set-published'."
  (canvas-api-request
   "PUT"
   (format "courses/%s/quizzes/%s" course-id quiz-id)
   `(("quiz" . ,(canvas-quiz--params quiz group-id)))))

(defun canvas-quiz--set-published (course-id quiz-id publish)
  "Set quiz QUIZ-ID in COURSE-ID published or not, per PUBLISH.
Run once the questions are in place: publishing is when Canvas works out
a quiz's point total, and re-publishing is what clears the \"needs
republishing\" state that changing a published quiz's questions leaves."
  (canvas-api-request
   "PUT"
   (format "courses/%s/quizzes/%s" course-id quiz-id)
   `(("quiz" . (("published" . ,(if publish "true" "false")))))))

(defun canvas-quiz--question-ids (course-id quiz-id)
  "Return the IDs of every question on QUIZ-ID in COURSE-ID.
Paged through to the end: a partial list would leave stragglers behind
when the questions are replaced, silently duplicating the quiz."
  (let ((ids nil) (page 1) (done nil))
    (while (not done)
      (let* ((batch (or (canvas-api-request
                         "GET" (format "courses/%s/quizzes/%s/questions" course-id quiz-id)
                         `(("per_page" . 100) ("page" . ,page)))
                        []))
             (n (length batch)))
        (setq ids (append ids (cl-loop for q across batch collect (alist-get 'id q))))
        (setq page (1+ page))
        (when (< n 100) (setq done t))))
    ids))

(defun canvas-quiz--delete-question (course-id quiz-id question-id)
  "Delete QUESTION-ID from QUIZ-ID in COURSE-ID."
  (canvas-api-request
   "DELETE"
   (format "courses/%s/quizzes/%s/questions/%s" course-id quiz-id question-id)))

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
(defun canvas-quiz-preview (&optional publish)
  "Parse the current Org buffer and show what `canvas-quiz-upload' would send.
Makes no network calls.  PUBLISH mirrors the prefix argument to
`canvas-quiz-upload' and only affects the reported publish state."
  (interactive "P")
  (let* ((quiz (canvas-quiz--parse-buffer))
         (buf (get-buffer-create "*canvas-quiz-preview*")))
    (with-current-buffer buf
      (erase-buffer)
      (insert (format "Quiz: %s\n" (plist-get quiz :title)))
      (when (plist-get quiz :description)
        (insert (format "Description: %s\n" (plist-get quiz :description))))
      (insert (format "Type: %s (%s)\n"
                      (plist-get quiz :quiz-type)
                      (cdr (assoc (plist-get quiz :quiz-type) canvas-quiz-types))))
      (insert (format "Published: %s\n"
                      (if (or publish (plist-get quiz :published)) "yes" "no")))
      (dolist (row '((:due "Due") (:unlock "Unlock") (:lock "Lock")))
        (when (plist-get quiz (car row))
          (insert (format "%s: %s\n" (cadr row) (plist-get quiz (car row))))))
      (when (plist-get quiz :group)
        (insert (format "Assignment group: %s (resolved at upload time)\n"
                        (plist-get quiz :group))))
      (when (plist-get quiz :attempts)
        (insert (format "Allowed attempts: %s\n" (plist-get quiz :attempts))))
      (when (plist-get quiz :course-id)
        (insert (format "Course ID: %s (from metadata)\n" (plist-get quiz :course-id))))
      (insert (format "Target: %s\n"
                      (if (plist-get quiz :quiz-id)
                          (format "quiz %s (from QUIZ_ID)" (plist-get quiz :quiz-id))
                        "a quiz with this title, else a new one")))
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

(defun canvas-quiz--upload-questions (course-id quiz-id questions)
  "Create each of QUESTIONS, in order, on QUIZ-ID in COURSE-ID."
  (let ((n (length questions)))
    (cl-loop for q in questions
             for i from 1
             do (message "Uploading question %d/%d..." i n)
                (canvas-quiz--create-question course-id quiz-id q))
    n))

(defun canvas-quiz--replace-questions (course-id quiz-id questions)
  "Replace every question on QUIZ-ID in COURSE-ID with QUESTIONS."
  (let ((old-ids (canvas-quiz--question-ids course-id quiz-id)))
    (cl-loop for id in old-ids
             for i from 1
             do (message "Removing old question %d/%d..." i (length old-ids))
                (canvas-quiz--delete-question course-id quiz-id id))
    (canvas-quiz--upload-questions course-id quiz-id questions)))

(defun canvas-quiz--confirm-replacement (title count)
  "Ask whether to replace the COUNT questions already on the quiz TITLE.
Returns non-nil when there is nothing to lose, when
`canvas-quiz-confirm-question-replacement' is nil, or when the user says
to go ahead."
  (or (zerop count)
      (not canvas-quiz-confirm-question-replacement)
      (yes-or-no-p
       (format "Quiz %S already has %d question(s) in Canvas; replace them? "
               title count))))

(defun canvas-quiz--do-create (course-id quiz group-id publish)
  "Create QUIZ in COURSE-ID, upload its questions, and publish if PUBLISH.
GROUP-ID is the resolved assignment group ID, or nil."
  (message "Creating quiz %S..." (plist-get quiz :title))
  (let* ((created (canvas-quiz--create-quiz course-id quiz group-id))
         (quiz-id (cdr (assq 'id created)))
         (n (canvas-quiz--upload-questions
             course-id quiz-id (plist-get quiz :questions))))
    (when publish
      (message "Publishing quiz...")
      (canvas-quiz--set-published course-id quiz-id t))
    (message "Created %S with %d question(s), %s: %s"
             (plist-get quiz :title) n
             (if publish "published" "unpublished")
             (cdr (assq 'html_url created)))))

(defun canvas-quiz--do-update (course-id quiz-id quiz group-id publish)
  "Update QUIZ-ID in COURSE-ID from QUIZ.
The quiz's own settings are always updated.  Its questions are replaced
only if no student has taken it yet -- there is no way to edit them
without destroying the submissions that refer to them, and no way to
rescore what has already been graded -- and only with the user's
agreement, since replacement discards whatever the Org format cannot
express.  GROUP-ID and PUBLISH are as for `canvas-quiz--do-create'."
  (let ((current (canvas-quiz--fetch-quiz course-id quiz-id)))
    (unless current
      (user-error "No quiz with ID %s in course %s (check #+QUIZ_ID:)" quiz-id course-id))
    (let* ((title (plist-get quiz :title))
           (taken (canvas-quiz--taken-p current))
           (count (or (alist-get 'question_count current) 0))
           (questions (plist-get quiz :questions))
           question-note publish-note)
      (message "Updating quiz %S..." title)
      (canvas-quiz--update-quiz course-id quiz-id quiz group-id)
      (cond
       (taken
        (setq question-note
              "questions left alone (students have already taken it -- edit them in Canvas)"))
       ((canvas-quiz--confirm-replacement title count)
        (setq question-note
              (format "%d question(s) replaced"
                      (canvas-quiz--replace-questions course-id quiz-id questions))))
       (t (setq question-note "questions left alone")))
      ;; Canvas refuses to unpublish a quiz with submissions, so do not ask it
      ;; to; publishing one, on the other hand, is always allowed and is also
      ;; what clears the "needs republishing" state after a question change.
      (cond
       ((and (not publish) taken)
        (setq publish-note "left published (it has submissions)"))
       (t
        (canvas-quiz--set-published course-id quiz-id publish)
        (setq publish-note (if publish "published" "unpublished"))))
      (message "Updated %S: %s, %s: %s"
               title question-note publish-note
               (or (alist-get 'html_url current)
                   (format "https://%s/courses/%s/quizzes/%s"
                           (canvas-api-domain) course-id quiz-id))))))

;;;###autoload
(defun canvas-quiz-upload (&optional publish)
  "Upload the current Org buffer to Canvas as a quiz.
A quiz in the course with the same title is updated in place; if there is
none, a new one is created.  `#+QUIZ_ID:' pins a specific quiz when its
title has been changed in Canvas.

Updating always refreshes the quiz's settings.  Its questions are
replaced wholesale -- and only after asking, see
`canvas-quiz-confirm-question-replacement' -- because an Org question
carries no ID to match an existing Canvas one by.  A quiz students have
already taken keeps its questions regardless: replacing them would strand
the submissions that refer to them, and Canvas offers no way to rescore
what it has already graded.

With a prefix argument PUBLISH, publish the quiz; otherwise it is
published only if the buffer says `#+QUIZ_PUBLISHED: t'.  Publishing
happens last, once the questions are in place, so the point total is
right and no \"needs republishing\" state is left behind."
  (interactive "P")
  (let* ((quiz (canvas-quiz--parse-buffer))
         (title (plist-get quiz :title))
         (course-id (canvas-api-read-course-id (plist-get quiz :course-id)))
         (publish (or publish (plist-get quiz :published)))
         (group (plist-get quiz :group))
         (group-id (and group (canvas-api-assignment-group-id course-id group)))
         (existing (or (plist-get quiz :quiz-id)
                       (progn (message "Looking for an existing quiz titled %S..." title)
                              (canvas-quiz--find-existing-id course-id title)))))
    (if existing
        (canvas-quiz--do-update course-id existing quiz group-id publish)
      (canvas-quiz--do-create course-id quiz group-id publish))))

(provide 'canvas-quiz)
;;; canvas-quiz.el ends here
