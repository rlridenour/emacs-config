;;; rlr-argument-functions.el --- Bracket-join a region into a #argument line -*- lexical-binding: t; -*-

;;; Turn an ordered list into something that will export as a standard-form argument in both Typst and HTML. Typst export requires the standard-form package at https://github.com/rlridenour/typst-standard-form.


(defun rlr/org-standard-form--item-text (pos struct)
  "Return the trimmed, marker-stripped body text of the item at POS in STRUCT."
  (let* ((end (org-list-get-item-end-before-blank pos struct))
         (raw (buffer-substring-no-properties pos end)))
    (string-trim
     (replace-regexp-in-string
      "[ \t]*\n[ \t]*" " "
      (replace-regexp-in-string
       "\\`[ \t]*\\(?:[-+*]\\|[0-9]+[.)]\\)[ \t]+" "" raw)))))

(defun rlr/org-standard-form--top-level-item-positions (struct)
  "Return the positions in STRUCT belonging to its outermost indentation level."
  (let* ((positions (mapcar #'car struct))
         (min-ind (apply #'min
                          (mapcar (lambda (pos) (org-list-get-ind pos struct))
                                  positions)))
         result)
    (dolist (pos positions (nreverse result))
      (when (= (org-list-get-ind pos struct) min-ind)
        (push pos result)))))

(defun rlr/org-make-standard-form ()
  "Turn the plain list at point into a standard-form argument.

Replaces the list with two copies: the first rewritten as an
\"#+begin_export html\" block containing an <ol class=\"org-ol arg\">
with one <li> per top-level item, and the second wrapped verbatim in
a \"#+begin_export typst\" block using `#standard-form[...]', for the
`standard-form' Typst package."
  (interactive)
  (require 'org-list)
  (unless (org-in-item-p)
    (user-error "Point is not inside an org list"))
  (let* ((struct (org-list-struct))
         (beg (org-list-get-top-point struct))
         (end (org-list-get-bottom-point struct))
         (orig-text (string-trim-right (buffer-substring-no-properties beg end)))
         (items (mapcar (lambda (pos) (rlr/org-standard-form--item-text pos struct))
                         (rlr/org-standard-form--top-level-item-positions struct)))
         (html-block
          (concat "#+begin_export html\n"
                  "<ol class=\"org-ol arg\">\n"
                  (mapconcat (lambda (item) (format "<li>%s</li>" item))
                             items "\n")
                  "\n</ol>\n"
                  "#+end_export\n"))
         (typst-block
          (concat "#+begin_export typst\n"
                  "#standard-form[\n"
                  orig-text "\n"
                  "]\n"
                  "#+end_export\n")))
    (goto-char beg)
    (delete-region beg end)
    (insert html-block "\n" typst-block)))

(provide 'rlr-argument-functions)
;;; rlr-argument-functions.el ends here
