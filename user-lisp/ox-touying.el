;;; ox-touying.el --- Org export backend for basic-theme content.typ -*- lexical-binding: t; -*-

;; Exports an Org buffer directly to a working content.typ for the
;; "basic-theme" Touying scaffold (see rlr-touying-scaffold.el) --
;; heading levels map onto section (=) / frame (==) / optional
;; subsection, matching the content.typ two-entry-point convention:
;; plain body text under a heading needs no wrapper.
;;
;; Conventions:
;;
;;   - Headline depth maps 1:1 onto Typst heading depth (`*` -> `=`,
;;     `**` -> `==`, `***` -> `===`). Whether `==` is a frame or a
;;     subsection is decided by the presentation's own slide-level in
;;     config.typ, not by this exporter.
;;   - #+begin_speakernote ... #+end_speakernote -> #speaker-note[...]
;;   - #+begin_handoutnote ... #+end_handoutnote -> #handout-note[...]
;;   - #+begin_center ... #+end_center -> #align(center)[...]
;;   - @@typst:...@@ export snippets pass through raw -- use
;;     @@typst:#pause@@ for a progressive reveal.
;;   - #+begin_statement ... #+end_statement -> big centered text: both
;;     axes via align(center + horizon), size via a preceding
;;     `#+ATTR_TOUYING: :size 3em' (default 2em if omitted). Often
;;     nested inside #+begin_fullslide for a blank, title-less slide.
;;   - #+begin_columns containing two #+begin_column ... #+end_column
;;     blocks -> #two-column-slide[...][...]
;;   - #+begin_fullslide ... #+end_fullslide -> #full-slide(...); a
;;     lone image link inside becomes
;;     image("path", width: 100%, height: 100%, fit: "cover") unless it
;;     has its own #+ATTR_TOUYING sizing (see below), which is kept
;;     as-is instead of being forced to fill the slide.
;;   - #+ATTR_TOUYING: :width ... :height ... :fit ... :align ...
;;     immediately before an image link, e.g. `#+ATTR_TOUYING: :width
;;     50%' -> #image("path", width: 50%). `:align' (e.g. `center',
;;     `center + horizon') wraps the image in #align(...), since
;;     alignment belongs to the surrounding container in Typst, not to
;;     image() itself, e.g. `#+ATTR_TOUYING: :height 100% :align
;;     center' -> #align(center, image("path", height: 100%)).
;;   - Bold/italic/code/lists/links get basic Typst equivalents.
;;     Tables, footnotes, and other exotic constructs aren't specially
;;     handled (falls back to ascii-backend rendering -- touch those
;;     up by hand in content.typ afterward).
;;
;; Usage: open the presentation's talk.org (in the same directory as
;; config.typ/content.typ), M-x rlr/org-export-to-touying-content --
;; overwrites content.typ in that directory. Re-export from the Org
;; source rather than hand-editing the generated content.typ.

(require 'ox)
(require 'subr-x)
(require 'seq)

(defconst rlr/touying--column-start "@@OXTOUYINGCOLUMNSTART@@"
  "Sentinel marking the start of a transcoded #+begin_column block.
Plain printable text, not a control character -- the ascii backend
this derives from silently strips control characters from output.")
(defconst rlr/touying--column-end "@@OXTOUYINGCOLUMNEND@@"
  "Sentinel marking the end of a transcoded #+begin_column block.")

(defun rlr/touying-plain-text (text _info)
  "Escape Typst-special characters in TEXT."
  (replace-regexp-in-string
   "[\\#`*_@]"
   (lambda (m) (concat "\\" m))
   text nil t))

(defun rlr/touying-bold (_bold contents _info)
  "Transcode a BOLD element into Typst strong emphasis."
  (format "*%s*" contents))

(defun rlr/touying-italic (_italic contents _info)
  "Transcode an ITALIC element into Typst emphasis."
  (format "_%s_" contents))

(defun rlr/touying-code (code _contents _info)
  "Transcode a CODE element into a Typst raw span."
  (format "`%s`" (org-element-property :value code)))

(defun rlr/touying-verbatim (verbatim _contents _info)
  "Transcode a VERBATIM element into a Typst raw span."
  (format "`%s`" (org-element-property :value verbatim)))

(defun rlr/touying-src-block (src-block _contents _info)
  "Transcode a SRC-BLOCK element into a Typst fenced raw block."
  (format "```%s\n%s```\n\n"
          (or (org-element-property :language src-block) "")
          (org-element-property :value src-block)))

(defun rlr/touying-paragraph (_paragraph contents _info)
  "Transcode a PARAGRAPH element into a Typst paragraph."
  (concat contents "\n\n"))

