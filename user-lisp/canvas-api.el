;;; canvas-api.el --- Shared plumbing for talking to the Canvas REST API -*- lexical-binding: t; -*-

;; The bits every canvas-* module in this repository needs: where the Canvas
;; instance lives, how to get its API token out of `auth-source', how to turn
;; a (possibly nested) alist into the Rails-bracket form encoding Canvas
;; expects, and how to make a synchronous request with `url.el' -- no external
;; dependencies.
;;
;; Nothing here knows about quizzes or pages; see canvas-quiz.el and
;; canvas-page.el for those.

;;; Code:

(require 'auth-source)
(require 'url)
(require 'url-util)
(require 'json)
(require 'cl-lib)

(defgroup canvas nil
  "Push Org-authored course material into Canvas."
  :group 'org)

(defcustom canvas-domain nil
  "Canvas domain to talk to, e.g. \"myschool.instructure.com\".

The API access token is looked up via `auth-source' using this domain
as the host, so `~/.authinfo.gpg' should have a line such as:

  machine myschool.instructure.com login canvas password TOKEN"
  :type '(choice (const :tag "Unset" nil) string)
  :group 'canvas)

(defcustom canvas-default-course-id nil
  "Default Canvas course ID offered when uploading.
Still prompts every time; this just pre-fills the prompt."
  :type '(choice (const :tag "None" nil) integer)
  :group 'canvas)

(defcustom canvas-api-timeout 30
  "Seconds to wait for a Canvas API response before giving up."
  :type 'integer
  :group 'canvas)

;;; Credentials

(defun canvas-api-domain ()
  "Return `canvas-domain', erroring with guidance if unset."
  (or canvas-domain
      (user-error "Set `canvas-domain' first, e.g. (setq canvas-domain \"myschool.instructure.com\")")))

(defun canvas-api-token ()
  "Look up the Canvas API token for `canvas-domain' via `auth-source'."
  (let* ((domain (canvas-api-domain))
         (found (car (auth-source-search :host domain :max 1)))
         (secret (plist-get found :secret)))
    (unless found
      (user-error "No auth-source entry for host %S; add a line like `machine %s login canvas password TOKEN' to ~/.authinfo.gpg" domain domain))
    (if (functionp secret) (funcall secret) secret)))

;;; Parameter encoding

(defun canvas-api--flatten-params (params &optional prefix)
  "Flatten PARAMS (an alist, possibly nested) into Rails-bracket key/value
conses suitable for an application/x-www-form-urlencoded body.

A value that is itself an alist (its first element's car is a string, e.g.
\\=(\"title\" . \"Foo\")\\=) recurses with a \"PREFIX[KEY]\" prefix; a value
that is a list of alists (its first element's car is itself a cons)
recurses with a \"PREFIX[]\" prefix for each element -- used for
question[answers][]."
  (cl-loop for (key . value) in params
           append
           (let ((full-key (if prefix (format "%s[%s]" prefix key) (format "%s" key))))
             (cond
              ((and (consp value) (consp (car value)) (stringp (caar value)))
               ;; value is itself an alist -> nested object
               (canvas-api--flatten-params value full-key))
              ((and (consp value) (consp (car value)))
               ;; value is a list of alists -> array of objects
               (cl-loop for element in value
                        append (canvas-api--flatten-params element (concat full-key "[]"))))
              (t (list (cons full-key value)))))))

(defun canvas-api-encode-params (params)
  "Encode PARAMS (an alist, possibly nested) as a urlencoded string."
  (mapconcat
   (lambda (pair)
     (concat (url-hexify-string (car pair)) "=" (url-hexify-string (format "%s" (cdr pair)))))
   (canvas-api--flatten-params params)
   "&"))

;;; Requests

(defun canvas-api-request (method path &optional params allow-404)
  "Make a synchronous METHOD request to Canvas at PATH with PARAMS.
PATH is relative to /api/v1/.  For \"GET\", PARAMS become a query string;
otherwise they become a form-encoded body.  Returns the parsed JSON
response (an alist, or a vector of alists for a collection).

With ALLOW-404 non-nil, a 404 response returns nil instead of signalling."
  (let* ((get-p (equal method "GET"))
         (encoded (and params (canvas-api-encode-params params)))
         (url (concat (format "https://%s/api/v1/%s" (canvas-api-domain) path)
                      (if (and get-p encoded (not (string-empty-p encoded)))
                          (concat "?" encoded)
                        "")))
         (url-request-method method)
         (url-request-extra-headers
          `(("Authorization" . ,(concat "Bearer " (canvas-api-token)))
            ,@(unless get-p '(("Content-Type" . "application/x-www-form-urlencoded")))))
         (url-request-data (unless get-p encoded))
         (buffer (url-retrieve-synchronously url t t canvas-api-timeout)))
    (unless buffer
      (user-error "Canvas request to %s timed out or failed" url))
    (unwind-protect
        (with-current-buffer buffer
          (goto-char (point-min))
          (unless (looking-at "HTTP/[0-9.]+ \\([0-9]+\\)")
            (user-error "Unexpected response from Canvas: %s" (buffer-string)))
          (let ((status (string-to-number (match-string 1))))
            (goto-char (point-min))
            (search-forward "\n\n" nil t)
            (let* ((raw (buffer-substring-no-properties (point) (point-max)))
                   ;; url.el hands back the raw bytes in a unibyte buffer;
                   ;; decode so non-ASCII in responses (and error messages)
                   ;; survives.
                   (body (if (multibyte-string-p raw) raw (decode-coding-string raw 'utf-8)))
                   (parsed (condition-case nil
                               (json-parse-string body :object-type 'alist :null-object nil)
                             (error nil))))
              (cond
               ((and (>= status 200) (< status 300)) parsed)
               ((and allow-404 (= status 404)) nil)
               (t (user-error "Canvas request to %s failed (%d): %s" url status body))))))
      (kill-buffer buffer))))

(defun canvas-api-read-course-id (&optional default)
  "Prompt for a Canvas course ID, defaulting to DEFAULT or
`canvas-default-course-id'."
  (read-number "Canvas course ID: " (or default canvas-default-course-id)))

(provide 'canvas-api)
;;; canvas-api.el ends here
