;;; rlr-blog.el --- Org blog helpers -*- lexical-binding: t; -*-

;; Commands for writing and publishing the Org-based blog in
;; ~/sites/orgblog/.

;;; Code:

(require 'subr-x)
(require 's)

(defvar org-html-footnotes-section)
(declare-function yas-expand-snippet "yasnippet")
(declare-function yas-lookup-snippet "yasnippet")
(declare-function org-publish-all "ox-publish")
(declare-function org-link-set-parameters "ol")

(defvar orgblog-directory "~/sites/orgblog/" "Path to the Org mode blog.")
(defvar orgblog-public-directory (expand-file-name "docs/" orgblog-directory)
  "Path to the blog public directory.")
(defvar orgblog-posts-directory (expand-file-name "posts/" orgblog-directory)
  "Path to the blog posts directory.")
(defvar orgblog-drafts-directory (expand-file-name "drafts/" orgblog-directory)
  "Path to the blog drafts directory.")
(defvar orgblog-images-directory (expand-file-name "images/posts/" orgblog-directory)
  "Path to the blog post images directory.")

;;;; Posts

(defun orgblog--make-filename (title)
  "Convert TITLE to a filename string.
Remove punctuation, one or two-letter words, \"the\", and \"and\"."
  (downcase
   (string-join
    (split-string
     (replace-regexp-in-string
      "\\bthe \\b\\|\\band \\b\\|\\b[a-z]\\b \\|\\b[a-z][a-z]\\b \\|[[:punct:]]"
      "" title)
     " ")
    "-")))

;;;###autoload
(defun orgblog-new-post (title)
  "Create a new draft post titled TITLE."
  (interactive "sTitle: ")
  (find-file (concat orgblog-drafts-directory
                     (format-time-string "%Y-%m-%d-")
                     (orgblog--make-filename title)
                     ".org"))
  (insert "#+TITLE: " title "\n")
  (yas-expand-snippet (yas-lookup-snippet "orgblogt")))

;;;###autoload
(defun orgblog-insert-image ()
  "Insert a centered image link, prompting for the file."
  (interactive)
  (insert "#+begin_center\n#+ATTR_HTML: :width 100% :height\n"
          "[[" (file-relative-name
                (read-file-name "Insert file name: " orgblog-images-directory))
          "]]\n#+end_center\n\n"))

;;;###autoload
(defun orgblog-publish-draft ()
  "Move the current draft to the posts directory."
  (interactive)
  (save-buffer)
  (copy-file (buffer-file-name) orgblog-posts-directory)
  (delete-file (buffer-file-name) t)
  (kill-buffer)
  (dired orgblog-posts-directory))

;;;; Site

;;;###autoload
(defun orgblog-build ()
  "Publish the blog source to the public directory."
  (interactive)
  (find-file (expand-file-name "publish.el" orgblog-directory))
  (eval-buffer)
  (org-publish-all)
  (kill-buffer)
  (message "Build complete!"))

;;;###autoload
(defun orgblog-serve ()
  "Start the local server and open the site."
  (interactive)
  (async-shell-command "orgblog-serve")
  (sleep-for 2)
  (async-shell-command "open http://localhost:3000"))

;;;###autoload
(defun orgblog-push ()
  "Push changes to GitHub."
  (interactive)
  (async-shell-command "orgblog-push"))

;;;; Export

(with-eval-after-load 'ox-html
  (setq org-html-footnotes-section "<div id=\"footnotes\">
<h2 class=\"footnotes\">%s</h2>
<div id=\"text-footnotes\">
%s
</div>
</div>"))

;; Embed YouTube videos, from
;; https://endlessparentheses.com/embedding-youtube-videos-with-org-mode-links.html
;; Add a link like this: [[yt:3Aoa-yP5U_Y]]
(defvar orgblog-yt-iframe-format
  (concat "<iframe width=\"440\""
          " height=\"335\""
          " src=\"https://www.youtube.com/embed/%s\""
          " frameborder=\"0\""
          " allowfullscreen>%s</iframe>"))

(with-eval-after-load 'ol
  (org-link-set-parameters
   "yt"
   :follow (lambda (handle _)
             (browse-url (concat "https://www.youtube.com/embed/" handle)))
   :export (lambda (path desc backend _info)
             (cl-case backend
               (html (format orgblog-yt-iframe-format path (or desc "")))
               (latex (format "\\href{%s}{%s}" path (or desc "video")))))))

;;;; Tags

(defun orgblog-all-tag-lines ()
  "Get filetag lines from all posts."
  (let ((regex "^#\\+filetags:\\s([a-zA-Z]+)"))
    (shell-command-to-string
     (concat "rg --context 0 --no-filename --no-heading --replace \"\\$1\" -- "
             (shell-quote-argument regex) " " orgblog-posts-directory))))

(defun orgblog-all-tags ()
  "Return a list of unique tags from all posts."
  (delete-dups (split-string (orgblog-all-tag-lines) nil t)))

(defun orgblog-select-tag ()
  "Select a tag from the tags in the blog."
  (completing-read "Tag: " (orgblog-all-tags)))

(defun orgblog--insert-post-tag (tag)
  "Add TAG to the filetags line and the Tagged: line of the current post."
  (goto-char (point-min))
  (search-forward "#+filetags" nil 1)
  (end-of-line)
  (insert " " tag)
  (goto-char (point-min))
  (search-forward "Tagged:")
  (end-of-line)
  (insert " [[file:../tags/" tag ".org][" (s-titleized-words tag) "]]"))

(defun orgblog--add-post-to-tagfile (tag)
  "Add the current post to the page for TAG, creating the page if needed."
  (let* ((tagfile (concat "../tags/" tag ".org"))
         (post-filename (file-name-nondirectory (buffer-file-name)))
         (post-title (save-excursion
                       (goto-char (point-min))
                       (search-forward "#+title: " nil 1)
                       (buffer-substring (point) (line-end-position)))))
    (unless (file-exists-p tagfile)
      (write-region (concat "#+title: Tagged: " (s-titleized-words tag)
                            "\n#+setupfile: ../org-templates/post.org\n")
                    nil tagfile 'append 'silent))
    (write-region (concat "\n- [[file:../posts/" post-filename "][" post-title "]]")
                  nil tagfile 'append 'silent)))

;;;###autoload
(defun orgblog-add-tag ()
  "Select a tag, add it to the current post, and add the post to the tag page."
  (interactive)
  (let ((tag (orgblog-select-tag)))
    (orgblog--insert-post-tag tag)
    (orgblog--add-post-to-tagfile tag)
    (save-buffer)))

(provide 'rlr-blog)
;;; rlr-blog.el ends here
