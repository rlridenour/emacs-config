;;; org-mcq-to-lisp.el --- Convert an Org multiple-choice list item to a Lisp quiz block  -*- lexical-binding: t; -*-

;; Usage: place point anywhere inside a list item of the form:
;;
;;   1. Whether human beings have a non-physical soul is a topic in
;;        a) metaphysics*
;;        b) epistemology
;;        c) ethics
;;        d) aesthetics
;;
;; (the answer ending in "*" is the correct one; the "*" itself is not
;; part of the answer text) and call `org-mcq-item-to-lisp-block'.  It
;; will build the corresponding Lisp data structure, wrap it in a
;; #+begin_src lisp ... #+end_src block, and append that block to the
;; end of the buffer displayed in the other/adjacent window.

(require 'cl-lib)
(require 'subr-x)

(defun org-mcq--escape-string (s)
  "Escape backslashes and double quotes in S for embedding in a Lisp string literal."
  (replace-regexp-in-string
   "\"" "\\\\\""
   (replace-regexp-in-string "\\\\" "\\\\\\\\" s)))

(defun org-mcq--parse-item ()
  "Parse the multiple-choice Org item at point.
Return a list (QUESTION-TEXT . ANSWERS), where ANSWERS is a list of
\(TEXT . CORRECT-P) conses, in the order they appear."
  (save-excursion
    (let (question-text answers)
      ;; Walk backward to the numbered question line, e.g. "1. ..." or "1) ...".
      (beginning-of-line)
      (while (and (not (looking-at "^[ \t]*[0-9]+[.)][ \t]+\\(.*\\)$"))
                  (not (bobp)))
        (forward-line -1))
      (unless (looking-at "^[ \t]*[0-9]+[.)][ \t]+\\(.*\\)$")
        (user-error "No numbered question line found above point"))
      (setq question-text (string-trim (match-string 1)))
      ;; Walk forward collecting lettered answer lines, e.g. "   a) text*".
      (forward-line 1)
      (while (looking-at "^[ \t]*[a-zA-Z])[ \t]+\\(.*\\)$")
        (let* ((raw (string-trim (match-string 1)))
               (correct (string-suffix-p "*" raw))
               (text (if correct
                         (string-trim (substring raw 0 (1- (length raw))))
                       raw)))
          (push (cons text correct) answers))
        (forward-line 1))
      (setq answers (nreverse answers))
      (unless answers
        (user-error "No lettered answers found below the question line"))
      (cons question-text answers))))

(defun org-mcq--build-block (question-text answers)
  "Build the #+begin_src lisp ... #+end_src text for QUESTION-TEXT and ANSWERS."
  (let* ((q (org-mcq--escape-string question-text))
         (answers-prefix "   (:answers . (")
         (indent (make-string (length answers-prefix) ?\s))
         (answer-strings
          (mapcar (lambda (a)
                    (format "((:text . \"%s\") (:correct . %s))"
                            (org-mcq--escape-string (car a))
                            (if (cdr a) "t" "nil")))
                  answers))
         (n (length answer-strings)))
    (concat
     "#+begin_src lisp\n"
     "  ((:type . :multiple-choice)\n"
     (format "   (:question-name . \"%s\")\n" q)
     (format "   (:question-text . \"%s\")\n" q)
     "   (:points . 1)\n"
     answers-prefix
     (cl-loop for s in answer-strings
              for i from 0
              concat (if (zerop i) s (concat "\n" indent s)))
     ")))\n"
     "#+end_src\n")))

;;;###autoload
(defun org-mcq-item-to-lisp-block ()
  "Convert the Org multiple-choice list item at point into a Lisp
quiz data structure, wrapped in a #+begin_src lisp block, and
append it to the buffer shown in the adjacent (other) window.

The item at point is expected to look like:

  1. Question text here
       a) wrong answer
       b) correct answer*
       c) wrong answer

The single answer whose text ends in \"*\" is marked
\(:correct . t); all others are marked (:correct . nil), and the
trailing \"*\" is stripped from the answer text before it is used."
  (interactive)
  (let* ((parsed (org-mcq--parse-item))
         (question-text (car parsed))
         (answers (cdr parsed))
         (block (org-mcq--build-block question-text answers))
         (target-window (or (window-in-direction 'right)
                             (window-in-direction 'left)
                             (window-in-direction 'below)
                             (window-in-direction 'above)
                             (next-window)))
         (target-buffer (window-buffer target-window)))
    (when (eq target-buffer (current-buffer))
      (user-error "No adjacent window with a different buffer was found"))
    (with-current-buffer target-buffer
      (goto-char (point-max))
      (unless (or (bobp) (bolp))
        (insert "\n"))
      (insert "\n" block))
    (message "Appended multiple-choice question to %s" (buffer-name target-buffer))))

;;; The following two functions are used to copy lisp-format questions to an adjacent buffer.

(defun outer-sexp-bounds ()
  "Return (START . END) of the outermost parenthesized expression
enclosing point. If point isn't inside any parens, fall back to
the sexp at/around point."
  (save-excursion
    (let* ((open-positions (nth 9 (syntax-ppss))))
      (if open-positions
          (let ((start (car open-positions))) ; outermost open paren
            (goto-char start)
            (forward-sexp)
            (cons start (point)))
        (or (bounds-of-thing-at-point 'sexp)
            (save-excursion (backward-sexp) (bounds-of-thing-at-point 'sexp)))))))

(defun copy-sexp-to-other-window ()
  "Copy the outermost expression enclosing point to the buffer in
the adjacent window, inserting it at that buffer's point. Also
saves the text to the kill ring as a fallback."
  (interactive)
  (let* ((bounds (outer-sexp-bounds))
         (text (if bounds
                   (buffer-substring-no-properties (car bounds) (cdr bounds))
                 (user-error "No expression found at point")))
         (target (next-window nil 'no-minibuf)))
    (when (eq target (selected-window))
      (user-error "No adjacent window to copy into"))
    (kill-new text)
    (with-selected-window target
      (insert text))
    (message "Copied: %s"
             (if (> (length text) 40) (concat (substring text 0 40) "...") text))))

(provide 'org-mcq-to-lisp)
;;; org-mcq-to-lisp.el ends here
