;;; canvas-assignment.el --- Upload an Org buffer or subtree to Canvas as an assignment -*- lexical-binding: t; -*-

;; `canvas-assignment-upload' pushes the current Org buffer into Canvas as an
;; assignment; `canvas-assignment-upload-subtree' does the same for the
;; subtree at point, so one file can hold a whole course's worth of
;; assignments.  The prose of the buffer becomes the assignment description,
;; rendered by Org's own HTML exporter exactly as canvas-page.el renders a
;; page body (see canvas-org.el); everything else -- due date, points,
;; submission types, assignment group -- comes from `#+ASSIGNMENT_*:'
;; keywords, or the matching `:ASSIGNMENT_*:' properties on a subtree:
;;
;;   #+ASSIGNMENT_NAME: Paper 1 -- Personal Identity
;;   #+ASSIGNMENT_POINTS: 100
;;   #+ASSIGNMENT_DUE: <2026-09-15 Tue>
;;   #+ASSIGNMENT_SUBMISSION_TYPES: online_upload
;;   #+ASSIGNMENT_ALLOWED_EXTENSIONS: pdf,docx
;;   #+ASSIGNMENT_GROUP: Papers
;;
;;   Everything else in the buffer becomes the assignment description.
;;
;; Dates are Org timestamps (or bare "2026-09-15 17:00" strings) and are sent
;; in the local timezone; a date with no time of day gets
;; `canvas-org-default-due-time' for due/lock dates and midnight for
;; unlock dates.  `#+ASSIGNMENT_GROUP:' takes either an assignment group's
;; name, looked up in the course, or its numeric ID.
;;
;; Uploading looks for an existing assignment with the same name in the
;; course: if there is one it is updated in place (PUT), otherwise a new one
;; is created (POST).  So editing the Org file and re-running updates the same
;; assignment rather than piling up copies -- which also means edits made in
;; the Canvas UI are overwritten.  `#+ASSIGNMENT_ID:' pins a specific
;; assignment when its name has been changed in Canvas.
;;
;; `canvas-assignment-preview' shows exactly what would be sent, with no
;; network call, so it is safe to run any time.

;;; Code:

