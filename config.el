(use-package cape
  :commands (cape-file)
  :bind
  (("M-p p" . completion-at-point) ;; capf
   ("M-p d" . cape-dabbrev)        ;; or dabbrev-completion
   ("M-p a" . cape-abbrev)
   ("M-p w" . cape-dict)
   ("M-p \\" . cape-tex)
   ("M-p _" . cape-tex)
   ("M-p ^" . cape-tex))
  :init
  ;; Add to the global default value of `completion-at-point-functions' which is
  ;; used by `completion-at-point'.  The order of the functions matters, the
  ;; first function returning a result wins.  Note that the list of buffer-local
  ;; completion functions takes precedence over the global list.
  (add-hook 'completion-at-point-functions #'cape-dabbrev)
  (add-hook 'completion-at-point-functions #'cape-file)
  (add-hook 'completion-at-point-functions #'cape-elisp-block)
  (add-hook 'completion-at-point-functions #'cape-history)
  )