(defun rlr/touying-plain-list (_plain-list contents _info)
  "Transcode a PLAIN-LIST element, passing its items through."
  contents)

(defun rlr/touying--item-depth (item)
  "Return ITEM's nesting depth, 0 for a top-level list item.
Typst list items nest by leading indentation rather than by an explicit
parent/child structure, so the exporter needs to know how many
ancestor items ITEM is nested under."
  (let ((depth 0)
        (node (org-export-get-parent item)))
    (while node
      (when (eq (org-element-type node) 'item)
        (setq depth (1+ depth)))
      (setq node (org-export-get-parent node)))
    depth))

(defun rlr/touying-item (item contents _info)
  "Transcode an ITEM element into a Typst list item, indented by depth."
  (let* ((ordered (eq (org-element-property :type (org-export-get-parent item))
                       'ordered))
         (indent (make-string (* 2 (rlr/touying--item-depth item)) ?\s)))
    (format "%s%s %s\n" indent (if ordered "+" "-") (string-trim (or contents "")))))

(defun rlr/touying--attr-typst-string (value)
  "Format VALUE from an ATTR_TOUYING attribute as a Typst string.
`org-export-read-attribute' leaves an already-quoted value's quote
characters in place (e.g. `:fit \"contain\"' reads back as the string
literally containing quotes) -- use it as-is in that case rather than
quoting it again; otherwise quote VALUE."
  (if (and (stringp value) (string-prefix-p "\"" value) (string-suffix-p "\"" value))
      value
    (format "%S" value)))

(defun rlr/touying-link (link contents _info)
  "Transcode a LINK element into a Typst image call or #link[...].
An image link honors a preceding `#+ATTR_TOUYING: :width ... :height
... :fit ... :align ...' keyword: width/height/fit are passed straight
through as `image()' arguments, e.g. `#+ATTR_TOUYING: :width 50%'.
`:align' (e.g. `center', `center + horizon') wraps the image in
`#align(...)', since alignment is a property of the surrounding
container in Typst, not of `image()' itself."
  (let ((type (org-element-property :type link))
        (path (org-element-property :path link))
        (raw (org-element-property :raw-link link)))
    (cond
     ((and (member type '("file" nil))
           path
           (string-match-p "\\.\\(png\\|jpe?g\\|gif\\|svg\\|webp\\)\\'" path))
      (let* ((attrs (org-export-read-attribute
                     :attr_touying (org-export-get-parent-element link)))
             (args (delq nil
                         (list (format "%S" path)
                               (when (plist-get attrs :width)
                                 (format "width: %s" (plist-get attrs :width)))
                               (when (plist-get attrs :height)
                                 (format "height: %s" (plist-get attrs :height)))
                               (when (plist-get attrs :fit)
                                 (format "fit: %s" (rlr/touying--attr-typst-string
                                                     (plist-get attrs :fit)))))))
             (image-call (format "image(%s)" (mapconcat #'identity args ", "))))
        (if (plist-get attrs :align)
            (format "#align(%s, %s)" (plist-get attrs :align) image-call)
          (format "#%s" image-call))))
     (t
      (format "#link(%S)[%s]" raw (if (org-string-nw-p contents) contents raw))))))

(defun rlr/touying-export-snippet (export-snippet _contents _info)
  "Pass an @@typst:...@@ EXPORT-SNIPPET through raw."
  (when (eq (org-export-snippet-backend export-snippet) 'typst)
    (org-element-property :value export-snippet)))

(defun rlr/touying-special-block (special-block contents _info)
  "Transcode SPECIAL-BLOCK (speakernote/handoutnote/columns/fullslide/statement)."
  (let ((type (downcase (or (org-element-property :type special-block) "")))
        (trimmed (string-trim-right (or contents ""))))
    (cond
     ((string= type "speakernote")
      (format "#speaker-note[\n%s\n]\n\n" trimmed))
     ((string= type "handoutnote")
      (format "#handout-note[\n%s\n]\n\n" trimmed))
     ((string= type "statement")
      (let* ((attrs (org-export-read-attribute :attr_touying special-block))
             (size (or (plist-get attrs :size) "2em")))
        (format "#align(center + horizon, text(size: %s)[\n%s\n])\n\n" size trimmed)))
     ((string= type "column")
      (concat rlr/touying--column-start trimmed rlr/touying--column-end))
     ((string= type "columns")
      (let ((parts (seq-remove
                    #'string-blank-p
                    (mapcar (lambda (p)
                              (string-trim (string-remove-prefix
                                            rlr/touying--column-start
                                            (string-trim p))))
                            (split-string contents rlr/touying--column-end t)))))
        (if (= (length parts) 2)
            (format "#two-column-slide[\n%s\n][\n%s\n]\n\n"
                    (nth 0 parts) (nth 1 parts))
          trimmed)))
     ((string= type "fullslide")
      (cond
       ;; A lone image with no explicit sizing: force it to fill the slide.
       ;; #image(...)'s leading `#' is dropped -- inside full-slide(...)'s
       ;; parens we're already in code context, so it isn't needed there.
       ((and (string-match "\\`#image(\\(.*\\))\\'" trimmed)
             (not (string-match-p "\\(width\\|height\\|fit\\):" (match-string 1 trimmed))))
        (format "#full-slide(image(%s, width: 100%%, height: 100%%, fit: \"cover\"))\n\n"
                (match-string 1 trimmed)))
       ;; A lone image with its own #+ATTR_TOUYING sizing: respect it as-is.
       ((string-match "\\`#\\(image(.*)\\)\\'" trimmed)
        (format "#full-slide(%s)\n\n" (match-string 1 trimmed)))
       (t
        (format "#full-slide[\n%s\n]\n\n" trimmed))))
     (t contents))))

(defun rlr/touying-center-block (_center-block contents _info)
  "Transcode a CENTER-BLOCK element into a horizontally centered Typst block.
`#+begin_center'/`#+end_center' produces Org's own `center-block' element
type, distinct from the generic `special-block' used by speakernote/
handoutnote/etc, so it needs its own entry here."
  (format "#align(center)[\n%s\n]\n\n" (string-trim-right (or contents ""))))

(defun rlr/touying-section (_section contents _info)
  "Transcode a SECTION element, passing its content through."
  contents)

(defun rlr/touying-headline (headline contents info)
  "Transcode a HEADLINE element into a Typst heading."
  (let ((level (org-export-get-relative-level headline info))
        (title (org-export-data (org-element-property :title headline) info)))
    (concat (make-string level ?=) " " title "\n\n" (or contents ""))))

(defun rlr/touying-template (contents info)
  "Wrap the transcoded document CONTENTS in a content.typ file."
  (let ((title (org-export-data (plist-get info :title) info))
        (contents (replace-regexp-in-string "\n\\(\n+\\)" "\n\n" contents)))
    (format "// content.typ
// Slide content for %s, written once as a function of its building
// blocks so it can render either as live Touying slides (*-slides.typ) or
// as a flowing handout (*-handout.typ).
//
// Plain content under a heading needs no wrapper; only speaker-note/
// handout-note (which must differ between the live deck and the
// handout) and the two special layouts (two-column-slide, full-slide)
// are explicit calls.
//
// Generated from an Org source file by ox-touying.el -- re-export
// rather than hand-editing, or hand-edits will be overwritten.

#let content(
  title-slide,
  pause,
  speaker-note,
  handout-note,
  two-column-slide,
  full-slide,
) = [
  #title-slide()

%s]
"
            (if (org-string-nw-p title) title "Untitled")
            contents)))

(org-export-define-derived-backend 'touying 'ascii
  :translate-alist
  '((bold . rlr/touying-bold)
    (center-block . rlr/touying-center-block)
    (code . rlr/touying-code)
    (export-snippet . rlr/touying-export-snippet)
    (headline . rlr/touying-headline)
    (italic . rlr/touying-italic)
    (item . rlr/touying-item)
    (link . rlr/touying-link)
    (paragraph . rlr/touying-paragraph)
    (plain-list . rlr/touying-plain-list)
    (plain-text . rlr/touying-plain-text)
    (section . rlr/touying-section)
    (special-block . rlr/touying-special-block)
    (src-block . rlr/touying-src-block)
    (template . rlr/touying-template)
    (verbatim . rlr/touying-verbatim))
  :menu-entry
  '(?j "Export to Touying content.typ"
       ((?f "As content.typ file" rlr/org-export-to-touying-content))))

;;;###autoload
(defun rlr/org-export-to-touying-content (&optional async subtreep visible-only)
  "Export the current Org buffer to content.typ in the same directory.
Overwrites any existing content.typ -- re-export from the Org source
rather than hand-editing the generated file.

With a prefix argument, or non-nil ASYNC/SUBTREEP/VISIBLE-ONLY (see
`org-export-to-file'), export asynchronously, export only the current
subtree, or export only visible content, respectively."
  (interactive)
  (let ((outfile (expand-file-name "content.typ" default-directory)))
    (org-export-to-file 'touying outfile async subtreep visible-only)))

(provide 'ox-touying)
;;; ox-touying.el ends here
