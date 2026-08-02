;;; ox-rlr-slipshow.el --- Slipshow back-end for Org export -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Randy Ridenour

;; Author: Randy Ridenour <rlridenour@fastmail.com>
;; URL: https://github.com/rlridenour/ox-rlr-slipshow
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org "9.6"))
;; Keywords: outlines, hypermedia, wp

;; This file is not part of GNU Emacs.

;;; Commentary:

;; An Org export back-end producing source for Slipshow
;; (https://github.com/panglesd/slipshow), a presentation engine whose
;; input is an extension of CommonMark.
;;
;; Slipshow's dialect is close to Markdown but differs in ways that make a
;; plain Markdown exporter unsuitable:
;;
;;   * `>' introduces a *group*, not a block quote.  Real quotes need an
;;     explicit `{blockquote}' attribute.
;;   * Setext headings are not accepted; headings must be ATX (`#').
;;   * `{...}' is attribute syntax.  Literal braces in prose must be
;;     backslash-escaped or they are silently parsed as attributes.
;;   * `---' (and longer runs of dashes) separate sibling groups, so Org
;;     horizontal rules are emitted as `<hr>' to avoid colliding with the
;;     separators this back-end generates.
;;
;; Four complementary mechanisms express Slipshow attributes in Org, each
;; reaching a position the others cannot:
;;
;;   #+ATTR_SLIPSHOW: .definition title="Foo"   ; the next element
;;   #+SLIPSHOW: pause                          ; standalone, between elements
;;   :ATTR_SLIPSHOW: slip .dark                 ; a headline's own slip
;;   @@slipshow:{pause}@@                       ; inline, mid-sentence
;;
;; See README.org for a full description.

;;; Code:

(require 'ox-md)
(require 'ox-publish)
(require 'cl-lib)
(require 'subr-x)


;;; User configuration

(defgroup org-export-rlr-slipshow nil
  "Options for exporting Org files to Slipshow."
  :tag "Org Export Slipshow"
  :group 'org-export
  :prefix "org-rlr-slipshow-")

(defcustom org-rlr-slipshow-structure 'slip
  "How Org headlines map onto Slipshow's document structure.

`slip'   Headlines at `org-rlr-slipshow-slip-level' become `{slip}'
         groups.  This is Slipshow's native style: the presentation is
         one continuous surface that is scrolled and zoomed.

`slide'  Headlines at that level become fixed-height slides, separated
         by `---', with the matching frontmatter emitted automatically.

`flat'   No grouping at all.  Headlines become plain ATX headings and
         you control structure by hand with attributes."
  :type '(choice (const :tag "Slips (Slipshow native)" slip)
                 (const :tag "Slides (reveal.js-like)" slide)
                 (const :tag "Flat, no grouping" flat))
  :group 'org-export-rlr-slipshow)

(defcustom org-rlr-slipshow-slip-level 1
  "Headline level that becomes a slip or slide.
Levels above this one are emitted as ordinary headings inside the
enclosing slip, unless `org-rlr-slipshow-nest-subslips' is non-nil."
  :type 'integer
  :group 'org-export-rlr-slipshow)

(defcustom org-rlr-slipshow-nest-subslips nil
  "When non-nil, headlines below the slip level become nested sub-slips.
Nested slips are emitted as `>' groups carrying a `slip' attribute.
When nil (the default) deeper headlines are plain headings."
  :type 'boolean
  :group 'org-export-rlr-slipshow)

(defcustom org-rlr-slipshow-pause-lists nil
  "When non-nil, every plain list reveals its items one at a time.
This is off by default; enable it per list with

  #+ATTR_SLIPSHOW: pause-children

The first item is always visible, and each subsequent item appears on
its own step, matching the behaviour of Beamer's \\pause."
  :type 'boolean
  :group 'org-export-rlr-slipshow)

(defcustom org-rlr-slipshow-with-notes t
  "When non-nil, #+begin_notes blocks are exported as speaker notes.
Set to nil, or use

  #+OPTIONS: notes:nil

to drop them from the output entirely.  Slipshow hides notes from the
presentation either way, but they remain readable in the generated
source, so dropping them matters when sharing the file."
  :type 'boolean
  :group 'org-export-rlr-slipshow)

(defcustom org-rlr-slipshow-notes-attach t
  "When non-nil, attach a section's first notes block to its own slip.

Slipshow counts every action attribute as a step, so a standalone
`{speaker-note}' costs a keypress.  Referencing the note from the
enclosing slip instead makes it appear as the slip is entered, folded
into the step that enters it.  Set to nil to always emit notes inline,
each on its own step."
  :type 'boolean
  :group 'org-export-rlr-slipshow)

(defcustom org-rlr-slipshow-theme nil
  "Default Slipshow theme, or nil to let Slipshow decide.
Either a theme name such as \"vanier\" or a path to a CSS file."
  :type '(choice (const :tag "Slipshow default" nil) string)
  :group 'org-export-rlr-slipshow)

(defcustom org-rlr-slipshow-dimension nil
  "Default presentation dimension, or nil to let Slipshow decide.
Either \"WIDTHxHEIGHT\" such as \"1920x1080\", or a ratio such as
\"16:9\" or \"4:3\"."
  :type '(choice (const :tag "Slipshow default" nil) string)
  :group 'org-export-rlr-slipshow)

(defcustom org-rlr-slipshow-math-mode nil
  "Math renderer, or nil to let Slipshow decide.
Slipshow's own default is MathJax."
  :type '(choice (const :tag "Slipshow default (MathJax)" nil)
                 (const :tag "MathJax" "mathjax")
                 (const :tag "KaTeX" "katex"))
  :group 'org-export-rlr-slipshow)

(defcustom org-rlr-slipshow-math-link nil
  "Path or URL to the math library, or nil for the bundled one.
Useful when serving MathJax or KaTeX from somewhere of your own."
  :type '(choice (const :tag "Slipshow default" nil) string)
  :group 'org-export-rlr-slipshow)

(defcustom org-rlr-slipshow-language-alist
  '(("mermaid" . "=mermaid"))
  "Alist mapping an Org src-block language to Slipshow's info string.

Slipshow renders a fenced block as something other than source when its
info string begins with `=': `=mermaid' becomes a rendered diagram.  A
plain `mermaid' block is highlighted as code instead, and Slipshow
warns that it does not know the language.

Raw HTML has an Org spelling of its own --- #+begin_export html ---
so `html' is deliberately absent here: #+begin_src html means you want
to show the markup, not run it.

Set this to nil to emit every language verbatim, as a presentation
about Mermaid itself would want."
  :type '(alist :key-type (string :tag "Org language")
                :value-type (string :tag "Slipshow info string"))
  :group 'org-export-rlr-slipshow)

(defcustom org-rlr-slipshow-columns-style "display:flex; gap:2em"
  "Inline CSS applied to a #+begin_columns block, or nil for none.

Slipshow has no built-in column layout: the `columns' class in its
documentation is illustrative, and the reader is expected to supply
flexbox CSS.  This back-end supplies it so that #+begin_columns works
without a separate stylesheet.  Set to nil to emit a bare class and
style it yourself, and note that an explicit style= in #+ATTR_SLIPSHOW:
already takes precedence over this value."
  :type '(choice (const :tag "No inline styling" nil) string)
  :group 'org-export-rlr-slipshow)

(defcustom org-rlr-slipshow-column-style "flex:1"
  "Inline CSS applied to each direct child of a columns block, or nil.
Distributed to the children with Slipshow's `children:' mechanism, so
the columns share the available width evenly however many there are."
  :type '(choice (const :tag "No inline styling" nil) string)
  :group 'org-export-rlr-slipshow)

(defcustom org-rlr-slipshow-extension ".slp"
  "File extension used for exported Slipshow source files."
  :type 'string
  :group 'org-export-rlr-slipshow)

(defcustom org-rlr-slipshow-command "slipshow"
  "Name of, or path to, the Slipshow command line program."
  :type 'string
  :group 'org-export-rlr-slipshow)

(defcustom org-rlr-slipshow-serve-port 8080
  "Port used by `org-rlr-slipshow-serve'."
  :type 'integer
  :group 'org-export-rlr-slipshow)


;;; Constants

(defconst org-rlr-slipshow--slip-separator "-----"
  "Group separator emitted between slips.

Slipshow gives longer runs of dashes higher priority, so using five
dashes here leaves `----' and `---' free for groups the user writes
inside a slip.")

(defconst org-rlr-slipshow--slide-separator "---"
  "Group separator emitted between slides.")

(defconst org-rlr-slipshow--box-types
  '("block" "theorem" "definition" "example" "lemma" "corollary"
    "remark" "proof")
  "Special block names that Slipshow renders as boxes.
These are emitted as classes, so #+begin_theorem becomes `{.theorem}'.")

(defconst org-rlr-slipshow--element-types
  '("slip" "slide" "carousel" "blockquote")
  "Special block names that Slipshow renders as flag attributes.
These are emitted bare, so #+begin_slip becomes `{slip}'.")

(defconst org-rlr-slipshow--notes-types
  '("notes" "note" "speaker_note" "speaker_notes")
  "Special block names that become speaker notes.
`notes' is the spelling Org's Beamer and Reveal back-ends use.")

;; Let @@slipshow:...@@ and @@slp:...@@ reach this back-end, in addition
;; to the literal @@rlr-slipshow:...@@ that Org would match on its own.
(dolist (alias '("slipshow" "slp"))
  (add-to-list 'org-export-snippet-translation-alist
               (cons alias "rlr-slipshow")))


;;; Attribute helpers

(defun org-rlr-slipshow--clean (string)
  "Return STRING trimmed, or nil when it is blank."
  (when (stringp string)
    (let ((trimmed (string-trim string)))
      (unless (string-empty-p trimmed) trimmed))))

(defun org-rlr-slipshow--element-attrs (element)
  "Return the #+ATTR_SLIPSHOW: value attached to ELEMENT, or nil.
Consecutive keyword lines are merged into a single attribute string."
  (when element
    (org-rlr-slipshow--clean
     (mapconcat #'identity (org-element-property :attr_slipshow element) " "))))

(defun org-rlr-slipshow--headline-attrs (headline)
  "Return the :ATTR_SLIPSHOW: property of HEADLINE, or nil."
  (org-rlr-slipshow--clean (org-element-property :ATTR_SLIPSHOW headline)))

(defun org-rlr-slipshow--join-attrs (&rest parts)
  "Join PARTS into one attribute string, ignoring blanks.
Return nil when nothing is left."
  (org-rlr-slipshow--clean
   (mapconcat #'identity (delq nil (mapcar #'org-rlr-slipshow--clean parts)) " ")))

(defun org-rlr-slipshow--attr-line (attrs)
  "Return ATTRS as a standalone `{...}' line, or an empty string."
  (if attrs (format "{%s}\n" attrs) ""))

(defun org-rlr-slipshow--take-flag (attrs flag)
  "Look for FLAG in ATTRS.
Return a cons (FOUND . REMAINDER) where REMAINDER is ATTRS with FLAG
removed, or nil if nothing else is left."
  (if (and attrs (string-match-p (concat "\\_<" (regexp-quote flag) "\\_>") attrs))
      (cons t (org-rlr-slipshow--clean
               (replace-regexp-in-string
                (concat "\\_<" (regexp-quote flag) "\\_>") "" attrs)))
    (cons nil attrs)))

(defun org-rlr-slipshow--gt-group (contents)
  "Wrap CONTENTS in a Slipshow `>' group."
  (let ((body (string-trim-right (or contents ""))))
    (if (string-empty-p body) ""
      (concat (mapconcat (lambda (line)
                           (if (string-empty-p line) ">" (concat "> " line)))
                         (split-string body "\n")
                         "\n")
              "\n"))))


;;; Document-level option helpers

(defun org-rlr-slipshow--structure (info)
  "Return the structure mode symbol for this export, from INFO."
  (let ((value (plist-get info :slipshow-structure)))
    (cond
     ((symbolp value) (or value org-rlr-slipshow-structure))
     ((stringp value)
      (pcase (downcase (string-trim value))
        ("slip" 'slip)
        ("slide" 'slide)
        ((or "flat" "none") 'flat)
        (_ org-rlr-slipshow-structure)))
     (t org-rlr-slipshow-structure))))

(defun org-rlr-slipshow--slip-level (info)
  "Return the headline level that becomes a slip, from INFO."
  (let ((value (plist-get info :slipshow-slip-level)))
    (cond ((integerp value) value)
          ((and (stringp value) (string-match-p "\\`[0-9]+\\'" (string-trim value)))
           (string-to-number value))
          (t org-rlr-slipshow-slip-level))))

(defun org-rlr-slipshow--silent-element-p (element)
  "Return non-nil when ELEMENT contributes nothing to the output.
Leading #+OPTIONS: and #+SLIPSHOW_* lines form a section of their own, so
a section built only from these is not really a preamble."
  (pcase (org-element-type element)
    ('keyword (not (string= (org-element-property :key element) "SLIPSHOW")))
    ((or 'comment 'comment-block 'property-drawer) t)
    (_ nil)))

(defun org-rlr-slipshow--preamble-p (info)
  "Return non-nil when INFO's document has real content before its first headline."
  (let ((first (car (org-element-contents (plist-get info :parse-tree)))))
    (and first
         (eq (org-element-type first) 'section)
         (cl-notevery #'org-rlr-slipshow--silent-element-p
                      (org-element-contents first)))))

(defun org-rlr-slipshow--first-group-p (headline info)
  "Return non-nil when HEADLINE opens the very first group of the document.
INFO is the current export plist.  True only when no title block and no
preamble precede it, so that nothing has been emitted yet."
  (and
   ;; No title block was emitted before it.
   (not (and (plist-get info :with-title)
             (org-rlr-slipshow--clean
              (org-export-data (plist-get info :title) info))))
   ;; No content sits before the first headline.
   (not (org-rlr-slipshow--preamble-p info))
   ;; And it is itself the first headline at slip level.
   (eq headline
       (org-element-map (plist-get info :parse-tree) 'headline
         (lambda (candidate)
           (and (= (org-export-get-relative-level candidate info)
                   (org-rlr-slipshow--slip-level info))
                candidate))
         info t))))

;;; Speaker notes

(defun org-rlr-slipshow--notes-block-p (element)
  "Return non-nil when ELEMENT is a speaker-notes special block."
  (and (eq (org-element-type element) 'special-block)
       (member (downcase (or (org-element-property :type element) ""))
               org-rlr-slipshow--notes-types)))

(defun org-rlr-slipshow--note-id (block)
  "Return the identifier used to reference notes BLOCK.
Derived from the block's own buffer position, so that the headline and
the block agree on it without having to share any state."
  (format "org-slipshow-note-%d" (org-element-property :begin block)))

(defun org-rlr-slipshow--attributable-p (headline info)
  "Return non-nil when HEADLINE emits a group that can carry attributes.
INFO is the current export plist.

In slide mode the separator before the first group is suppressed, since
`children:slide' would turn it into an empty leading slide.  That
headline has nothing to hang an attribute on unless the author has
already forced a separator by giving it attributes of their own."
  (not (and (eq (org-rlr-slipshow--structure info) 'slide)
            (null (org-rlr-slipshow--headline-attrs headline))
            (org-rlr-slipshow--first-group-p headline info))))

(defun org-rlr-slipshow--note-host (block info)
  "Return the headline whose group should carry notes BLOCK, or nil.
INFO is the current export plist.  The host is the nearest ancestor
headline that becomes a group able to carry attributes; in flat mode
there is none, and the note is emitted inline instead."
  (let ((structure (org-rlr-slipshow--structure info))
        (slip-level (org-rlr-slipshow--slip-level info)))
    (when (memq structure '(slip slide))
      (let ((headline (org-element-lineage block '(headline)))
            (host nil))
        (while (and headline (not host))
          (let ((level (org-export-get-relative-level headline info)))
            (if (or (= level slip-level)
                    (and (> level slip-level)
                         (eq structure 'slip)
                         org-rlr-slipshow-nest-subslips))
                (setq host headline)
              (setq headline (org-element-lineage headline '(headline))))))
        (and host
             (org-rlr-slipshow--attributable-p host info)
             host)))))

(defun org-rlr-slipshow--attached-note (headline info)
  "Return the notes block HEADLINE's group should reference, or nil.
INFO is the current export plist.

Only one note can ride on a group, since a repeated `speaker-note'
attribute would collide, so this is the first block in the subtree that
names HEADLINE as its host.  A block carrying its own
#+ATTR_SLIPSHOW: line is left alone: the attributes are there to give
it a step of its own."
  (and org-rlr-slipshow-notes-attach
       (org-element-map (org-element-contents headline) 'special-block
         (lambda (block)
           (and (org-rlr-slipshow--notes-block-p block)
                (not (org-rlr-slipshow--element-attrs block))
                (eq (org-rlr-slipshow--note-host block info) headline)
                block))
         info t)))

(defun org-rlr-slipshow--note-attached-p (block info)
  "Return non-nil when notes BLOCK rides on its enclosing group.
INFO is the current export plist.  Decided through
`org-rlr-slipshow--attached-note' so that the block and the headline
cannot disagree."
  (let ((host (org-rlr-slipshow--note-host block info)))
    (and host (eq block (org-rlr-slipshow--attached-note host info)))))

(defun org-rlr-slipshow--note-reference (headline info)
  "Return the `speaker-note=ID' attribute for HEADLINE, or nil.
INFO is the current export plist."
  (when (plist-get info :slipshow-with-notes)
    (let ((note (org-rlr-slipshow--attached-note headline info)))
      (when note
        (format "speaker-note=%s" (org-rlr-slipshow--note-id note))))))

(defun org-rlr-slipshow--separator (info)
  "Return the group separator appropriate to INFO's structure mode."
  (if (eq (org-rlr-slipshow--structure info) 'slide)
      org-rlr-slipshow--slide-separator
    org-rlr-slipshow--slip-separator))


;;; Frontmatter

(defun org-rlr-slipshow--fm-pair (key value)
  "Return a frontmatter line for KEY and VALUE, or nil when VALUE is blank."
  (let ((value (org-rlr-slipshow--clean
                (if (listp value) (mapconcat #'identity value " ") value))))
    (when value (format "%s: %s" key value))))

(defun org-rlr-slipshow--frontmatter (info)
  "Return the `---' delimited frontmatter block for INFO, or an empty string."
  (let* ((slide (eq (org-rlr-slipshow--structure info) 'slide))
         (lines
          (delq nil
                (list
                 (org-rlr-slipshow--fm-pair
                  "attributes"
                  (or (plist-get info :slipshow-attributes)
                      (and slide "{ children:slide children:enter=~duration:0 }")))
                 (org-rlr-slipshow--fm-pair
                  "toplevel-attributes"
                  (or (plist-get info :slipshow-toplevel-attributes)
                      (and slide "{}")))
                 (org-rlr-slipshow--fm-pair
                  "theme" (or (plist-get info :slipshow-theme)
                              org-rlr-slipshow-theme))
                 (org-rlr-slipshow--fm-pair
                  "dimension" (or (plist-get info :slipshow-dimension)
                                  org-rlr-slipshow-dimension))
                 (org-rlr-slipshow--fm-pair
                  "math-mode" (or (plist-get info :slipshow-math-mode)
                                  org-rlr-slipshow-math-mode))
                 (org-rlr-slipshow--fm-pair
                  "math-link" (or (plist-get info :slipshow-math-link)
                                  org-rlr-slipshow-math-link))
                 (org-rlr-slipshow--fm-pair "css" (plist-get info :slipshow-css))
                 (org-rlr-slipshow--fm-pair "js" (plist-get info :slipshow-js))
                 (org-rlr-slipshow--fm-pair
                  "highlightjs-theme"
                  (plist-get info :slipshow-highlightjs-theme))
                 (org-rlr-slipshow--fm-pair
                  "external-ids" (plist-get info :slipshow-external-ids))))))
    (if lines
        (concat "---\n" (mapconcat #'identity lines "\n") "\n---\n\n")
      "")))

(defun org-rlr-slipshow--title-block (info)
  "Return an opening title slip for INFO, or an empty string."
  (let ((title (and (plist-get info :with-title)
                    (org-rlr-slipshow--clean
                     (org-export-data (plist-get info :title) info)))))
    (if (not title) ""
      (let* ((author (and (plist-get info :with-author)
                          (org-rlr-slipshow--clean
                           (org-export-data (plist-get info :author) info))))
             (date (and (plist-get info :with-date)
                        (org-rlr-slipshow--clean
                         (org-export-data (org-export-get-date info) info))))
             (body (concat "# " title "\n"
                           (when author (format "\n%s\n" author))
                           (when date (format "\n%s\n" date)))))
        (pcase (org-rlr-slipshow--structure info)
          ('slip (concat "{slip .title-slip}\n"
                         org-rlr-slipshow--slip-separator "\n" body "\n"))
          ('slide (concat body "\n"))
          (_ (concat body "\n")))))))


;;; Transcoders

(defun org-rlr-slipshow-template (contents info)
  "Return the complete Slipshow document for CONTENTS and INFO."
  (concat (org-rlr-slipshow--frontmatter info)
          (org-rlr-slipshow--title-block info)
          contents))

(defun org-rlr-slipshow-plain-text (text info)
  "Transcode TEXT, escaping Slipshow's attribute delimiters.
INFO is the current export plist.  An unescaped `{' in prose is parsed
as an attribute set and silently swallows the text inside it, so braces
are backslash-escaped here."
  (replace-regexp-in-string "[{}]" "\\\\\\&" (org-md-plain-text text info)))

(defun org-rlr-slipshow-headline (headline contents info)
  "Transcode HEADLINE with CONTENTS to Slipshow syntax.
INFO is the current export plist."
  (unless (org-element-property :footnote-section-p headline)
    (let* ((level (org-export-get-relative-level headline info))
           (structure (org-rlr-slipshow--structure info))
           (slip-level (org-rlr-slipshow--slip-level info))
           (user (org-rlr-slipshow--headline-attrs headline))
           (title (org-export-data (org-element-property :title headline) info))
           (tags (and (plist-get info :with-tags)
                      (org-export-get-tags headline info)))
           (heading (concat (make-string (max 1 level) ?#) " "
                            (org-rlr-slipshow--clean title)
                            (when tags
                              (format "     `%s`" (mapconcat #'identity tags ":")))))
           (body (or contents "")))
      (cond
       ;; A slip or slide: attributes ride on the separator, and apply to
       ;; the group that follows it.
       ((and (memq structure '(slip slide)) (= level slip-level))
        (let* ((note (org-rlr-slipshow--note-reference headline info))
               (attrs (if (eq structure 'slide)
                          (org-rlr-slipshow--join-attrs user note)
                        (org-rlr-slipshow--join-attrs "slip" user note)))
               ;; In slide mode `children:slide' makes every child of the
               ;; wrapper a slide, so a separator before the first one
               ;; would manufacture an empty leading slide.  Slip mode
               ;; needs its separator regardless: the `slip' attribute
               ;; rides on it, and an unattributed leading group renders
               ;; as nothing.
               (skip (and (eq structure 'slide)
                          (null attrs)
                          (org-rlr-slipshow--first-group-p headline info))))
          (concat (org-rlr-slipshow--attr-line attrs)
                  (unless skip (concat (org-rlr-slipshow--separator info) "\n"))
                  heading "\n\n" body)))
       ;; An optional nested sub-slip, wrapped in a `>' group so that it
       ;; stays inside its parent rather than becoming a sibling.
       ((and (eq structure 'slip)
             org-rlr-slipshow-nest-subslips
             (> level slip-level))
        (concat (org-rlr-slipshow--attr-line
                 (org-rlr-slipshow--join-attrs
                  "slip" user (org-rlr-slipshow--note-reference headline info)))
                (org-rlr-slipshow--gt-group (concat heading "\n\n" body))))
       (t
        (concat (org-rlr-slipshow--attr-line user) heading "\n\n" body))))))

(defconst org-rlr-slipshow--lone-image-re
  "\\`!\\[[^]]*\\](.*)\\'"
  "Match a paragraph body consisting of a single Markdown image.
`.' does not match a newline, so a paragraph with anything else in it
cannot match.")

(defun org-rlr-slipshow-paragraph (paragraph contents info)
  "Transcode PARAGRAPH with CONTENTS, attaching any attributes.
INFO is the current export plist.

Attributes normally go on a line of their own, which Slipshow reads as
belonging to the paragraph.  For a paragraph holding nothing but an
image that is the wrong target --- sizing the paragraph does not size
the picture --- so they are attached to the image inline instead,
where Slipshow puts them on the image's own container."
  (let* ((attrs (org-rlr-slipshow--element-attrs paragraph))
         (body (org-md-paragraph paragraph contents info))
         (image (string-trim-right body)))
    (if (and attrs (string-match-p org-rlr-slipshow--lone-image-re image))
        (format "%s{%s}\n" image attrs)
      (concat (org-rlr-slipshow--attr-line attrs) body))))

(defun org-rlr-slipshow--pause-list-p (plain-list info)
  "Return non-nil when items of PLAIN-LIST should be revealed one by one.
INFO is the current export plist."
  (or (car (org-rlr-slipshow--take-flag
            (org-rlr-slipshow--element-attrs plain-list) "pause-children"))
      (and (plist-get info :slipshow-pause-lists) t)))

(defun org-rlr-slipshow-plain-list (plain-list contents info)
  "Transcode PLAIN-LIST with CONTENTS.
INFO is the current export plist.  The `pause-children' flag is consumed
here; it is handled by `org-rlr-slipshow-item' and must not reach the
output, where Slipshow would warn about an unknown attribute."
  (concat (org-rlr-slipshow--attr-line
           (cdr (org-rlr-slipshow--take-flag
                 (org-rlr-slipshow--element-attrs plain-list) "pause-children")))
          (org-md-plain-list plain-list contents info)))

(defun org-rlr-slipshow--append-pause (contents)
  "Wrap the leading paragraph of CONTENTS in an inline `{pause}' group.

A bare trailing `{pause}' binds only to the inline element it touches,
which on a multi-word item would pause the last word alone.  Slipshow's
`[...]{attrs}' syntax attaches the attribute to the whole run instead.
Pausing the first paragraph is enough to hide the rest of the item, as a
pause also hides everything that follows it in the same pause block."
  (let* ((body (string-trim-right (or contents "")))
         (split (string-match "\n[ \t]*\n" body)))
    (if (string-empty-p body)
        contents
      (let ((head (if split (substring body 0 split) body))
            (tail (if split (substring body split) "")))
        (concat "[" (string-trim head) "]{pause}" tail "\n")))))

(defun org-rlr-slipshow-item (item contents info)
  "Transcode ITEM with CONTENTS, adding a pause when its list asks for one.
INFO is the current export plist.  The first item of a list is left
visible, so that each following item appears on its own step."
  (let ((list (org-element-lineage item '(plain-list)))
        (body (or contents "")))
    (when (and list
               (org-rlr-slipshow--pause-list-p list info)
               ;; Leave the first item visible, as Beamer's \pause does.
               (not (eq item (car (org-element-contents list)))))
      (setq body (org-rlr-slipshow--append-pause body)))
    (org-md-item item body info)))

(defun org-rlr-slipshow-quote-block (quote-block contents _info)
  "Transcode QUOTE-BLOCK with CONTENTS to a Slipshow blockquote.
A bare `>' group is not a quote in Slipshow, so the `blockquote'
attribute is required."
  (concat (org-rlr-slipshow--attr-line
           (org-rlr-slipshow--join-attrs
            "blockquote" (org-rlr-slipshow--element-attrs quote-block)))
          (org-rlr-slipshow--gt-group contents)))

(defun org-rlr-slipshow--assigns-p (attrs key)
  "Return non-nil when ATTRS already assigns KEY.
Matching is anchored so that `style' does not match `children:style'."
  (and attrs
       (string-match-p (concat "\\(?:\\`\\|[ \t]\\)" (regexp-quote key) "=")
                       attrs)))

(defun org-rlr-slipshow--block-attrs (type user)
  "Return the attribute string for a special block of TYPE with USER attributes."
  (let ((type (downcase type)))
    (cond
     ;; Columns need flexbox to lay out at all, so supply it unless the
     ;; user has said otherwise.  Any `columns-3'-style name works too.
     ((string-prefix-p "columns" type)
      (org-rlr-slipshow--join-attrs
       (concat "." type)
       (and org-rlr-slipshow-columns-style
            (not (org-rlr-slipshow--assigns-p user "style"))
            (format "style=\"%s\"" org-rlr-slipshow-columns-style))
       (and org-rlr-slipshow-column-style
            (not (org-rlr-slipshow--assigns-p user "children:style"))
            (format "children:style=\"%s\"" org-rlr-slipshow-column-style))
       user))
     ((member type org-rlr-slipshow--element-types)
      (org-rlr-slipshow--join-attrs type user))
     ((member type org-rlr-slipshow--box-types)
      (org-rlr-slipshow--join-attrs (concat "." type) user))
     ((string= type "group") (org-rlr-slipshow--join-attrs user))
     (t (org-rlr-slipshow--join-attrs (concat "." type) user)))))

(defun org-rlr-slipshow-notes-block (block contents info)
  "Transcode a speaker-notes BLOCK with CONTENTS.
INFO is the current export plist.

An attached note is emitted as a plain identified group; the
`speaker-note' attribute that names it rides on the enclosing slip, so
setting the note costs no step of its own.  Otherwise the attribute
goes here, and Slipshow gives the note a step.  Either way the note is
hidden from the presentation."
  (cond
   ((not (plist-get info :slipshow-with-notes)) "")
   ((org-rlr-slipshow--note-attached-p block info)
    (concat (org-rlr-slipshow--attr-line
             (concat "#" (org-rlr-slipshow--note-id block)))
            (org-rlr-slipshow--gt-group contents)))
   (t
    (concat (org-rlr-slipshow--attr-line
             (org-rlr-slipshow--join-attrs
              "speaker-note" (org-rlr-slipshow--element-attrs block)))
            (org-rlr-slipshow--gt-group contents)))))

(defun org-rlr-slipshow-special-block (special-block contents info)
  "Transcode SPECIAL-BLOCK with CONTENTS into an attributed Slipshow group.
INFO is the current export plist.

The block name becomes the attribute: #+begin_slip yields `{slip}',
#+begin_theorem yields `{.theorem}', and #+begin_group yields a bare
group.  Nesting groups inside a #+begin_columns block is how you get
side-by-side columns.  #+begin_notes is special-cased into a speaker
note."
  (if (org-rlr-slipshow--notes-block-p special-block)
      (org-rlr-slipshow-notes-block special-block contents info)
    (let ((attrs (org-rlr-slipshow--block-attrs
                  (org-element-property :type special-block)
                  (org-rlr-slipshow--element-attrs special-block))))
      (concat (org-rlr-slipshow--attr-line attrs)
              (org-rlr-slipshow--gt-group contents)))))

(defun org-rlr-slipshow-center-block (center-block contents _info)
  "Transcode CENTER-BLOCK with CONTENTS into a centred Slipshow group."
  (concat (org-rlr-slipshow--attr-line
           (org-rlr-slipshow--join-attrs
            "style=\"text-align:center\""
            (org-rlr-slipshow--element-attrs center-block)))
          (org-rlr-slipshow--gt-group contents)))

(defun org-rlr-slipshow--info-string (lang)
  "Return the Slipshow info string for src-block language LANG.
Languages Slipshow gives a meaning of their own are mapped through
`org-rlr-slipshow-language-alist'; anything else passes through."
  (or (and lang
           (cdr (assoc-string lang org-rlr-slipshow-language-alist t)))
      lang
      ""))

(defun org-rlr-slipshow-src-block (src-block _contents info)
  "Transcode SRC-BLOCK to a fenced code block.
INFO is the current export plist."
  (let ((lang (org-element-property :language src-block))
        (code (org-export-format-code-default src-block info)))
    (concat (org-rlr-slipshow--attr-line
             (org-rlr-slipshow--element-attrs src-block))
            "```" (org-rlr-slipshow--info-string lang) "\n"
            code
            (unless (string-suffix-p "\n" code) "\n")
            "```\n")))

(defun org-rlr-slipshow-example-block (example-block _contents info)
  "Transcode EXAMPLE-BLOCK to a fenced code block.
INFO is the current export plist."
  (let ((code (org-export-format-code-default example-block info)))
    (concat (org-rlr-slipshow--attr-line
             (org-rlr-slipshow--element-attrs example-block))
            "```text\n"
            code
            (unless (string-suffix-p "\n" code) "\n")
            "```\n")))

(defun org-rlr-slipshow-horizontal-rule (_rule _contents _info)
  "Transcode a horizontal rule to an HTML `<hr>'.
A literal run of dashes would be read as a group separator, so the HTML
tag, which Slipshow also accepts, is used instead."
  "<hr>")

(defun org-rlr-slipshow-latex-fragment (fragment _contents _info)
  "Transcode a LaTeX FRAGMENT to Slipshow's dollar-delimited math."
  (let ((value (org-element-property :value fragment)))
    (cond
     ((and (string-prefix-p "\\(" value) (string-suffix-p "\\)" value))
      (concat "$" (string-trim (substring value 2 -2)) "$"))
     ((and (string-prefix-p "\\[" value) (string-suffix-p "\\]" value))
      (concat "$$" (string-trim (substring value 2 -2)) "$$"))
     (t value))))

(defun org-rlr-slipshow-latex-environment (environment _contents info)
  "Transcode a LaTeX ENVIRONMENT to a Slipshow math block.
INFO is the current export plist."
  (when (plist-get info :with-latex)
    (let ((value (string-trim
                  (org-remove-indentation
                   (org-element-property :value environment)))))
      (concat (org-rlr-slipshow--attr-line
               (org-rlr-slipshow--element-attrs environment))
              "$$\n" value "\n$$\n"))))

(defun org-rlr-slipshow--include-line (value)
  "Return the `{include ...}' element for a #+SLIPSHOW_INCLUDE: VALUE.
VALUE is a path, optionally double-quoted so that it may contain
spaces, followed by any further attributes.  The path is passed through
untouched: this back-end cannot know where you export the other parts
to, and Slipshow names the offending path when it cannot read one."
  (let ((value (org-rlr-slipshow--clean value)))
    (when value
      (let ((quoted (string-match "\\`\"\\([^\"]*\\)\"[ \t]*" value)))
        (unless quoted (string-match "\\`\\([^ \t]+\\)[ \t]*" value))
        (let ((path (match-string 1 value))
              (rest (substring value (match-end 0))))
          (format "{%s}"
                  (org-rlr-slipshow--join-attrs
                   "include" (format "src=\"%s\"" path) rest)))))))

(defun org-rlr-slipshow-keyword (keyword contents info)
  "Transcode KEYWORD, handling this back-end's standalone forms.
CONTENTS is nil.  INFO is the current export plist."
  (pcase (org-element-property :key keyword)
    ("SLIPSHOW"
     (let ((value (org-rlr-slipshow--clean
                   (org-element-property :value keyword))))
       (if value (format "{%s}" value) "")))
    ("SLIPSHOW_INCLUDE"
     (or (org-rlr-slipshow--include-line
          (org-element-property :value keyword))
         ""))
    (_ (org-md-keyword keyword contents info))))

(defun org-rlr-slipshow-export-snippet (export-snippet _contents _info)
  "Transcode EXPORT-SNIPPET, passing Slipshow snippets through verbatim.

The inherited HTML transcoder only fires for the `html' back-end
exactly, so @@slipshow:...@@ would otherwise be dropped."
  (when (memq (org-export-snippet-backend export-snippet)
              '(rlr-slipshow slipshow slp))
    (org-element-property :value export-snippet)))

(defun org-rlr-slipshow-export-block (export-block contents info)
  "Transcode EXPORT-BLOCK, passing Slipshow blocks through verbatim.
CONTENTS is nil.  INFO is the current export plist."
  (let ((type (org-element-property :type export-block)))
    (if (member type '("SLIPSHOW" "SLP"))
        (org-remove-indentation (org-element-property :value export-block))
      (org-md-export-block export-block contents info))))


;;; Tables

(defun org-rlr-slipshow--table-rule (row info)
  "Return the GFM delimiter row matching the cells of ROW.
INFO is the current export plist."
  (concat "|"
          (mapconcat
           (lambda (cell)
             (pcase (org-export-table-cell-alignment cell info)
               ('left " :--- |")
               ('right " ---: |")
               ('center " :---: |")
               (_ " --- |")))
           (org-element-contents row)
           "")))

(defun org-rlr-slipshow-table-cell (_cell contents _info)
  "Transcode a table cell with CONTENTS to a GFM cell."
  (concat " " (or contents "") " |"))

(defun org-rlr-slipshow-table-row (row contents info)
  "Transcode table ROW with CONTENTS to a GFM row.
INFO is the current export plist."
  (when (eq 'standard (org-element-property :type row))
    (concat "|" contents
            (when (org-export-table-row-ends-header-p row info)
              (concat "\n" (org-rlr-slipshow--table-rule row info))))))

(defun org-rlr-slipshow-table (table contents info)
  "Transcode TABLE with CONTENTS to a GFM table.
INFO is the current export plist.  GFM requires a delimiter row, so one
is synthesised for tables that have no header."
  (let ((body (string-trim (or contents ""))))
    (unless (org-export-table-has-header-p table info)
      (let ((first-row (org-element-map table 'table-row
                         (lambda (row)
                           (and (eq 'standard (org-element-property :type row))
                                row))
                         info t)))
        (when first-row
          (let ((rule (org-rlr-slipshow--table-rule first-row info))
                (break (string-search "\n" body)))
            (setq body (if break
                           (concat (substring body 0 break) "\n" rule
                                   (substring body break))
                         (concat body "\n" rule)))))))
    (concat (org-rlr-slipshow--attr-line
             (org-rlr-slipshow--element-attrs table))
            body "\n")))


;;; Back-end definition

(org-export-define-derived-backend 'rlr-slipshow 'md
  :menu-entry
  '(?y "Export to Slipshow"
       ((?Y "As Slipshow buffer" org-rlr-slipshow-export-as-slipshow)
        (?y "As Slipshow file" org-rlr-slipshow-export-to-slipshow)
        (?h "As HTML file (compile)" org-rlr-slipshow-export-to-html)
        (?o "As HTML file and open" org-rlr-slipshow-export-to-html-and-open)
        (?s "Serve with live reload" org-rlr-slipshow-serve)
        (?w "Serve and re-export on save" org-rlr-slipshow-watch)
        ;; Not exports, but this is where the server was started from.
        (?k "Stop the server" (lambda (_a _s _v _b) (org-rlr-slipshow-stop)))
        (?K "Stop watching and serving"
            (lambda (_a _s _v _b) (org-rlr-slipshow-unwatch)))))
  :options-alist
  ;; A Markdown table of contents lands before the first slip separator,
  ;; where it renders as stray content in the top-level slip, so it is off
  ;; by default here.  Re-enable per file with `#+OPTIONS: toc:t'.
  '((:with-toc nil "toc" nil)
    (:slipshow-structure "SLIPSHOW_STRUCTURE" nil nil t)
    (:slipshow-slip-level "SLIPSHOW_SLIP_LEVEL" nil nil t)
    (:slipshow-theme "SLIPSHOW_THEME" nil nil t)
    (:slipshow-dimension "SLIPSHOW_DIMENSION" nil nil t)
    (:slipshow-css "SLIPSHOW_CSS" nil nil space)
    (:slipshow-js "SLIPSHOW_JS" nil nil space)
    (:slipshow-highlightjs-theme "SLIPSHOW_HIGHLIGHTJS_THEME" nil nil t)
    (:slipshow-math-mode "SLIPSHOW_MATH_MODE" nil nil t)
    (:slipshow-math-link "SLIPSHOW_MATH_LINK" nil nil t)
    (:slipshow-attributes "SLIPSHOW_ATTRIBUTES" nil nil t)
    (:slipshow-toplevel-attributes "SLIPSHOW_TOPLEVEL_ATTRIBUTES" nil nil t)
    (:slipshow-external-ids "SLIPSHOW_EXTERNAL_IDS" nil nil space)
    (:slipshow-pause-lists nil "pause-lists" org-rlr-slipshow-pause-lists)
    (:slipshow-with-notes nil "notes" org-rlr-slipshow-with-notes))
  :translate-alist
  '((template . org-rlr-slipshow-template)
    (headline . org-rlr-slipshow-headline)
    (plain-text . org-rlr-slipshow-plain-text)
    (paragraph . org-rlr-slipshow-paragraph)
    (plain-list . org-rlr-slipshow-plain-list)
    (item . org-rlr-slipshow-item)
    (quote-block . org-rlr-slipshow-quote-block)
    (special-block . org-rlr-slipshow-special-block)
    (center-block . org-rlr-slipshow-center-block)
    (src-block . org-rlr-slipshow-src-block)
    (example-block . org-rlr-slipshow-example-block)
    (fixed-width . org-rlr-slipshow-example-block)
    (horizontal-rule . org-rlr-slipshow-horizontal-rule)
    (latex-fragment . org-rlr-slipshow-latex-fragment)
    (latex-environment . org-rlr-slipshow-latex-environment)
    (keyword . org-rlr-slipshow-keyword)
    (export-block . org-rlr-slipshow-export-block)
    (export-snippet . org-rlr-slipshow-export-snippet)
    (table . org-rlr-slipshow-table)
    (table-row . org-rlr-slipshow-table-row)
    (table-cell . org-rlr-slipshow-table-cell)))


;;; End-user commands

;;;###autoload
(defun org-rlr-slipshow-export-as-slipshow
    (&optional async subtreep visible-only body-only)
  "Export current buffer to a Slipshow buffer.
ASYNC, SUBTREEP, VISIBLE-ONLY and BODY-ONLY behave as in other Org
exporters.  BODY-ONLY omits the frontmatter and title slip, which is
what you want for a file destined to be pulled in with `{include}'."
  (interactive)
  (org-export-to-buffer 'rlr-slipshow "*Org Slipshow Export*"
    async subtreep visible-only body-only nil
    (lambda () (when (fboundp 'markdown-mode) (markdown-mode)))))

;;;###autoload
(defun org-rlr-slipshow-export-to-slipshow
    (&optional async subtreep visible-only body-only)
  "Export current buffer to a Slipshow source file.
ASYNC, SUBTREEP, VISIBLE-ONLY and BODY-ONLY behave as in other Org
exporters.  Return the name of the file written."
  (interactive)
  (let ((file (org-export-output-file-name
               org-rlr-slipshow-extension subtreep)))
    (org-export-to-file 'rlr-slipshow file async subtreep visible-only body-only)))

(defconst org-rlr-slipshow--compile-buffer "*Slipshow*"
  "Buffer used for one-off `slipshow compile' runs.")

(defconst org-rlr-slipshow--serve-buffer "*Slipshow Serve*"
  "Buffer used for the long-running `slipshow serve' process.
Kept apart from compile runs so that compiling does not disturb a
running server, and so that the server can be found again and stopped.")

(defun org-rlr-slipshow--run (buffer-name command source &rest args)
  "Run Slipshow COMMAND on SOURCE with ARGS in BUFFER-NAME.
Return the process buffer."
  (unless (executable-find org-rlr-slipshow-command)
    (user-error "Cannot find the `%s' program; see `org-rlr-slipshow-command'"
                org-rlr-slipshow-command))
  (let ((buffer (get-buffer-create buffer-name))
        (default-directory (file-name-directory (expand-file-name source))))
    (with-current-buffer buffer (erase-buffer))
    (apply #'start-process (string-trim buffer-name "\\*" "\\*") buffer
           org-rlr-slipshow-command command
           (file-name-nondirectory source) args)
    buffer))

(defun org-rlr-slipshow--server ()
  "Return the live `slipshow serve' process, or nil."
  (let* ((buffer (get-buffer org-rlr-slipshow--serve-buffer))
         (process (and buffer (get-buffer-process buffer))))
    (and process (process-live-p process) process)))

;;;###autoload
(defun org-rlr-slipshow-stop ()
  "Stop the Slipshow server started by `org-rlr-slipshow-serve'."
  (interactive)
  (let ((process (org-rlr-slipshow--server)))
    (if (not process)
        (message "No Slipshow server is running")
      ;; The default sentinel would report the signal as an error.
      (set-process-sentinel process #'ignore)
      ;; SIGINT first, so the server releases the port on its own terms.
      (interrupt-process process)
      (let ((deadline (+ (float-time) 2)))
        (while (and (process-live-p process) (< (float-time) deadline))
          (accept-process-output process 0.05)))
      (when (process-live-p process)
        (delete-process process))
      (message "Stopped the Slipshow server on port %d"
               org-rlr-slipshow-serve-port))))

;;;###autoload
(defun org-rlr-slipshow-export-to-html
    (&optional async subtreep visible-only body-only)
  "Export current buffer to Slipshow source, then compile it to HTML.
ASYNC, SUBTREEP, VISIBLE-ONLY and BODY-ONLY behave as in other Org
exporters.  Return the name of the HTML file that will be produced."
  (interactive)
  (let* ((source (org-rlr-slipshow-export-to-slipshow
                  async subtreep visible-only body-only))
         (html (concat (file-name-sans-extension source) ".html")))
    (org-rlr-slipshow--run org-rlr-slipshow--compile-buffer
                           "compile" source "-o" (file-name-nondirectory html))
    (message "Compiling %s with Slipshow..." (file-name-nondirectory source))
    html))

;;;###autoload
(defun org-rlr-slipshow-export-to-html-and-open
    (&optional async subtreep visible-only body-only)
  "Export to HTML with Slipshow and open the result in a browser.
ASYNC, SUBTREEP, VISIBLE-ONLY and BODY-ONLY behave as in other Org
exporters."
  (interactive)
  (let ((html (org-rlr-slipshow-export-to-html
               async subtreep visible-only body-only))
        (process (get-buffer-process
                  (get-buffer org-rlr-slipshow--compile-buffer))))
    (if (not process)
        (browse-url-of-file html)
      (set-process-sentinel
       process
       (lambda (_process event)
         (if (string-match-p "finished" event)
             (browse-url-of-file html)
           (pop-to-buffer org-rlr-slipshow--compile-buffer)))))
    html))

;;;###autoload
(defun org-rlr-slipshow-serve
    (&optional async subtreep visible-only body-only)
  "Export the current buffer and serve it with live reload.
ASYNC, SUBTREEP, VISIBLE-ONLY and BODY-ONLY behave as in other Org
exporters.

Slipshow watches the exported source file, not the Org buffer, so
re-export to refresh the presentation.

Any server already running is stopped first: a second one would inherit
neither the port nor the buffer, and would be left running with no way
to reach it.  Stop the server with `org-rlr-slipshow-stop'."
  (interactive)
  (let ((source (org-rlr-slipshow-export-to-slipshow
                 async subtreep visible-only body-only)))
    (when (org-rlr-slipshow--server)
      (org-rlr-slipshow-stop))
    (org-rlr-slipshow--run org-rlr-slipshow--serve-buffer "serve" source
                           "--port" (number-to-string org-rlr-slipshow-serve-port))
    (message "Serving %s on http://localhost:%d"
             (file-name-nondirectory source) org-rlr-slipshow-serve-port)
    source))


;;; Watching a buffer

(defvar org-rlr-slipshow--watched-buffer nil
  "Buffer currently re-exporting on save, or nil.
Only one buffer watches at a time, because only one server runs.")

(defvar-local org-rlr-slipshow--watch-args nil
  "Export arguments reused for each re-export while watching.")

(defun org-rlr-slipshow--unwatch-buffer ()
  "Detach the watch hooks, leaving any running server alone."
  (when (buffer-live-p org-rlr-slipshow--watched-buffer)
    (with-current-buffer org-rlr-slipshow--watched-buffer
      (remove-hook 'after-save-hook #'org-rlr-slipshow--re-export t)
      (remove-hook 'kill-buffer-hook #'org-rlr-slipshow-unwatch t)
      (kill-local-variable 'org-rlr-slipshow--watch-args)))
  (setq org-rlr-slipshow--watched-buffer nil))

(defun org-rlr-slipshow--re-export ()
  "Re-export the watched buffer.  Runs from `after-save-hook'.

Slipshow serves and watches the exported file, so rewriting it is all
that is needed to refresh the presentation."
  (if (not (org-rlr-slipshow--server))
      ;; Nothing is left to refresh, and silently re-exporting for a
      ;; server that has gone away only looks like it is still working.
      (let ((name (buffer-name)))
        (org-rlr-slipshow--unwatch-buffer)
        (message "Slipshow server is gone; stopped watching %s" name))
    (condition-case err
        (progn
          (let ((inhibit-message t))
            (apply #'org-rlr-slipshow-export-to-slipshow
                   org-rlr-slipshow--watch-args))
          (message "Slipshow: re-exported %s" (buffer-name)))
      ;; Signalling here would abort the rest of `after-save-hook', so
      ;; report the failure and leave the other hooks to run.
      (error
       (message "Slipshow re-export of %s failed: %s"
                (buffer-name) (error-message-string err))))))

;;;###autoload
(defun org-rlr-slipshow-watch
    (&optional async subtreep visible-only body-only)
  "Export the current buffer, serve it, and re-export on every save.
ASYNC, SUBTREEP, VISIBLE-ONLY and BODY-ONLY behave as in other Org
exporters.

Slipshow's server already watches the exported file and reloads the
browser when it changes, so this only adds the missing half: rewriting
that file whenever the Org buffer is saved.

Any buffer already being watched is released first, and
`org-rlr-slipshow-serve' stops any running server, so calling this
again -- here or in another buffer -- replaces the previous watcher
rather than accumulating one.  Stop with `org-rlr-slipshow-unwatch'."
  (interactive)
  (org-rlr-slipshow--unwatch-buffer)
  (let ((source (org-rlr-slipshow-serve async subtreep visible-only body-only)))
    ;; Re-exports are always synchronous: an async export spawns a fresh
    ;; Emacs, which is far too much to do on every save.
    (setq org-rlr-slipshow--watch-args
          (list nil subtreep visible-only body-only))
    (setq org-rlr-slipshow--watched-buffer (current-buffer))
    (add-hook 'after-save-hook #'org-rlr-slipshow--re-export nil t)
    (add-hook 'kill-buffer-hook #'org-rlr-slipshow-unwatch nil t)
    (message "Watching %s: saving re-exports %s, served on http://localhost:%d"
             (buffer-name) (file-name-nondirectory source)
             org-rlr-slipshow-serve-port)
    source))

;;;###autoload
(defun org-rlr-slipshow-unwatch ()
  "Stop re-exporting on save, and stop the Slipshow server."
  (interactive)
  (let ((name (and (buffer-live-p org-rlr-slipshow--watched-buffer)
                   (buffer-name org-rlr-slipshow--watched-buffer))))
    (org-rlr-slipshow--unwatch-buffer)
    (when (org-rlr-slipshow--server)
      (org-rlr-slipshow-stop))
    (message (if name
                 (format "Stopped watching %s" name)
               "No buffer is being watched"))))

;;;###autoload
(defun org-rlr-slipshow-publish-to-slipshow (plist filename pub-dir)
  "Publish an Org FILENAME to Slipshow source.
PLIST is the property list for the given project.  PUB-DIR is the
publishing directory.  Return the output file name."
  (org-publish-org-to 'rlr-slipshow filename
                      org-rlr-slipshow-extension plist pub-dir))

(provide 'ox-rlr-slipshow)

;;; ox-rlr-slipshow.el ends here
