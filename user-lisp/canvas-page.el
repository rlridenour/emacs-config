;;; canvas-page.el --- Upload an Org buffer or subtree to Canvas as a page -*- lexical-binding: t; -*-

;; `canvas-page-upload' pushes the current Org buffer into Canvas as a wiki
;; page; `canvas-page-upload-subtree' does the same for the subtree at point,
;; so one file can hold a whole course's worth of pages.
;;
;; Unlike canvas-quiz.el -- whose Org subset is small and fixed, and so is
;; parsed by hand -- a page is freeform prose, so the body is produced by
;; Org's own HTML exporter (body-only, no TOC, headlines starting at <h2>
;; because Canvas renders the page title as the <h1>).  Tables, links, code
;; blocks, footnotes, and LaTeX all come through as they would in any Org HTML
;; export.
;;
;;   #+PAGE_TITLE: Course Policies
;;   #+PAGE_PUBLISHED: t
;;
;;   Everything in the buffer becomes the page body.
;;
;; Uploading uses Canvas's PUT /courses/:id/pages/:url endpoint, which creates
;; the page if it is absent and overwrites it if it is present, so re-running
;; after an edit updates the same page rather than piling up copies.  The page
;; is located by searching Canvas for one whose title matches, falling back to
;; a slug derived from the title; `#+PAGE_URL:' (or a `:PAGE_URL:' property on
;; a subtree) pins it explicitly.  Note that this overwrites whatever is in
;; Canvas -- edits made in the Canvas UI are lost.
;;
;; `canvas-page-preview' renders the page and shows the exact HTML that would
;; be sent, with no network call, so it is safe to run any time.

;;; Code:

(require 'org)
(require 'ox-html)
(require 'cl-lib)
(require 'canvas-api)

(defgroup canvas-page nil
  "Upload Org-authored pages to Canvas."
  :group 'canvas)

(defcustom canvas-page-export-options
  '(:with-toc nil
    :section-numbers nil
    :html-toplevel-hlevel 2
    :html-self-link-headlines nil
    :html-container "div")
  "Extra export options passed to the HTML exporter for page bodies.
A plist in the form `org-export-as' accepts as its EXT-PLIST argument.
The defaults suit Canvas: no table of contents, no section numbers, and
headlines starting at <h2> because Canvas renders the page title as the
page's <h1>."
  :type '(plist)
  :group 'canvas-page)

