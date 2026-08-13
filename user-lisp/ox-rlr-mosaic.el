;;; ox-rlr-mosaic.el --- Mosaic (Typst) presentation backend for Org export -*- lexical-binding: t; -*-

;; Author: Randy Ridenour
;; Keywords: org, typst, mosaic, presentation, slides
;; Package-Requires: ((emacs "27.1") (org "9.6"))
;; Homepage: https://github.com/rlridenour/ox-rlr-mosaic

;;; Commentary:

;; This library implements an Org export back-end that produces Typst
;; presentations built with the Mosaic package
;; (https://github.com/vincentarelbundock/mosaic).
;;
;; It derives from `rlr-typst' (ox-rlr-typst.el), so every inline and
;; block construct that back-end already knows -- emphasis, lists,
;; tables, links, footnotes, citations, LaTeX math via mitex, source
;; blocks -- is inherited unchanged.  What this back-end adds is slide
;; semantics: a Mosaic preamble, the heading-to-slide mapping, explicit
;; `#m.slide(...)' calls driven by headline properties, multi-cell slide
;; bodies, incremental reveals, and speaker notes.
;;
;; Mosaic's own authoring model is deliberately thin: after
;; `#show: m.setup', a level-one Typst heading (`=') opens a section
;; slide and a level-two heading (`==') opens a content slide.  This
;; exporter preserves that model rather than hiding it, so an Org
;; document maps onto a deck with no ceremony:
;;
;;     #+TITLE: A short talk
;;     #+AUTHOR: Ada Lovelace
;;
;;     * Methods            -> section slide
;;     ** Data              -> content slide
;;     One slide.
;;     ** Model             -> content slide
;;     Another slide.
;;
;; `org-rlr-mosaic-slide-level' decides which Org level becomes a
;; content slide (default 2, matching Mosaic).  Set it to 1 for a flat
;; deck in which every top-level heading is a slide and there are no
;; section dividers.  Headings deeper than the slide level stay ordinary
;; Typst headings inside the slide body.
;;
;; Deck-wide configuration comes from `#+MOSAIC_*' keywords, which are
;; passed to `m.setup' (see `org-rlr-mosaic--setup').  Per-slide
;; configuration comes from `:MOSAIC_*:' headline properties, which
;; promote that heading to an explicit `#m.slide(...)' call carrying the
;; corresponding Mosaic layout fields (see
;; `org-rlr-mosaic-slide-fields').  A slide body is split into several
;; Mosaic cells with `#+MOSAIC: split', which is also enough on its own
;; to turn a slide into a multi-column one.
;;
;; Values written in those keywords and properties are passed through to
;; Typst essentially verbatim, so the full Mosaic API stays reachable; a
;; small amount of coercion (see `org-rlr-mosaic--field-value') lets the
;; common cases be written as plain words rather than Typst literals.
;;
;; Usage: `M-x org-rlr-mosaic-export-to-typst' writes a sibling ".typ"
;; file; `M-x org-rlr-mosaic-export-to-pdf' writes it and compiles the
;; deck with the `typst' binary.

;;; Code:

(require 'cl-lib)
(require 'ox)
(require 'ox-publish)
(require 'ox-rlr-typst)
(require 'subr-x)


;;; User-Configurable Variables

(defgroup org-export-rlr-mosaic nil
  "Options for the Mosaic (Typst) presentation export back-end."
  :tag "Org Mosaic"
  :group 'org-export)

(defcustom org-rlr-mosaic-package "@preview/mosaic:0.0.1"
  "Typst package specification imported at the top of the deck.

Defaults to the version published on Typst Universe, which Typst
fetches automatically on first compile.  Set this to
\"@local/mosaic:0.0.2\" to build against a working tree installed
with the Mosaic repository's `make install'."
  :group 'org-export-rlr-mosaic
  :type 'string)

(defcustom org-rlr-mosaic-theme nil
  "Name of the Mosaic theme facade to import, or nil for the default.

Bundled facades are \"default\", \"editorial\", \"metropolis\",
\"manifesto\", and \"mono\".  When non-nil, the package is imported as
`mosaic' and the facade is imported as `m', which is the spelling
Mosaic documents; the rest of the deck is unaffected because every
facade exports the same API."
  :group 'org-export-rlr-mosaic
  :type '(choice (const :tag "Default facade" nil) string))

(defcustom org-rlr-mosaic-slide-level 2
  "Org headline level that becomes a Mosaic content slide.

With the default of 2, the mapping matches Mosaic's own: level-one
headings become section slides (`=') and level-two headings become
content slides (`==').  With 1, every top-level heading becomes a
content slide and the deck has no section dividers.

Headings deeper than this level are emitted as ordinary Typst
headings inside the slide body."
  :group 'org-export-rlr-mosaic
  :type '(choice (const :tag "Sections and slides (= / ==)" 2)
                 (const :tag "Flat deck, every heading a slide" 1)))

(defcustom org-rlr-mosaic-title-slide t
  "Whether to emit a title slide after `m.setup'.

A non-nil value emits `#m.slide(layout: \"title\")' when the document
has a title.  A string is used as the title layout's variant, e.g.
\"kicker\" for `#m.slide(layout: \"title\", variant: \"kicker\")'.
Stock variants are \"ruled\", \"centered\", \"bordered\", \"kicker\",
\"panel\", and \"academic\"."
  :group 'org-export-rlr-mosaic
  :type '(choice (const :tag "No title slide" nil)
                 (const :tag "Configured title layout" t)
                 (string :tag "Title layout variant")))

(defcustom org-rlr-mosaic-paper "16-9"
  "Slide aspect ratio, either \"16-9\" or \"4-3\"."
  :group 'org-export-rlr-mosaic
  :type '(choice (const "16-9") (const "4-3")))

(defcustom org-rlr-mosaic-notes-paper "us-letter"
  "Paper size for the printed `speaker' and `notes' outputs.

Mosaic fixes those companion pages at A4, which it has no argument to
change, so this is emitted as a `#set page(paper: ...)' rule after
`m.setup'.  Any Typst paper name works.

Set this to nil to leave Mosaic's A4 alone.

The rule is emitted only for the `speaker' and `notes' outputs.  The
`slides' and `split' outputs derive their page from the slide's own
dimensions rather than from a named paper, and a `paper:' rule would
replace those dimensions and break the deck."
  :group 'org-export-rlr-mosaic
  :type '(choice (const :tag "Leave Mosaic's default (A4)" nil)
                 (const :tag "US Letter" "us-letter")
                 (string :tag "Typst paper name")))

(defcustom org-rlr-mosaic-quote-component nil
  "Whether `#+begin_quote' becomes Mosaic's quote component.

When nil, a quote block becomes a native Typst `#quote(block: true)',
which the theme styles as ordinary block quotation.  When non-nil it
becomes `#m.components.quote(...)' instead, Mosaic's panelled
attribution treatment.

A quote block carrying an `#+ATTR_MOSAIC:' line always uses the
component regardless of this setting, since its arguments --
`:attribution' and `:source' -- have nowhere else to go."
  :group 'org-export-rlr-mosaic
  :type 'boolean)

(defcustom org-rlr-mosaic-typst-command "typst"
  "Name of, or path to, the Typst executable used to compile a deck."
  :group 'org-export-rlr-mosaic
  :type 'string)

(defcustom org-rlr-mosaic-typst-compile-options '("--root" ".")
  "Extra arguments passed to `typst compile'.

The default roots the compile at the working directory, which is what
decks referencing images by relative path need."
  :group 'org-export-rlr-mosaic
  :type '(repeat string))

(defconst org-rlr-mosaic-slide-fields
  '("layout" "variant" "columns" "tracks" "gutter" "image" "caption"
    "cells" "background" "foreground" "numbered" "invert" "accent"
    "inset" "fit" "scrim" "number" "title" "subtitle" "authors" "date"
    "align" "stroke" "label")
  "Mosaic slide fields settable from a headline `:MOSAIC_FIELD:' property.

Each name FOO here is read from the `:MOSAIC_FOO:' property of a
headline and emitted as the `foo:' argument of that slide's
`#m.slide(...)' call.  Setting any of them promotes the heading from an
automatic heading slide to an explicit slide.

Mosaic validates field names against the selected layout, so a name
this list allows but the layout does not have is a Typst compile
error rather than a silent no-op.  Anything not listed here can still
be passed through `:MOSAIC_ARGS:'.")

(defconst org-rlr-mosaic--string-fields
  '("layout" "variant" "fit" "position" "role" "count" "output")
  "Slide/component fields whose bare-word values are quoted as Typst strings.")

(defconst org-rlr-mosaic--content-fields
  '("caption" "title" "subtitle" "number" "footer" "header" "body"
    "attribution" "source")
  "Slide/component fields whose values are wrapped in a Typst content block.")

(defconst org-rlr-mosaic--path-fields '("image")
  "Slide/component fields whose bare values are wrapped in Typst `path(...)'.

Mosaic's documentation is emphatic about this: an image path given to a
layout or component argument crosses the package boundary, so a bare
string is searched for inside the installed Mosaic package and fails.")

(defconst org-rlr-mosaic--split-marker "\x1mosaic-split\x1"
  "Internal sentinel marking a `#+MOSAIC: split' cell boundary.")

(defconst org-rlr-mosaic--body-marker "\x1mosaic-body\x1"
  "Internal sentinel marking the end of a headline's own section content.

Everything a headline transcoder receives after this marker was
produced by child headlines, which for a section slide must be emitted
after the slide rather than inside it.")


;;; Define Backend

(org-export-define-derived-backend 'rlr-mosaic 'rlr-typst
  :menu-entry
  '(?m "Export to Mosaic slides"
       ((?M "As Typst buffer" org-rlr-mosaic-export-as-typst)
        (?m "To .typ file" org-rlr-mosaic-export-to-typst)
        (?p "To .typ and compile PDF" org-rlr-mosaic-export-to-pdf)
        (?o "To PDF and open"
            (lambda (a s v b)
              (if a (org-rlr-mosaic-export-to-pdf t s v)
                (org-open-file (org-rlr-mosaic-export-to-pdf nil s v)))))))
  :translate-alist
  '((headline . org-rlr-mosaic-headline)
    (inner-template . org-rlr-mosaic-inner-template)
    (keyword . org-rlr-mosaic-keyword)
    (quote-block . org-rlr-mosaic-quote-block)
    (section . org-rlr-mosaic-section)
    (special-block . org-rlr-mosaic-special-block)
    (template . org-rlr-mosaic-template))
  :options-alist
  ;; A deck's table of contents is a slide of its own, so it is an
  ;; explicit design choice rather than something to emit by default as
  ;; a prose document would.  `#+OPTIONS: toc:t' asks for one.
  '((:with-toc nil "toc" nil)
    (:subtitle "SUBTITLE" nil nil parse)
    (:mosaic-package "MOSAIC_PACKAGE" nil org-rlr-mosaic-package t)
    (:mosaic-theme "MOSAIC_THEME" nil org-rlr-mosaic-theme t)
    (:mosaic-slide-level "MOSAIC_SLIDE_LEVEL" nil org-rlr-mosaic-slide-level t)
    (:mosaic-title-slide "MOSAIC_TITLE_SLIDE" nil org-rlr-mosaic-title-slide t)
    (:mosaic-paper "MOSAIC_PAPER" nil org-rlr-mosaic-paper t)
    (:mosaic-quote-component "MOSAIC_QUOTE_COMPONENT" nil
                             org-rlr-mosaic-quote-component t)
    (:mosaic-authors "MOSAIC_AUTHORS" nil nil t)
    (:mosaic-colors "MOSAIC_COLORS" nil nil t)
    (:mosaic-cells "MOSAIC_CELLS" nil nil t)
    (:mosaic-layouts "MOSAIC_LAYOUTS" nil nil t)
    (:mosaic-background "MOSAIC_BACKGROUND" nil nil t)
    (:mosaic-foreground "MOSAIC_FOREGROUND" nil nil t)
    (:mosaic-spacing "MOSAIC_SPACING" nil nil t)
    (:mosaic-output "MOSAIC_OUTPUT" nil nil t)
    (:mosaic-notes "MOSAIC_NOTES" nil nil t)
    (:mosaic-notes-paper "MOSAIC_NOTES_PAPER" nil org-rlr-mosaic-notes-paper t)
    (:mosaic-handout "MOSAIC_HANDOUT" nil nil t)
    (:mosaic-overflow "MOSAIC_OVERFLOW" nil nil t)
    (:mosaic-frozen-counters "MOSAIC_FROZEN_COUNTERS" nil nil t)
    (:mosaic-frozen-states "MOSAIC_FROZEN_STATES" nil nil t)
    (:mosaic-setup "MOSAIC_SETUP" nil nil newline)
    (:mosaic-preamble "MOSAIC_PREAMBLE" nil nil newline)))


;;; Internal functions

;;;; Value coercion

(defun org-rlr-mosaic--typst-literal-p (value)
  "Non-nil when VALUE is already a self-contained Typst expression.

Such a value is passed through untouched, which is what keeps the whole
Mosaic API reachable from Org: anything this predicate accepts escapes
the convenience coercion in `org-rlr-mosaic--field-value'."
  (or
   ;; Content block, dictionary/array/parenthesised expression, code
   ;; expression, string literal, or math.
   (string-match-p "\\`[][(#\"$]" value)
   ;; Bare Typst keywords.
   (member value '("none" "auto" "true" "false"))
   ;; Numbers, lengths, ratios, fractions, angles.
   (string-match-p "\\`-?[0-9]*\\.?[0-9]+\\(pt\\|em\\|cm\\|mm\\|in\\|%\\|fr\\|deg\\|rad\\)?\\'"
                   value)
   ;; A function call or a dotted lookup: rgb(..), path(..),
   ;; m.layouts.title(..), black.transparentize(..), mosaic.palettes.dark.
   (string-match-p "\\`[A-Za-z_][A-Za-z0-9_-]*\\(\\.[A-Za-z_][A-Za-z0-9_-]*\\)*(" value)
   (string-match-p "\\`[A-Za-z_][A-Za-z0-9_-]*\\.[A-Za-z_]" value)))

(defun org-rlr-mosaic--field-value (name value)
  "Return VALUE rendered as the Typst argument value for field NAME.

A value that is already a Typst expression is passed through verbatim.
Otherwise NAME decides how a bare word is read: as a string for fields
like `layout' and `variant', as `path(...)' for image fields, and as a
content block for fields like `caption' and `title'.  Any other field
is passed through unchanged."
  (let ((value (org-trim value)))
    (cond
     ((org-rlr-mosaic--typst-literal-p value) value)
     ((member name org-rlr-mosaic--path-fields) (format "path(%S)" value))
     ((member name org-rlr-mosaic--string-fields) (format "%S" value))
     ((member name org-rlr-mosaic--content-fields) (format "[%s]" value))
     (t value))))

(defun org-rlr-mosaic--attribute-args (element &optional exclude)
  "Return ELEMENT's `#+ATTR_MOSAIC' line as a list of Typst argument strings.

Each `:key value' pair becomes \"key: VALUE\", with VALUE coerced by
`org-rlr-mosaic--field-value' exactly as a headline property would be.
Attribute names in EXCLUDE are skipped, for callers that render those
themselves."
  (let ((plist (org-export-read-attribute :attr_mosaic element))
        args)
    (while plist
      (let ((name (substring (symbol-name (car plist)) 1))
            (value (cadr plist)))
        (when (and value (not (member name exclude)))
          (push (format "%s: %s"
                        name
                        (org-rlr-mosaic--field-value
                         name (if (stringp value) value (format "%s" value))))
                args)))
      (setq plist (cddr plist)))
    (nreverse args)))

(defun org-rlr-mosaic--attribute (element name)
  "Return ELEMENT's `#+ATTR_MOSAIC' attribute NAME as a string, or nil."
  (let ((value (plist-get (org-export-read-attribute :attr_mosaic element)
                          (intern (concat ":" name)))))
    (and value (org-string-nw-p (if (stringp value) value (format "%s" value))))))

(defun org-rlr-mosaic--join-args (args)
  "Join ARGS, a list of Typst argument strings, into an argument list."
  (mapconcat #'identity (delq nil args) ", "))

(defun org-rlr-mosaic--call (function args)
  "Return a call of FUNCTION with ARGS, omitting empty parentheses."
  (if (org-string-nw-p args) (format "%s(%s)" function args) function))

(defun org-rlr-mosaic--field-args (fields)
  "Render FIELDS, an alist of (NAME . RAW-VALUE), as Typst arguments."
  (mapcar (lambda (field)
            (format "%s: %s"
                    (car field)
                    (org-rlr-mosaic--field-value (car field) (cdr field))))
          fields))

;;;; Option readers

(defun org-rlr-mosaic--option-flag (value)
  "Interpret VALUE, which may be a string from a keyword, as a boolean.

Org gives keyword values as strings, so the customization value t and
the keyword value \"t\" must both read as true, and \"nil\" must read
as false rather than as the non-empty -- hence true -- string it is."
  (cond
   ((null value) nil)
   ((stringp value)
    (let ((value (downcase (org-trim value))))
      (not (member value '("" "nil" "no" "off" "none" "false")))))
   (t t)))

(defun org-rlr-mosaic--slide-level (info)
  "Return the Org headline level that becomes a content slide.
INFO is a plist used as a communication channel."
  (let ((value (plist-get info :mosaic-slide-level)))
    (max 1 (min 2 (if (stringp value) (string-to-number value) (or value 2))))))

(defun org-rlr-mosaic--depth (headline info)
  "Return the Typst heading depth HEADLINE maps onto.

Depth 1 is a Mosaic section slide and depth 2 a content slide, so the
offset between Org levels and Typst depths is whatever moves
`org-rlr-mosaic-slide-level' onto 2.  INFO is a plist used as a
communication channel."
  (+ (org-export-get-relative-level headline info)
     (- 2 (org-rlr-mosaic--slide-level info))))

;;;; Body partitioning

(defun org-rlr-mosaic--partition (contents)
  "Split CONTENTS into a cons of (OWN-BODY . CHILDREN).

OWN-BODY is what the headline's own section produced; CHILDREN is what
its child headlines produced.  The two are told apart by the sentinel
`org-rlr-mosaic-section' appends, which each headline strips from its
own contents on the way up, so only the current headline's marker is
ever present here."
  (let* ((contents (or contents ""))
         (index (string-match (regexp-quote org-rlr-mosaic--body-marker) contents)))
    (if index
        (cons (substring contents 0 index)
              (substring contents (+ index (length org-rlr-mosaic--body-marker))))
      (cons "" contents))))

(defun org-rlr-mosaic--cells (body)
  "Split BODY on `#+MOSAIC: split' into a list of non-empty cell strings."
  (let ((parts (mapcar #'org-trim
                       (split-string body (regexp-quote org-rlr-mosaic--split-marker)))))
    ;; Keep interior empties -- an empty cell is a legitimate way to skip
    ;; a positional block -- but drop leading/trailing ones, which are
    ;; just the blank lines around the marker.
    (while (and parts (equal (car parts) "")) (setq parts (cdr parts)))
    (setq parts (nreverse parts))
    (while (and parts (equal (car parts) "")) (setq parts (cdr parts)))
    (nreverse parts)))

(defun org-rlr-mosaic--strip-note-calls (string)
  "Return STRING with every `#m.note[...]' call removed.

Bracket nesting inside a note is tracked, so a note whose own body
contains bracketed content is removed whole."
  (let ((call "#m.note[")
        (start 0)
        (out "")
        (done nil))
    (while (not done)
      (let ((hit (string-match (regexp-quote call) string start)))
        (if (not hit)
            (setq out (concat out (substring string start))
                  done t)
          (setq out (concat out (substring string start hit)))
          (let ((index (+ hit (length call)))
                (depth 1)
                (length (length string)))
            (while (and (< index length) (> depth 0))
              (pcase (aref string index)
                (?\[ (setq depth (1+ depth)))
                (?\] (setq depth (1- depth))))
              (setq index (1+ index)))
            (setq start index)))))
    out))

(defun org-rlr-mosaic--notes-only-p (string)
  "Non-nil when STRING holds speaker notes and nothing else."
  (string-empty-p (org-trim (org-rlr-mosaic--strip-note-calls string))))

(defun org-rlr-mosaic--strip-markers (string)
  "Remove any internal sentinels left in STRING."
  (replace-regexp-in-string
   (regexp-opt (list org-rlr-mosaic--body-marker org-rlr-mosaic--split-marker))
   "" (or string "")))

;;;; Slide fields

(defun org-rlr-mosaic--headline-fields (headline)
  "Return HEADLINE's `:MOSAIC_*:' properties as an alist of (NAME . VALUE).

NAME is the lower-case Mosaic field name and VALUE its raw, uncoerced
property string.  Fields are returned in the order of
`org-rlr-mosaic-slide-fields' so that generated argument lists are
stable and readable."
  (delq nil
        (mapcar
         (lambda (field)
           (let ((value (org-element-property
                         (intern (concat ":MOSAIC_" (upcase field))) headline)))
             (and (org-string-nw-p value) (cons field (org-trim value)))))
         org-rlr-mosaic-slide-fields)))


;;; Transcode Functions

;;;; Section

(defun org-rlr-mosaic-section (_section contents _info)
  "Transcode a SECTION element, marking where the headline's own body ends.

CONTENTS is passed through unchanged apart from the appended sentinel,
which `org-rlr-mosaic-headline' consumes and never reaches the output."
  (concat contents org-rlr-mosaic--body-marker))


;;;; Headline

(defun org-rlr-mosaic--heading-markup (headline info depth)
  "Return the Typst heading line for HEADLINE at DEPTH.
INFO is a plist used as a communication channel."
  (let* ((title (org-export-data (org-element-property :title headline) info))
         (todo (and (plist-get info :with-todo-keywords)
                    (let ((todo (org-element-property :todo-keyword headline)))
                      (and todo (concat (org-export-data todo info) " ")))))
         (tags (and (plist-get info :with-tags)
                    (let ((tag-list (org-export-get-tags headline info)))
                      (and tag-list (concat "  " (org-make-tag-string tag-list))))))
         (label (and (org-rlr-typst--headline-referred-p headline info)
                     (or (org-string-nw-p (org-element-property :CUSTOM_ID headline))
                         (org-export-get-reference headline info)))))
    (concat (make-string (max 1 depth) ?=) " " todo title tags
            (and label (format " <%s>" (org-rlr-typst--label label))))))

(defconst org-rlr-mosaic--headerless-variants '("body" "body-footer" "full")
  "Layout variants with no header cell.

A slide using one of these has nowhere to put a heading block, so the
heading is folded into its first content cell instead.")

(defun org-rlr-mosaic--explicit-slide (headline info depth fields extra body)
  "Return an explicit `#m.slide(...)' call for HEADLINE.

FIELDS is the alist of Mosaic layout fields from the headline's
properties and EXTRA the raw `:MOSAIC_ARGS:' string.  BODY is the
headline's own transcoded content.  DEPTH is the Typst heading depth.
INFO is a plist used as a communication channel.

The number of positional blocks has to match the resolved layout's cell
count exactly, since that is how Mosaic assigns content to cells.  Two
consequences shape what this emits:

  - A content slide that supplies a heading block pins
    `variant: \"header-body\"' unless the document asked for another
    variant.  Without it the block count depends on the theme -- the
    configured content layout is header-body under the default facade
    but header-body-footer under Metropolis -- and heading plus body
    would be rejected as two blocks where one or three were expected.

  - A section slide with any other field is emitted through the
    `m.layouts.section(...)' constructor rather than as a field overlay,
    because a theme whose configured section layout is a raw grid
    cannot carry overlaid fields.  The constructor is the theme's own,
    so the theme's defaults still apply."
  (let* ((layout (cdr (assoc "layout" fields)))
         (variant (cdr (assoc "variant" fields)))
         (cells (org-rlr-mosaic--cells body))
         (heading (org-rlr-mosaic--heading-markup headline info depth))
         (title (org-export-data (org-element-property :title headline) info))
         (title-p (equal layout "title"))
         (section-p (equal layout "section"))
         (headerless (member variant org-rlr-mosaic--headerless-variants))
         ;; A body holding nothing but speaker notes is not cell content.
         ;; Notes render nowhere, but as a block they still count against
         ;; the layout's cell budget, and the layouts most likely to
         ;; carry a bare note are exactly the ones with no body cell to
         ;; spare -- the image layout's figure variant has header, image,
         ;; and caption only.  Fold them into the slide's own block,
         ;; where Mosaic collects them just the same.
         (notes-only (and cells (cl-every #'org-rlr-mosaic--notes-only-p cells)))
         (notes (and notes-only (org-trim (mapconcat #'identity cells "\n\n"))))
         (cells (if notes-only nil cells))
         ;; Fields are refinements of the configured content layout
         ;; unless the document named a different one.
         (content-p (member layout '(nil "content")))
         (fields
          (append
           fields
           ;; Several cells and no column count is a request for a
           ;; multi-column content slide.  Both of these apply only when
           ;; the document named no variant: a variant means it is
           ;; managing the layout's cells itself, and the extra cells
           ;; are that variant's own (a footer, say) rather than columns.
           (when (and content-p (null variant) (cdr cells)
                      (not (assoc "columns" fields)))
             (list (cons "columns" (number-to-string (length cells)))))
           (when (and content-p (null variant))
             (list (cons "variant" "header-body")))))
         (args
          (org-rlr-mosaic--join-args
           (append
            (if (and section-p (cdr fields))
                ;; Move every other field into the section constructor.
                (list (format "layout: %s"
                              (org-rlr-mosaic--call
                               "m.layouts.section"
                               (org-rlr-mosaic--join-args
                                (org-rlr-mosaic--field-args
                                 (assoc-delete-all "layout" (copy-sequence fields)))))))
              (org-rlr-mosaic--field-args fields))
            (and (org-string-nw-p extra) (list (org-trim extra))))))
         (join (lambda (&rest parts)
                 (mapconcat #'identity (delq nil (mapcar #'org-string-nw-p parts))
                            "\n\n")))
         (blocks
          (cond
           ;; A title slide inherits title, subtitle, authors, and date
           ;; from setup and takes no blocks at all.
           (title-p "")
           ;; A section slide takes its title as plain content; its
           ;; child slides follow the call rather than nesting in it.
           (section-p (format "[%s]" (funcall join title notes)))
           ;; No header cell: the heading opens the first content cell.
           (headerless
            (let ((cells (or cells (list ""))))
              (concat (format "[\n%s\n]"
                              (funcall join heading notes (org-trim (car cells))))
                      (mapconcat (lambda (cell) (format "[\n%s\n]" cell))
                                 (cdr cells) ""))))
           (t (concat (format "[%s]" (funcall join heading notes))
                      (mapconcat (lambda (cell) (format "[\n%s\n]" cell)) cells "")))))
         ;; A title layout accepts no block, so its notes have to precede
         ;; the call instead of riding inside one.
         (prologue (and title-p notes (concat notes "\n\n"))))
    (concat prologue (org-rlr-mosaic--call "#m.slide" args) blocks "\n\n")))

(defun org-rlr-mosaic-headline (headline contents info)
  "Transcode a HEADLINE element into a Mosaic slide.

A headline at or above the slide level becomes a slide: an ordinary
Typst heading, which Mosaic's setup turns into a slide by itself, or an
explicit `#m.slide(...)' call when the headline carries `:MOSAIC_*:'
properties or splits its body into several cells.  A headline below the
slide level stays an ordinary heading inside the slide body.

CONTENTS is the transcoded contents string.  INFO is a plist used as a
communication channel."
  (unless (org-element-property :footnote-section-p headline)
    (let* ((depth (org-rlr-mosaic--depth headline info))
           (partition (org-rlr-mosaic--partition contents))
           (body (org-trim (car partition)))
           (children (cdr partition))
           (fields (org-rlr-mosaic--headline-fields headline))
           (extra (org-element-property :MOSAIC_ARGS headline))
           (scope (org-element-property :MOSAIC_SCOPE headline))
           (heading (org-rlr-mosaic--heading-markup headline info depth)))
      (cond
       ;; Deeper than a slide: an ordinary heading within the body.
       ((> depth 2)
        (concat heading "\n\n" (org-rlr-mosaic--strip-markers body)
                (if (org-string-nw-p body) "\n\n" "") children))
       ;; Explicit slide: layout fields, scoped rules, or a body split
       ;; into cells that an automatic heading slide has nowhere to put.
       ((or fields (org-string-nw-p extra) (org-string-nw-p scope)
            (string-match-p (regexp-quote org-rlr-mosaic--split-marker) body))
        (let ((slide (org-rlr-mosaic--explicit-slide
                      headline info depth fields extra body)))
          ;; Scoped rules wrap the slide alone, never its child slides.
          (concat (if (org-string-nw-p scope)
                      (format "#[\n%s\n%s]\n\n" (org-trim scope) slide)
                    slide)
                  children)))
       ;; Automatic slide: Mosaic's setup makes the slide from the
       ;; heading itself, which is the form to prefer.
       (t
        (concat heading "\n\n" body (if (org-string-nw-p body) "\n\n" "") children))))))


;;;; Keyword

(defun org-rlr-mosaic-keyword (keyword contents info)
  "Transcode a KEYWORD element, handling `#+MOSAIC:' lines.

`#+MOSAIC: pause' emits an incremental step boundary and
`#+MOSAIC: split' a cell boundary within the slide body; any other
value passes through as raw Typst, as `#+TYPST:' does.  Every other
keyword is left to the parent back-end.

CONTENTS is nil.  INFO is a plist used as a communication channel."
  (let ((key (org-element-property :key keyword))
        (value (org-trim (or (org-element-property :value keyword) ""))))
    (cond
     ((equal key "MOSAIC")
      (pcase (downcase value)
        ("pause" "#m.steps.pause\n\n")
        ("split" org-rlr-mosaic--split-marker)
        ("" nil)
        (_ value)))
     ;; A deck's table of contents lists sections by default; Org's
     ;; optional depth argument (`#+TOC: headlines 2') selects slides too.
     ((and (equal key "TOC") (string-match-p "\\<headlines\\>" (downcase value)))
      (format "#outline(depth: %s)"
              (if (string-match "[0-9]+" value) (match-string 0 value) "1")))
     (t (org-rlr-typst-keyword keyword contents info)))))


;;;; Quote Block

(defun org-rlr-mosaic--quote-credit (element)
  "Return ELEMENT's quote attribution and source as one Typst argument.

Mosaic renders the two on a single line separated by a comma, but joins
them across a newline in markup, which Typst reads as a space: the
credit comes out as \"Aristotle , Politics\".  Since Mosaic gives
`source' no styling of its own and reads it nowhere else -- the two
share one text span in `component/quote.typ' -- they are joined here
into a single `attribution' instead, which sets the comma tight and
leaves each half free to carry its own markup.

Only the pair is affected: either alone renders correctly through
Mosaic's own argument, so it is passed through untouched."
  (let* ((attribution (org-rlr-mosaic--attribute element "attribution"))
         (source (org-rlr-mosaic--attribute element "source"))
         (value (lambda (name raw)
                  (org-rlr-mosaic--field-value name raw))))
    (cond
     ((and attribution source)
      ;; Each half is embedded with `#' so that a content block and a
      ;; bare expression are both spliced rather than printed.
      (list (format "attribution: [#%s, #%s]"
                    (funcall value "attribution" attribution)
                    (funcall value "source" source))))
     (attribution
      (list (format "attribution: %s" (funcall value "attribution" attribution))))
     (source
      (list (format "source: %s" (funcall value "source" source)))))))

(defun org-rlr-mosaic-quote-block (quote-block contents info)
  "Transcode a QUOTE-BLOCK element into a Mosaic quote, or a native one.

Org parses `#+begin_quote' into its own element type rather than a
special block, so Mosaic's quote component is reached from here rather
than from `org-rlr-mosaic-special-block'.  A `#+ATTR_MOSAIC:' line
supplies the component's arguments:

  #+ATTR_MOSAIC: :attribution Ada Lovelace :source Notes, 1843
  #+begin_quote
  The Analytical Engine weaves algebraic patterns.
  #+end_quote

The component is used whenever such a line is present, and otherwise
only when `org-rlr-mosaic-quote-component' asks for it; a plain quote
block stays a native Typst `#quote(block: true)' so that the theme's own
quotation styling applies.

CONTENTS is the transcoded contents string.  INFO is a plist used as a
communication channel."
  (let ((attrs (append (org-rlr-mosaic--quote-credit quote-block)
                       (org-rlr-mosaic--attribute-args
                        quote-block '("attribution" "source")))))
    (if (or attrs
            (org-rlr-mosaic--option-flag (plist-get info :mosaic-quote-component)))
        ;; The body is the component's first positional parameter, which
        ;; a trailing content block supplies.
        (format "%s[\n%s\n]\n\n"
                (org-rlr-mosaic--call "#m.components.quote"
                                      (org-rlr-mosaic--join-args attrs))
                (org-trim (org-rlr-mosaic--strip-markers (or contents ""))))
      (org-rlr-typst-quote-block quote-block contents info))))


;;;; Special Block

(defun org-rlr-mosaic-special-block (special-block contents info)
  "Transcode a SPECIAL-BLOCK element into a Mosaic construct.

Mosaic's speaker notes, incremental step commands, and components are
reachable as named blocks:

  #+begin_note ... #+end_note            -> #m.note[...]
  #+begin_reveal ... #+end_reveal        -> #m.steps.reveal[...]
  #+begin_step 2-4 ... #+end_step        -> #m.steps.on(\"2-4\")[...]
  #+begin_replace ... #+end_replace      -> #m.steps.replace[...][...]
  #+begin_callout ... #+end_callout      -> #m.components.callout(...)[...]

`#+begin_replace' takes its alternatives separated by `#+MOSAIC: split'.
A `#+ATTR_MOSAIC:' line above any of these supplies further arguments,
e.g. `:role \"warning\"' or `:before \"dimmed\"'.  Any other special
block falls through to the parent back-end, which calls a same-named
Typst function.

CONTENTS is the transcoded contents string.  INFO is a plist used as a
communication channel."
  (let* ((type (downcase (or (org-element-property :type special-block) "")))
         (params (org-string-nw-p
                  (org-trim (or (org-element-property :parameters special-block) ""))))
         (attrs (org-rlr-mosaic--attribute-args special-block))
         (body (org-trim (or contents ""))))
    (pcase type
      ("note"
       (format "#m.note[\n%s\n]\n\n" (org-rlr-mosaic--strip-markers body)))
      ((or "reveal" "steps")
       (format "%s[\n%s\n]\n\n"
               (org-rlr-mosaic--call "#m.steps.reveal" (org-rlr-mosaic--join-args attrs))
               (org-rlr-mosaic--strip-markers body)))
      ((or "step" "only" "on")
       (format "#m.steps.on(%s)[\n%s\n]\n\n"
               (org-rlr-mosaic--join-args
                (cons (format "%S" (or params "1")) attrs))
               (org-rlr-mosaic--strip-markers body)))
      ("replace"
       (format "%s%s\n\n"
               (org-rlr-mosaic--call "#m.steps.replace" (org-rlr-mosaic--join-args attrs))
               (mapconcat (lambda (cell) (format "[\n%s\n]" cell))
                          (org-rlr-mosaic--cells body) "")))
      ((or "callout" "card" "badge" "divider" "progress")
       (format "%s[\n%s\n]\n\n"
               (org-rlr-mosaic--call (concat "#m.components." type)
                                     (org-rlr-mosaic--join-args attrs))
               (org-rlr-mosaic--strip-markers body)))
      (_ (org-rlr-typst-special-block special-block contents info)))))


;;;; Template

(defun org-rlr-mosaic--imports (info)
  "Return the deck's Typst import lines.
INFO is a plist used as a communication channel."
  (let ((package (or (org-string-nw-p (plist-get info :mosaic-package))
                     org-rlr-mosaic-package))
        (theme (org-string-nw-p (or (plist-get info :mosaic-theme) ""))))
    (concat
     (if theme
         ;; Import the package under its own name so that its palettes and
         ;; other non-facade exports stay reachable alongside the facade.
         (format "#import %S as mosaic\n#import mosaic.themes.%s as m\n" package theme)
       (format "#import %S as m\n" package))
     (when (and (plist-get info :with-latex) (org-rlr-typst--uses-math-p info))
       (concat (plist-get info :rlr-typst-mitex-import) "\n")))))

(defun org-rlr-mosaic--authors (info)
  "Return the Typst value for `m.setup''s `authors:' argument, or nil.

`#+MOSAIC_AUTHORS:' is passed through verbatim, which is how author
records built with `m.layouts.author(...)' are supplied.  Otherwise
`#+AUTHOR:' is split on semicolons, or on commas when there are none,
so that several authors become the array Mosaic expects.  INFO is a
plist used as a communication channel."
  (let ((explicit (org-string-nw-p (or (plist-get info :mosaic-authors) ""))))
    (cond
     (explicit (org-trim explicit))
     ((not (plist-get info :with-author)) nil)
     (t
      (let ((raw (org-string-nw-p (org-export-data (plist-get info :author) info))))
        (when raw
          (let ((names (mapcar #'org-trim
                               (split-string raw (if (string-match-p ";" raw) ";" ",") t))))
            (if (cdr names)
                (format "(%s)" (mapconcat (lambda (name) (format "[%s]" name)) names ", "))
              (format "[%s]" (car names))))))))))

(defun org-rlr-mosaic--setup (info)
  "Return the deck's `#show: m.setup' line.
INFO is a plist used as a communication channel."
  (let* ((raw (lambda (key) (org-string-nw-p (or (plist-get info key) ""))))
         (title (and (plist-get info :with-title)
                     (org-string-nw-p (org-export-data (plist-get info :title) info))))
         (subtitle (org-string-nw-p (org-export-data (plist-get info :subtitle) info)))
         (authors (org-rlr-mosaic--authors info))
         (date (and (plist-get info :with-date)
                    (org-string-nw-p (org-export-data (org-export-get-date info) info))))
         (paper (or (funcall raw :mosaic-paper) org-rlr-mosaic-paper))
         (args (delq nil
                     (list
                      (and title (format "title: [%s]" title))
                      (and subtitle (format "subtitle: [%s]" subtitle))
                      (and authors (format "authors: %s" authors))
                      (and date (format "date: [%s]" date))
                      (and paper (not (equal paper "16-9")) (format "paper: %S" paper))
                      (and (funcall raw :mosaic-colors)
                           (format "colors: %s" (funcall raw :mosaic-colors)))
                      (and (funcall raw :mosaic-layouts)
                           (format "layouts: %s" (funcall raw :mosaic-layouts)))
                      (and (funcall raw :mosaic-cells)
                           (format "cells: %s" (funcall raw :mosaic-cells)))
                      (and (funcall raw :mosaic-background)
                           (format "background: %s" (funcall raw :mosaic-background)))
                      (and (funcall raw :mosaic-foreground)
                           (format "foreground: %s" (funcall raw :mosaic-foreground)))
                      (and (funcall raw :mosaic-spacing)
                           (format "spacing: %s" (funcall raw :mosaic-spacing)))
                      (and (funcall raw :mosaic-output)
                           (format "output: %S" (funcall raw :mosaic-output)))
                      (and (funcall raw :mosaic-notes)
                           (format "notes: %s" (funcall raw :mosaic-notes)))
                      (and (org-rlr-mosaic--option-flag (plist-get info :mosaic-handout))
                           "handout: true")
                      (and (funcall raw :mosaic-overflow)
                           (format "overflow: %S" (funcall raw :mosaic-overflow)))
                      (and (funcall raw :mosaic-frozen-counters)
                           (format "frozen-counters: %s"
                                   (funcall raw :mosaic-frozen-counters)))
                      (and (funcall raw :mosaic-frozen-states)
                           (format "frozen-states: %s"
                                   (funcall raw :mosaic-frozen-states)))))))
    (when (funcall raw :mosaic-setup)
      (setq args (append args (split-string (funcall raw :mosaic-setup) "\n" t))))
    (if args
        (format "#show: m.setup.with(\n%s\n)\n"
                (mapconcat (lambda (arg) (concat "  " (org-trim arg) ",")) args "\n"))
      "#show: m.setup\n")))

(defun org-rlr-mosaic--notes-paper (info)
  "Return a `#set page' rule fixing the printed outputs' paper, or nil.

Mosaic hard-codes A4 for the `speaker' and `notes' companions, so the
paper is changed by a rule after `m.setup' rather than by an argument to
it.  The rule is confined to those two outputs: `slides' and `split'
size their page from the slide itself, and a `paper:' rule would replace
that geometry.  INFO is a plist used as a communication channel."
  (let ((output (downcase (org-trim (or (plist-get info :mosaic-output) ""))))
        (paper (org-string-nw-p (or (plist-get info :mosaic-notes-paper) ""))))
    (and paper
         (member output '("speaker" "notes"))
         (format "\n#set page(paper: %S)\n" (org-trim paper)))))

(defun org-rlr-mosaic--preamble (info)
  "Return the deck's `#+MOSAIC_PREAMBLE:' rules, or nil.

These are emitted between `m.setup' and the first slide, which is where
Mosaic expects deck-wide `set' and `show' rules: a rule placed after the
first slide would miss it.  They are rules rather than content, so they
do not trip Mosaic's check for content before the first heading.  INFO
is a plist used as a communication channel."
  (let ((preamble (org-string-nw-p (or (plist-get info :mosaic-preamble) ""))))
    (and preamble (concat "\n" (org-trim preamble) "\n"))))

(defun org-rlr-mosaic--title-slide (info)
  "Return the deck's title slide, or nil.
INFO is a plist used as a communication channel."
  (let ((value (plist-get info :mosaic-title-slide))
        (title (and (plist-get info :with-title)
                    (org-string-nw-p (org-export-data (plist-get info :title) info)))))
    (when (and title (org-rlr-mosaic--option-flag value))
      (let ((variant (and (stringp value)
                          (not (member (downcase (org-trim value)) '("t" "yes" "on")))
                          (org-trim value))))
        (format "#m.slide(layout: \"title\"%s)\n\n"
                (if variant (format ", variant: %S" variant) ""))))))

(defun org-rlr-mosaic-inner-template (contents info)
  "Return the body of the deck.

A requested table of contents becomes a slide of its own rather than
loose content, which Mosaic rejects before the first slide.  CONTENTS is
the transcoded contents string.  INFO is a plist used as a communication
channel."
  (concat
   (when (plist-get info :with-toc)
     ;; The variant is pinned for the same reason explicit content
     ;; slides pin it: two blocks only fit a two-cell layout, and the
     ;; configured one is theme-dependent.  The outline lists whatever
     ;; the deck's top level is -- sections when there are any, and
     ;; otherwise the slides themselves.
     (format "#m.slide(variant: \"header-body\")[== %s][\n#outline(depth: %d)\n]\n\n"
             (org-export-translate "Table of Contents" :utf-8 info)
             (- 3 (org-rlr-mosaic--slide-level info))))
   contents))

(defun org-rlr-mosaic-template (contents info)
  "Return the complete deck as a Typst document.

CONTENTS is the transcoded contents string.  INFO is a plist used as a
communication channel."
  (replace-regexp-in-string
   "\n\\{3,\\}" "\n\n"
   (org-rlr-mosaic--strip-markers
    (concat (org-rlr-mosaic--imports info)
            "\n"
            (org-rlr-mosaic--setup info)
            ;; Before the document's own rules, so that a deck wanting
            ;; something else can simply state it.
            (org-rlr-mosaic--notes-paper info)
            (org-rlr-mosaic--preamble info)
            "\n"
            (org-rlr-mosaic--title-slide info)
            contents))))


;;; Interactive functions

;;;###autoload
(defun org-rlr-mosaic-export-as-typst (&optional async subtreep visible-only)
  "Export current buffer to a Mosaic Typst buffer.

If narrowing is active in the current buffer, only export its
narrowed part.

If a region is active, export that region.

A non-nil optional argument ASYNC means the process should happen
asynchronously.  The resulting buffer should be accessible through the
`org-export-stack' interface.

When optional argument SUBTREEP is non-nil, export the sub-tree at
point, extracting information from the headline properties first.

When optional argument VISIBLE-ONLY is non-nil, don't export contents
of hidden elements.

Export is done in a buffer named \"*Org Mosaic Export*\"."
  (interactive)
  (org-export-to-buffer 'rlr-mosaic "*Org Mosaic Export*"
    async subtreep visible-only nil nil (lambda () (text-mode))))

;;;###autoload
(defun org-rlr-mosaic-export-to-typst (&optional async subtreep visible-only)
  "Export current buffer to a Mosaic Typst file.

If narrowing is active in the current buffer, only export its
narrowed part.

If a region is active, export that region.

A non-nil optional argument ASYNC means the process should happen
asynchronously.  The resulting file should be accessible through the
`org-export-stack' interface.

When optional argument SUBTREEP is non-nil, export the sub-tree at
point, extracting information from the headline properties first.

When optional argument VISIBLE-ONLY is non-nil, don't export contents
of hidden elements.

Return output file's name."
  (interactive)
  (let ((outfile (org-export-output-file-name ".typ" subtreep)))
    (org-export-to-file 'rlr-mosaic outfile async subtreep visible-only)))

;;;###autoload
(defun org-rlr-mosaic-export-to-pdf (&optional async subtreep visible-only)
  "Export current buffer to a Mosaic Typst file and compile it to PDF.

The Typst file is written as by `org-rlr-mosaic-export-to-typst' and
then compiled with `org-rlr-mosaic-typst-command'.  Compilation happens
in the exported file's directory, so that
`org-rlr-mosaic-typst-compile-options' roots relative image paths there.

See `org-rlr-mosaic-export-to-typst' for ASYNC, SUBTREEP, and
VISIBLE-ONLY.

Return the PDF file's name."
  (interactive)
  (let ((typ (org-rlr-mosaic-export-to-typst async subtreep visible-only)))
    (org-rlr-mosaic-compile typ)))

(defun org-rlr-mosaic-compile (file)
  "Compile FILE, a Mosaic Typst deck, into a PDF and return its name.

Signal an error, showing Typst's own diagnostic, when compilation
fails."
  (let* ((file (expand-file-name file))
         (pdf (concat (file-name-sans-extension file) ".pdf"))
         (default-directory (file-name-directory file))
         (buffer (get-buffer-create "*Org Mosaic Typst Output*"))
         status)
    (with-current-buffer buffer (erase-buffer))
    (setq status (apply #'call-process
                        org-rlr-mosaic-typst-command nil buffer nil
                        (append (list "compile")
                                org-rlr-mosaic-typst-compile-options
                                (list (file-relative-name file)
                                      (file-relative-name pdf)))))
    (if (zerop status)
        (progn (message "Compiled %s" (file-name-nondirectory pdf)) pdf)
      (display-buffer buffer)
      (error "Typst failed to compile %s; see *Org Mosaic Typst Output*"
             (file-name-nondirectory file)))))

;;;###autoload
(defun org-rlr-mosaic-publish-to-typst (plist filename pub-dir)
  "Publish an Org file to a Mosaic Typst deck.

FILENAME is the filename of the Org file to be published.  PLIST is
the property list for the given project.  PUB-DIR is the publishing
directory.

Return output file name."
  (org-publish-org-to 'rlr-mosaic filename ".typ" plist pub-dir))

(provide 'ox-rlr-mosaic)

;;; ox-rlr-mosaic.el ends here
