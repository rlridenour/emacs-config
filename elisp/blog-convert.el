(defun fix-blog-title ()
  (interactive)
  (beginning-of-buffer)
  (re-search-forward "title")
  (beginning-of-line)
  (insert "#+")
  (replace-string-in-region "\'" "" (line-beginning-position) (line-end-position))
  )


(defun fix-blog-date ()
  (interactive)
  (beginning-of-buffer)
  (re-search-forward "date")
  (beginning-of-line)
  (insert "#+")
  (re-search-forward ": ")
  (kill-visual-line)
  (insert (format-time-string "<%Y-%m-%d>" (date-to-time (current-kill 0 t))))
  )