(defcustom canvas-page-strip-generated-ids t
  "When non-nil, drop Org's auto-generated `id=\"orgXXXXXXX\"' anchors.
Org mints those anchors afresh on every export, so leaving them in makes
each upload differ from the last even when the Org source has not changed,
cluttering the page's revision history in Canvas.  Explicit `#+NAME:' and
`CUSTOM_ID' anchors are untouched, so internal links still work."
  :type 'boolean
  :group 'canvas-page)

(defcustom canvas-page-default-editing-roles nil
  "Default Canvas `editing_roles' for uploaded pages, or nil to let Canvas decide.
A comma-separated string; Canvas accepts \"teachers\", \"students\",
\"members\", and \"public\", e.g. \"teachers,students\"."
  :type '(choice (const :tag "Canvas default" nil) string)
  :group 'canvas-page)

;;; Metadata

(defun canvas-page--keyword (key)
  "Return the value of buffer keyword #+KEY:, or nil if absent or empty."
  (let ((val (cdr (assoc key (org-collect-keywords (list key))))))
    (when val
      (let ((s (string-trim (mapconcat #'identity val " "))))
        (unless (string-empty-p s) s)))))

(defun canvas-page--truthy (str)
  "Return non-nil if STR is an Org-ish spelling of true."
  (and str (member (downcase (string-trim str)) '("t" "true" "yes" "y" "1"))))

(defun canvas-page--buffer-metadata ()
  "Collect page metadata from the current buffer's #+KEYWORD: lines.
Return a plist (:title :url :published :front-page :editing-roles :notify
:course-id)."
  (let ((title (or (canvas-page--keyword "PAGE_TITLE")
                   (canvas-page--keyword "TITLE"))))
    (unless title
      (user-error "Missing required #+PAGE_TITLE: (or #+TITLE:) keyword"))
    (list :title title
          :url (canvas-page--keyword "PAGE_URL")
          :published (canvas-page--truthy (canvas-page--keyword "PAGE_PUBLISHED"))
          :front-page (canvas-page--truthy (canvas-page--keyword "PAGE_FRONT_PAGE"))
          :editing-roles (or (canvas-page--keyword "PAGE_EDITING_ROLES")
                             canvas-page-default-editing-roles)
          :notify (canvas-page--truthy (canvas-page--keyword "PAGE_NOTIFY"))
          :course-id (let ((id (canvas-page--keyword "PAGE_COURSE_ID")))
                       (and id (string-to-number id))))))

(defun canvas-page--subtree-metadata ()
  "Collect page metadata for the subtree at point.
The headline is the title unless a `:PAGE_TITLE:' property overrides it;
the other `:PAGE_*:' properties mirror the buffer keywords, and are
inherited, so a parent headline can set them for a whole section.  Falls
back to buffer keywords for anything unset."
  (let* ((buffer-meta (ignore-errors (canvas-page--buffer-metadata)))
         (get (lambda (prop) (org-entry-get nil prop t)))
         (title (or (funcall get "PAGE_TITLE")
                    (substring-no-properties
                     (org-get-heading t t t t)))))
    (when (or (null title) (string-empty-p (string-trim title)))
      (user-error "Subtree has no headline text to use as a page title"))
    (list :title (string-trim title)
          ;; A url is per-page, so unlike the rest it is never inherited from
          ;; a parent headline or from the buffer.
          :url (org-entry-get nil "PAGE_URL")
          :published (canvas-page--truthy (funcall get "PAGE_PUBLISHED"))
          :front-page (canvas-page--truthy (funcall get "PAGE_FRONT_PAGE"))
          :editing-roles (or (funcall get "PAGE_EDITING_ROLES")
                             (plist-get buffer-meta :editing-roles)
                             canvas-page-default-editing-roles)
          :notify (canvas-page--truthy (funcall get "PAGE_NOTIFY"))
          :course-id (let ((id (funcall get "PAGE_COURSE_ID")))
                       (if id
                           (string-to-number id)
                         (plist-get buffer-meta :course-id))))))

;;; Org -> HTML

(defun canvas-page--clean-html (html)
  "Post-process exported HTML for Canvas.
Currently just honours `canvas-page-strip-generated-ids'."
  (if canvas-page-strip-generated-ids
      (replace-regexp-in-string
       " id=\"\\(?:outline-container-\\|text-\\)?org[0-9a-f]+\"" "" html t t)
    html))

(defun canvas-page--export-body (subtreep)
  "Export the current buffer (or, with SUBTREEP, the subtree at point) to HTML.
Returns the body HTML only -- no <html>, <head>, title, or postamble."
  (let ((org-export-with-broken-links t))
    (canvas-page--clean-html
     (string-trim
      (org-export-as 'html subtreep nil t canvas-page-export-options)))))

(defun canvas-page--slug (title)
  "Derive a Canvas page URL slug from TITLE.
Mirrors how Canvas itself slugifies a title: non-word characters become
dashes, which are then trimmed from both ends, and the result is
downcased."
  (let* ((s (replace-regexp-in-string "[^[:alnum:]_]+" "-" title))
         (s (replace-regexp-in-string "\\`-+\\|-+\\'" "" s))
         (s (downcase s)))
    (if (string-empty-p s)
        (user-error "Cannot derive a Canvas page URL from title %S; set #+PAGE_URL:" title)
      s)))

;;; Parsing

(defun canvas-page--parse (subtreep)
  "Build the page plist for the current buffer, or SUBTREEP's subtree at point.
Returns the metadata plist with :body (the exported HTML) added."
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an Org buffer"))
  (if subtreep
      ;; Read the properties and export from the headline itself, so both see
      ;; the same subtree no matter where in it point happened to be.
      (save-excursion
        (unless (or (org-at-heading-p) (ignore-errors (org-back-to-heading t)))
          (user-error "Point is not inside a subtree"))
        (let ((meta (canvas-page--subtree-metadata)))
          (plist-put meta :body (canvas-page--export-body t))))
    (let ((meta (canvas-page--buffer-metadata)))
      (plist-put meta :body (canvas-page--export-body nil)))))

;;; Canvas

(defun canvas-page--find-existing-url (course-id title)
  "Return the Canvas page URL slug in COURSE-ID whose title matches TITLE.
Returns nil when no page matches.  Searching by title rather than trusting
a locally derived slug keeps re-uploads landing on the same page even when
Canvas slugified the title differently than `canvas-page--slug' would."
  (let ((results (canvas-api-request
                  "GET" (format "courses/%s/pages" course-id)
                  `(("search_term" . ,title) ("per_page" . 100))
                  t)))
    (cl-loop with wanted = (downcase title)
             for page across (or results [])
             when (equal (downcase (or (alist-get 'title page) "")) wanted)
             return (alist-get 'url page))))

(defun canvas-page--params (page publish)
  "Build the `wiki_page[...]' params alist for PAGE, publishing when PUBLISH."
  (let ((params `(("title" . ,(plist-get page :title))
                  ("body" . ,(plist-get page :body))
                  ("published" . ,(if publish "true" "false")))))
    (when (plist-get page :front-page)
      (setq params (append params '(("front_page" . "true")))))
    (when (plist-get page :editing-roles)
      (setq params (append params `(("editing_roles" . ,(plist-get page :editing-roles))))))
    (when (plist-get page :notify)
      (setq params (append params '(("notify_of_update" . "true")))))
    params))

(defun canvas-page--put (course-id url page publish)
  "Create or overwrite the page at slug URL in COURSE-ID from PAGE."
  (canvas-api-request
   "PUT"
   (format "courses/%s/pages/%s" course-id (url-hexify-string url))
   `(("wiki_page" . ,(canvas-page--params page publish)))))

;;; Commands

(defun canvas-page--do-upload (subtreep publish)
  "Upload the buffer, or SUBTREEP's subtree at point, to Canvas as a page.
PUBLISH forces the page published regardless of its metadata."
  (let* ((page (canvas-page--parse subtreep))
         (title (plist-get page :title))
         (course-id (canvas-api-read-course-id (plist-get page :course-id)))
         (publish (or publish (plist-get page :published)))
         (url (or (plist-get page :url)
                  (progn (message "Looking for an existing page named %S..." title)
                         (canvas-page--find-existing-url course-id title))
                  (canvas-page--slug title))))
    (message "Uploading page %S..." title)
    (let ((result (canvas-page--put course-id url page publish)))
      (message "Uploaded %S (%s) to %s"
               title
               (if publish "published" "unpublished")
               (or (alist-get 'html_url result)
                   (format "https://%s/courses/%s/pages/%s"
                           (canvas-api-domain) course-id url))))))

;;;###autoload
(defun canvas-page-upload (&optional publish)
  "Upload the current Org buffer to Canvas as a page.
The page is created if absent and overwritten if present, so re-running
after an edit updates the same page.  With a prefix argument PUBLISH,
publish the page; otherwise it is published only if the buffer says
`#+PAGE_PUBLISHED: t'."
  (interactive "P")
  (canvas-page--do-upload nil publish))

;;;###autoload
(defun canvas-page-upload-subtree (&optional publish)
  "Upload the Org subtree at point to Canvas as a page.
The headline is the page title unless a `:PAGE_TITLE:' property overrides
it.  With a prefix argument PUBLISH, publish the page; otherwise it is
published only if a `:PAGE_PUBLISHED: t' property says so."
  (interactive "P")
  (canvas-page--do-upload t publish))

(defun canvas-page--show-preview (page publish)
  "Display PAGE's metadata and HTML body in a preview buffer."
  (let ((buf (get-buffer-create "*canvas-page-preview*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "Title:     %s\n" (plist-get page :title)))
        (insert (format "URL slug:  %s%s\n"
                        (or (plist-get page :url)
                            (canvas-page--slug (plist-get page :title)))
                        (if (plist-get page :url)
                            " (from PAGE_URL)"
                          " (derived; an existing page with this title wins)")))
        (insert (format "Published: %s\n" (if (or publish (plist-get page :published)) "yes" "no")))
        (when (plist-get page :front-page)
          (insert "Front page: yes\n"))
        (when (plist-get page :editing-roles)
          (insert (format "Editing roles: %s\n" (plist-get page :editing-roles))))
        (when (plist-get page :notify)
          (insert "Notify of update: yes\n"))
        (when (plist-get page :course-id)
          (insert (format "Course ID: %s (from metadata)\n" (plist-get page :course-id))))
        (insert "\n--- body HTML ---\n\n")
        (insert (plist-get page :body))
        (insert "\n"))
      (goto-char (point-min)))
    (pop-to-buffer buf)))

;;;###autoload
(defun canvas-page-preview (&optional publish)
  "Show what `canvas-page-upload' would send for the current buffer.
Makes no network calls.  PUBLISH mirrors the prefix argument to
`canvas-page-upload' and only affects the reported publish state."
  (interactive "P")
  (canvas-page--show-preview (canvas-page--parse nil) publish))

;;;###autoload
(defun canvas-page-preview-subtree (&optional publish)
  "Show what `canvas-page-upload-subtree' would send for the subtree at point.
Makes no network calls.  PUBLISH mirrors the prefix argument to
`canvas-page-upload-subtree'."
  (interactive "P")
  (canvas-page--show-preview (canvas-page--parse t) publish))

(provide 'canvas-page)
;;; canvas-page.el ends here
