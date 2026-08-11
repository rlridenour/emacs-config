;;; question-convert.el --- Convert LaTeX question environments to plain text -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Converts
;;
;;   \begin{question}
;;     Question text
;;     \choice {Answer 1}
;;     \choice[!] {Answer 2}
;;     \choice {Answer 3}
;;     \choice {Answer 4}
;;   \end{question}
;;
;; into
;;
;;   1. Question text
;;        a) Answer 1
;;        b) Answer 2*
;;        c) Answer 3
;;        d) Answer 4
;;
;; The [!] marker (correct answer) may appear on any \choice line.

;;; Code:

(defgroup question-convert nil
  "Convert LaTeX question environments to numbered plain text."
  :group 'tex)

(defcustom question-convert-choice-indent 5
  "Number of spaces used to indent each choice line."
  :type 'integer
  :group 'question-convert)

(defcustom question-convert-correct-marker "*"
  "String appended to the choice flagged with [!]."
  :type 'string
  :group 'question-convert)

(defun question-convert--brace-group (string pos)
  "Read the brace group in STRING that starts at POS (which must be a `{').
Return a cons cell (CONTENTS . END), where END is the index just
past the closing brace, or nil if the group is unbalanced."
  (let ((len (length string))
        (depth 0)
        (i pos)
        (start (1+ pos))
        (end nil))
    (while (and (< i len) (null end))
      (let ((c (aref string i)))
        (cond
         ;; Skip escaped characters such as \{ \} \\
         ((and (eq c ?\\) (< (1+ i) len))
          (setq i (+ i 2)))
         ((eq c ?\{)
          (setq depth (1+ depth) i (1+ i)))
         ((eq c ?\})
          (setq depth (1- depth))
          (when (zerop depth) (setq end i))
          (setq i (1+ i)))
         (t (setq i (1+ i))))))
    (and end (cons (substring string start end) (1+ end)))))

(defun question-convert--squeeze (string)
  "Collapse all runs of whitespace in STRING to single spaces and trim it."
  (string-trim (replace-regexp-in-string "[ \t\n\r]+" " " string)))

(defun question-convert--label (n)
  "Return the letter label for choice N (zero-based): a, b, ... z, aa, ab, ..."
  (let ((label ""))
    (setq n (1+ n))
    (while (> n 0)
      (setq n (1- n))
      (setq label (concat (char-to-string (+ ?a (% n 26))) label))
      (setq n (/ n 26)))
    label))

(defun question-convert-body (body number)
  "Convert the BODY of one question environment to plain text.
NUMBER is the question number to print."
  (let ((pos 0)
        (first-choice nil)
        (choices '()))
    ;; Collect every \choice[...]{...} in BODY.
    (while (string-match "\\\\choice[ \t\n]*\\(\\[[^]]*\\]\\)?[ \t\n]*{" body pos)
      (let* ((match-start (match-beginning 0))
             (opt (match-string 1 body))
             (brace (1- (match-end 0)))
             (group (question-convert--brace-group body brace)))
        (unless first-choice (setq first-choice match-start))
        (if (null group)
            (setq pos (length body))     ; unbalanced braces: stop scanning
          (push (cons (question-convert--squeeze (car group))
                      (and opt (string-match-p "!" opt)))
                choices)
          (setq pos (cdr group)))))
    (setq choices (nreverse choices))
    (let ((question (question-convert--squeeze
                     (substring body 0 (or first-choice (length body)))))
          (indent (make-string question-convert-choice-indent ?\s))
          (i -1))
      (concat
       (format "%d. %s" number question)
       (mapconcat (lambda (choice)
                    (setq i (1+ i))
                    (format "\n%s%s) %s%s"
                            indent
                            (question-convert--label i)
                            (car choice)
                            (if (cdr choice)
                                question-convert-correct-marker
                              "")))
                  choices "")))))

;;;###autoload
(defun question-convert-region (beg end)
  "Convert every question environment between BEG and END to plain text.
Interactively, operate on the region when it is active, otherwise on
the whole buffer.  Questions are numbered sequentially starting at 1,
choices are labeled a), b), c), ..., and the choice marked with [!] gets
a trailing `*'."
  (interactive
   (if (use-region-p)
       (list (region-beginning) (region-end))
     (list (point-min) (point-max))))
  (let ((number 0)
        (count 0))
    (save-excursion
      (save-restriction
        (narrow-to-region beg end)
        (goto-char (point-min))
        (while (re-search-forward
                "^[ \t]*\\\\begin{question}\\(?:\\[[^]]*\\]\\)?[ \t]*\n?" nil t)
          (let ((start (match-beginning 0))
                (body-start (point)))
            (if (not (re-search-forward "^[ \t]*\\\\end{question}[ \t]*" nil t))
                (goto-char (point-max))
              ;; Grab the match bounds before calling anything that might
              ;; clobber the match data.
              (let* ((body (buffer-substring-no-properties
                            body-start (match-beginning 0)))
                     (stop (match-end 0))
                     (text (question-convert-body body (setq number (1+ number)))))
                (delete-region start stop)
                (goto-char start)
                (insert text)
                (setq count (1+ count))))))))
    (when (called-interactively-p 'interactive)
      (message "Converted %d question%s." count (if (= count 1) "" "s")))
    count))

;;;###autoload
(defun question-convert-buffer ()
  "Convert every question environment in the current buffer to plain text."
  (interactive)
  (question-convert-region (point-min) (point-max)))

(provide 'question-convert)
;;; question-convert.el ends here
