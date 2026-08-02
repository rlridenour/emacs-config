(major-mode-hydra-define dired-mode
  (:quit-key "q")
  ("Tools"
   (("d" crux-open-with "Open in default program")
    ("." dired-omit-mode "Show hidden files")
    ("p" xah-copy-file-path "Copy filename and path")
    ("n" dired-toggle-read-only "edit Filenames")
    ("c" tex-clean "clean aux")
    ("C" tex-clean-all "clean all"))))