(require 'org)
(require 'cl-lib)
(require 'canvas-api)
(require 'canvas-org)

(defgroup canvas-assignment nil
  "Upload Org-authored assignments to Canvas."
  :group 'canvas)

(defconst canvas-assignment-submission-types
  '("online_text_entry" "online_upload" "online_url" "media_recording"
    "student_annotation" "online_quiz" "discussion_topic" "wiki_page"
    "external_tool" "on_paper" "none" "not_graded")
  "The submission types the Canvas assignments API accepts.
Canvas checks every value it is sent against this list and rejects the
whole request with \"Invalid submission types\" -- naming no culprit --
if any one of them is not on it, so `canvas-assignment--submission-types'
checks the list here first, before anything goes over the wire.")

(defcustom canvas-assignment-default-submission-types '("online_text_entry" "online_upload")
  "Default Canvas `submission_types' for uploaded assignments.
Any of `canvas-assignment-submission-types'; an assignment may list more
than one, though Canvas only allows that for the online types (adding
\"on_paper\" or \"none\" to another type is refused)."
  :type '(repeat string)
  :group 'canvas-assignment)

(defcustom canvas-assignment-default-grading-type nil
  "Default Canvas `grading_type', or nil to let Canvas decide (points).
One of \"points\", \"percent\", \"letter_grade\", \"gpa_scale\",
\"pass_fail\", or \"not_graded\"."
  :type '(choice (const :tag "Canvas default" nil) string)
  :group 'canvas-assignment)

(defcustom canvas-assignment-default-points nil
  "Default `points_possible' for uploaded assignments, or nil for Canvas's."
  :type '(choice (const :tag "Canvas default" nil) number)
  :group 'canvas-assignment)

;; The date and number parsing moved to canvas-org.el when canvas-quiz.el
;; grew due, unlock, and lock dates of its own; the old name still works.
(define-obsolete-variable-alias 'canvas-assignment-default-due-time
  'canvas-org-default-due-time "canvas-assignment 1.1")

;;; Metadata

(defun canvas-assignment--submission-types (types)
  "Normalise TYPES, a list of Canvas submission types, checking each one.
Matching ignores case and reads a hyphen as an underscore, so
\"Online-Upload\" means `online_upload'.  A string is split like the
keyword itself, so a `canvas-assignment-default-submission-types'
customised to \"online_upload\" rather than a list still works."
  (let ((types (mapcar (lambda (type)
                         (replace-regexp-in-string
                          "-" "_" (downcase (string-trim type))))
                       (if (stringp types) (canvas-org-split-list types) types))))
    (dolist (type types types)
      (unless (member type canvas-assignment-submission-types)
        (user-error "%S is not a Canvas submission type; ASSIGNMENT_SUBMISSION_TYPES takes %s"
                    type (string-join canvas-assignment-submission-types ", "))))))

(defun canvas-assignment--metadata (get)
  "Collect assignment metadata using GET, a function of one keyword string.
GET returns the raw string value of `ASSIGNMENT_KEY' or nil, however the
caller happens to look it up (buffer keywords, or subtree properties)."
  (list :points (or (canvas-org-number (funcall get "POINTS") "ASSIGNMENT_POINTS")
                    canvas-assignment-default-points)
        :due (canvas-org-parse-time (funcall get "DUE") "ASSIGNMENT_DUE" t)
        :unlock (canvas-org-parse-time (funcall get "UNLOCK") "ASSIGNMENT_UNLOCK" nil)
        :lock (canvas-org-parse-time (funcall get "LOCK") "ASSIGNMENT_LOCK" t)
        :submission-types (canvas-assignment--submission-types
                           (or (canvas-org-split-list (funcall get "SUBMISSION_TYPES"))
                               canvas-assignment-default-submission-types))
        :allowed-extensions (canvas-org-split-list (funcall get "ALLOWED_EXTENSIONS"))
        :grading-type (or (funcall get "GRADING_TYPE") canvas-assignment-default-grading-type)
        :group (funcall get "GROUP")
        :published (canvas-org-truthy (funcall get "PUBLISHED"))
        :peer-reviews (canvas-org-truthy (funcall get "PEER_REVIEWS"))
        :omit-from-final (canvas-org-truthy (funcall get "OMIT_FROM_FINAL_GRADE"))
        :notify (canvas-org-truthy (funcall get "NOTIFY"))
        :attempts (canvas-org-number (funcall get "ATTEMPTS") "ASSIGNMENT_ATTEMPTS")
        :assignment-id (canvas-org-number (funcall get "ID") "ASSIGNMENT_ID")
        :course-id (canvas-org-number (funcall get "COURSE_ID") "ASSIGNMENT_COURSE_ID")))

(defun canvas-assignment--buffer-metadata ()
  "Collect assignment metadata from the current buffer's #+KEYWORD: lines."
  (let* ((get (lambda (key) (canvas-org-keyword (concat "ASSIGNMENT_" key))))
         (name (or (funcall get "NAME") (canvas-org-keyword "TITLE"))))
    (unless name
      (user-error "Missing required #+ASSIGNMENT_NAME: (or #+TITLE:) keyword"))
    (append (list :name name) (canvas-assignment--metadata get))))

(defun canvas-assignment--subtree-metadata ()
  "Collect assignment metadata for the subtree at point.
The headline is the assignment name unless an `:ASSIGNMENT_NAME:' property
overrides it; the other `:ASSIGNMENT_*:' properties mirror the buffer
keywords, and are inherited, so a parent headline can set them for a whole
section.  Anything unset falls back to the buffer's keywords."
  (let* ((get (lambda (key)
                (let ((prop (concat "ASSIGNMENT_" key)))
                  (if (equal key "ID")
                      ;; An ID names one specific assignment, so unlike the
                      ;; rest it is never inherited from a parent headline or
                      ;; from the buffer.
                      (org-entry-get nil prop)
                    (or (org-entry-get nil prop t) (canvas-org-keyword prop))))))
         (name (or (org-entry-get nil "ASSIGNMENT_NAME" t)
                   (substring-no-properties (org-get-heading t t t t)))))
    (when (or (null name) (string-empty-p (string-trim name)))
      (user-error "Subtree has no headline text to use as an assignment name"))
    (append (list :name (string-trim name))
            (canvas-assignment--metadata get))))

;;; Parsing

(defun canvas-assignment--parse (subtreep)
  "Build the assignment plist for the buffer, or SUBTREEP's subtree at point.
Returns the metadata plist with :description (the exported HTML) added."
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an Org buffer"))
  (if subtreep
      ;; Read the properties and export from the headline itself, so both see
      ;; the same subtree no matter where in it point happened to be.
      (save-excursion
        (unless (or (org-at-heading-p) (ignore-errors (org-back-to-heading t)))
          (user-error "Point is not inside a subtree"))
        (let ((meta (canvas-assignment--subtree-metadata)))
          (plist-put meta :description (canvas-org-export-body t))))
    (let ((meta (canvas-assignment--buffer-metadata)))
      (plist-put meta :description (canvas-org-export-body nil)))))

;;; Canvas

(defun canvas-assignment--find-existing-id (course-id name)
  "Return the ID of the assignment in COURSE-ID named NAME, or nil."
  (let ((results (canvas-api-request
                  "GET" (format "courses/%s/assignments" course-id)
                  (canvas-api-search-params name)
                  t)))
    (cl-loop with wanted = (downcase name)
             for assignment across (or results [])
             when (equal (downcase (or (alist-get 'name assignment) "")) wanted)
             return (alist-get 'id assignment))))

(defun canvas-assignment--params (assignment publish group-id)
  "Build the `assignment[...]' params alist for ASSIGNMENT.
PUBLISH is the resolved publish state; GROUP-ID the resolved assignment
group ID, or nil to leave the group to Canvas."
  (let ((params `(("name" . ,(plist-get assignment :name))
                  ("description" . ,(plist-get assignment :description))
                  ("published" . ,(if publish "true" "false"))
                  ("submission_types" . ,(vconcat (plist-get assignment :submission-types))))))
    (cl-flet ((add (key value) (when value (setq params (append params `((,key . ,value)))))))
      (add "points_possible" (plist-get assignment :points))
      (add "due_at" (plist-get assignment :due))
      (add "unlock_at" (plist-get assignment :unlock))
      (add "lock_at" (plist-get assignment :lock))
      (add "grading_type" (plist-get assignment :grading-type))
      (add "assignment_group_id" group-id)
      (add "allowed_attempts" (plist-get assignment :attempts))
      (when (plist-get assignment :allowed-extensions)
        (add "allowed_extensions" (vconcat (plist-get assignment :allowed-extensions))))
      (when (plist-get assignment :peer-reviews) (add "peer_reviews" "true"))
      (when (plist-get assignment :omit-from-final) (add "omit_from_final_grade" "true"))
      (when (plist-get assignment :notify) (add "notify_of_update" "true")))
    params))

(defun canvas-assignment--put (course-id assignment-id assignment publish group-id)
  "Update ASSIGNMENT-ID in COURSE-ID from ASSIGNMENT."
  (canvas-api-request
   "PUT" (format "courses/%s/assignments/%s" course-id assignment-id)
   `(("assignment" . ,(canvas-assignment--params assignment publish group-id)))))

(defun canvas-assignment--post (course-id assignment publish group-id)
  "Create ASSIGNMENT in COURSE-ID."
  (canvas-api-request
   "POST" (format "courses/%s/assignments" course-id)
   `(("assignment" . ,(canvas-assignment--params assignment publish group-id)))))

;;; Commands

(defun canvas-assignment--do-upload (subtreep publish)
  "Upload the buffer, or SUBTREEP's subtree at point, to Canvas as an assignment.
PUBLISH forces the assignment published regardless of its metadata."
  (let* ((assignment (canvas-assignment--parse subtreep))
         (name (plist-get assignment :name))
         (course-id (canvas-api-read-course-id (plist-get assignment :course-id)))
         (publish (or publish (plist-get assignment :published)))
         (group (plist-get assignment :group))
         (group-id (and group (canvas-api-assignment-group-id course-id group)))
         (existing (or (plist-get assignment :assignment-id)
                       (progn (message "Looking for an existing assignment named %S..." name)
                              (canvas-assignment--find-existing-id course-id name)))))
    (message "%s assignment %S..." (if existing "Updating" "Creating") name)
    (let ((result (if existing
                      (canvas-assignment--put course-id existing assignment publish group-id)
                    (canvas-assignment--post course-id assignment publish group-id))))
      (message "%s %S (%s) at %s"
               (if existing "Updated" "Created")
               name
               (if publish "published" "unpublished")
               (or (alist-get 'html_url result)
                   (format "https://%s/courses/%s/assignments/%s"
                           (canvas-api-domain) course-id (or (alist-get 'id result) "")))))))

;;;###autoload
(defun canvas-assignment-upload (&optional publish)
  "Upload the current Org buffer to Canvas as an assignment.
An assignment in the course with the same name is updated in place; if
there is none, a new one is created.  With a prefix argument PUBLISH,
publish the assignment; otherwise it is published only if the buffer says
`#+ASSIGNMENT_PUBLISHED: t'."
  (interactive "P")
  (canvas-assignment--do-upload nil publish))

;;;###autoload
(defun canvas-assignment-upload-subtree (&optional publish)
  "Upload the Org subtree at point to Canvas as an assignment.
The headline is the assignment name unless an `:ASSIGNMENT_NAME:' property
overrides it.  With a prefix argument PUBLISH, publish the assignment;
otherwise it is published only if an `:ASSIGNMENT_PUBLISHED: t' property
says so."
  (interactive "P")
  (canvas-assignment--do-upload t publish))

(defun canvas-assignment--show-preview (assignment publish)
  "Display ASSIGNMENT's metadata and description HTML in a preview buffer."
  (let ((buf (get-buffer-create "*canvas-assignment-preview*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "Name:      %s\n" (plist-get assignment :name)))
        (insert (format "Points:    %s\n" (or (plist-get assignment :points) "(Canvas default)")))
        (insert (format "Published: %s\n" (if (or publish (plist-get assignment :published)) "yes" "no")))
        (insert (format "Submission types: %s\n"
                        (string-join (plist-get assignment :submission-types) ", ")))
        (dolist (row '((:due "Due" ) (:unlock "Unlock") (:lock "Lock")))
          (when (plist-get assignment (car row))
            (insert (format "%s: %s\n" (cadr row) (plist-get assignment (car row))))))
        (when (plist-get assignment :allowed-extensions)
          (insert (format "Allowed extensions: %s\n"
                          (string-join (plist-get assignment :allowed-extensions) ", "))))
        (when (plist-get assignment :grading-type)
          (insert (format "Grading type: %s\n" (plist-get assignment :grading-type))))
        (when (plist-get assignment :group)
          (insert (format "Assignment group: %s (resolved at upload time)\n"
                          (plist-get assignment :group))))
        (when (plist-get assignment :attempts)
          (insert (format "Allowed attempts: %s\n" (plist-get assignment :attempts))))
        (when (plist-get assignment :peer-reviews)
          (insert "Peer reviews: yes\n"))
        (when (plist-get assignment :omit-from-final)
          (insert "Omit from final grade: yes\n"))
        (when (plist-get assignment :notify)
          (insert "Notify of update: yes\n"))
        (insert (format "Target:    %s\n"
                        (if (plist-get assignment :assignment-id)
                            (format "assignment %s (from ASSIGNMENT_ID)"
                                    (plist-get assignment :assignment-id))
                          "an assignment with this name, else a new one")))
        (when (plist-get assignment :course-id)
          (insert (format "Course ID: %s (from metadata)\n" (plist-get assignment :course-id))))
        (insert "\n--- description HTML ---\n\n")
        (insert (plist-get assignment :description))
        (insert "\n"))
      (goto-char (point-min)))
    (pop-to-buffer buf)))

;;;###autoload
(defun canvas-assignment-preview (&optional publish)
  "Show what `canvas-assignment-upload' would send for the current buffer.
Makes no network calls.  PUBLISH mirrors the prefix argument to
`canvas-assignment-upload' and only affects the reported publish state."
  (interactive "P")
  (canvas-assignment--show-preview (canvas-assignment--parse nil) publish))

;;;###autoload
(defun canvas-assignment-preview-subtree (&optional publish)
  "Show what `canvas-assignment-upload-subtree' would send for the subtree.
Uses the subtree at point.  Makes no network calls.  PUBLISH mirrors the
prefix argument to `canvas-assignment-upload-subtree'."
  (interactive "P")
  (canvas-assignment--show-preview (canvas-assignment--parse t) publish))

(provide 'canvas-assignment)
;;; canvas-assignment.el ends here
