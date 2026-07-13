;;; ox-rlr-typst.el --- Typst Backend for Org Export Engine -*- lexical-binding: t; -*-

;; Author: Randy Ridenour
;; Keywords: org, typst, tex
;; Package-Requires: ((emacs "27.1") (org "9.6"))
;; Homepage: https://github.com/rlridenour/ox-rlr-typst

;;; Commentary:

;; This library implements a Typst back-end for the Org export engine,
;; producing standard Typst (https://typst.app) markup from an Org
;; document.  It derives from the built-in `ascii' back-end, which
;; supplies harmless fallback rendering for any construct not
;; explicitly handled below (e.g. inline tasks, clocks, planning
;; lines).
;;
;; Conventions:
;;
;;   - Headline depth maps 1:1 onto Typst heading depth (`*' -> `=',
;;     `**' -> `==', and so on), offset by `org-rlr-typst-toplevel-hlevel'.
;;   - Bold/italic/underline/strike-through/code map onto Typst's own
;;     markup shorthands (`*bold*', `_italic_', `#underline[...]',
;;     `#strike[...]', `` `code` ``).
;;   - `#+begin_export typst ... #+end_export' blocks (and the
;;     `#+TYPST: ...' keyword) pass through verbatim -- the same
;;     convention used by `rlr-org-standard-form.el'.
;;   - Any other `#+begin_NAME ... #+end_NAME' special block becomes
;;     `#NAME[...]', letting you invoke your own Typst functions
;;     directly from Org, e.g. `#+begin_note' -> `#note[...]'.
;;   - LaTeX fragments/environments (`$...$', `$$...$$', `\(...\)',
;;     `\[...\]', `\begin{...}...\end{...}') are rendered through the
;;     `mitex' Typst package (https://typst.app/universe/package/mitex)
;;     via `#mi(`...`)' (inline) or `#mitex(`...`)' (block), so
;;     ordinary LaTeX math syntax keeps working unchanged.  The import
;;     line is only emitted when the document actually contains math.
;;   - Tables become native `#table(...)' calls, with a leading row
;;     group wrapped in `table.header(...)' when the Org table has one,
;;     and per-column alignment carried over from Org's alignment
;;     cookies.
;;   - Footnotes are inlined at their first reference as
;;     `#footnote[...] <fn-LABEL>'; later references to the same
;;     labelled footnote become `#footnote(<fn-LABEL>)'. Anonymous
;;     footnotes (`[fn::...]') cannot be referenced twice in Org, so
;;     this covers all repeatable cases.
;;   - A headline is given a Typst label (`<id>') when it carries a
;;     `:CUSTOM_ID:' property or is the target of an internal link, so
;;     `[[#some-id]]'-style links resolve to `#link(<some-id>)[...]' or
;;     bare `@some-id' references.
;;
;; Usage: `M-x org-rlr-typst-export-to-typst' exports the current
;; buffer to a sibling ".typ" file; `M-x org-rlr-typst-export-as-typst'
;; exports to a temporary buffer instead.

;;; Code:

(require 'cl-lib)
(require 'ox)
(require 'ox-ascii)
(require 'ox-publish)
(require 'subr-x)


;;; User-Configurable Variables

(defgroup org-export-rlr-typst nil
  "Options specific to Typst export back-end."
  :tag "Org Typst"
  :group 'org-export)

(defcustom org-rlr-typst-toplevel-hlevel 1
  "Heading level to use for level 1 Org headings in Typst export.

If this is 1, headline levels are preserved on export (Org level 1
becomes a single `='). Incrementing this value is useful when the
exported Typst is meant to be spliced into a larger document that
reserves top-level headings for its own use."
  :group 'org-export-rlr-typst
  :type 'integer)

(defcustom org-rlr-typst-mitex-import "#import \"@preview/mitex:0.2.7\": *"
  "Import line emitted when the document contains LaTeX math.
Only used when a `latex-fragment' or `latex-environment' is present
and `:with-latex' is non-nil."
  :group 'org-export-rlr-typst
  :type 'string)


;;; Define Backend

(org-export-define-derived-backend 'rlr-typst 'ascii
  :menu-entry
  '(?y "Export to Typst"
       ((?T "As Typst buffer" org-rlr-typst-export-as-typst)
        (?t "To file" org-rlr-typst-export-to-typst)
        (?o "To file and open"
            (lambda (a s v b)
              (if a (org-rlr-typst-export-to-typst t s v)
                (org-open-file (org-rlr-typst-export-to-typst nil s v)))))))
  :translate-alist
  '((bold . org-rlr-typst-bold)
    (center-block . org-rlr-typst-center-block)
    (clock . (lambda (&rest _) nil))
    (code . org-rlr-typst-verbatim)
    (comment . (lambda (&rest _) nil))
    (comment-block . (lambda (&rest _) nil))
    (drawer . org-rlr-typst-drawer)
    (entity . org-rlr-typst-entity)
    (example-block . org-rlr-typst-example-block)
    (export-block . org-rlr-typst-export-block)
    (fixed-width . org-rlr-typst-example-block)
    (footnote-definition . (lambda (&rest _) nil))
    (footnote-reference . org-rlr-typst-footnote-reference)
    (headline . org-rlr-typst-headline)
    (horizontal-rule . org-rlr-typst-horizontal-rule)
    (inline-src-block . org-rlr-typst-verbatim)
    (inner-template . org-rlr-typst-inner-template)
    (italic . org-rlr-typst-italic)
    (item . org-rlr-typst-item)
    (keyword . org-rlr-typst-keyword)
    (latex-environment . org-rlr-typst-latex-environment)
    (latex-fragment . org-rlr-typst-latex-fragment)
    (line-break . org-rlr-typst-line-break)
    (link . org-rlr-typst-link)
    (node-property . org-rlr-typst-node-property)
    (paragraph . org-rlr-typst-paragraph)
    (plain-list . org-rlr-typst-plain-list)
    (plain-text . org-rlr-typst-plain-text)
    (property-drawer . org-rlr-typst-property-drawer)
    (quote-block . org-rlr-typst-quote-block)
    (radio-target . org-rlr-typst-radio-target)
    (section . org-rlr-typst-section)
    (special-block . org-rlr-typst-special-block)
    (src-block . org-rlr-typst-src-block)
    (strike-through . org-rlr-typst-strike-through)
    (subscript . org-rlr-typst-subscript)
    (superscript . org-rlr-typst-superscript)
    (table . org-rlr-typst-table)
    (table-cell . org-rlr-typst-table-cell)
    (table-row . org-rlr-typst-table-row)
    (target . org-rlr-typst-radio-target)
    (template . org-rlr-typst-template)
    (underline . org-rlr-typst-underline)
    (verbatim . org-rlr-typst-verbatim))
  :options-alist
  '((:rlr-typst-toplevel-hlevel nil nil org-rlr-typst-toplevel-hlevel)
    (:rlr-typst-mitex-import nil nil org-rlr-typst-mitex-import)))


;;; Internal functions

(defun org-rlr-typst--label (raw)
  "Sanitize RAW into a valid Typst label token."
  (replace-regexp-in-string "[^A-Za-z0-9_-]+" "-" raw))

(defun org-rlr-typst--fence-for (value)
  "Return the shortest backtick fence that can safely enclose VALUE.
VALUE may itself contain runs of backticks; the fence is made one
character longer than the longest such run (minimum one backtick, the
idiomatic Typst inline raw span)."
  (let ((longest 0) (start 0))
    (while (string-match "`+" value start)
      (setq longest (max longest (length (match-string 0 value))))
      (setq start (match-end 0)))
    (make-string (max 1 (1+ longest)) ?`)))

(defun org-rlr-typst--raw (value)
  "Wrap VALUE in a backtick-fenced Typst raw span.
Adds a guard space on both sides when the fence reaches 3 backticks or
more, since Typst then treats text up to the first whitespace as
a language tag."
  (let ((fence (org-rlr-typst--fence-for value)))
    (if (>= (length fence) 3)
        (format "%s %s %s" fence value fence)
      (format "%s%s%s" fence value fence))))

(defun org-rlr-typst--headline-referred-p (headline info)
  "Non-nil when HEADLINE is the target of an internal link.
INFO is a plist used as a communication channel."
  (or (org-string-nw-p (org-element-property :CUSTOM_ID headline))
      (org-element-map (plist-get info :parse-tree) 'link
        (lambda (link)
          (equal headline
                 (condition-case nil
                     (pcase (org-element-property :type link)
                       ((or "custom-id" "id") (org-export-resolve-id-link link info))
                       ("fuzzy" (org-export-resolve-fuzzy-link link info)))
                   (org-link-broken nil))))
        info t)))


;;; Transcode Functions

;;;; Bold, Italic, Underline, Strike-through

(defun org-rlr-typst-bold (_bold contents _info)
  "Transcode a BOLD object into Typst strong emphasis."
  (format "*%s*" contents))

(defun org-rlr-typst-italic (_italic contents _info)
  "Transcode an ITALIC object into Typst emphasis."
  (format "_%s_" contents))

(defun org-rlr-typst-underline (_underline contents _info)
  "Transcode an UNDERLINE object into a Typst `#underline[...]' call."
  (format "#underline[%s]" contents))

(defun org-rlr-typst-strike-through (_strike-through contents _info)
  "Transcode a STRIKE-THROUGH object into a Typst `#strike[...]' call."
  (format "#strike[%s]" contents))


;;;; Code, Verbatim, Inline Src Block

(defun org-rlr-typst-verbatim (verbatim _contents _info)
  "Transcode a CODE/VERBATIM/INLINE-SRC-BLOCK object into a Typst raw span."
  (org-rlr-typst--raw (org-element-property :value verbatim)))


;;;; Example Block, Src Block, Export Block

(defun org-rlr-typst-example-block (example-block _contents info)
  "Transcode an EXAMPLE-BLOCK/FIXED-WIDTH element into a Typst raw block."
  (let ((value (org-export-format-code-default example-block info)))
    (format "```\n%s```\n\n" (org-remove-indentation value))))

(defun org-rlr-typst-src-block (src-block _contents info)
  "Transcode a SRC-BLOCK element into a Typst fenced raw block."
  (let ((lang (or (org-element-property :language src-block) ""))
        (value (org-export-format-code-default src-block info)))
    (format "```%s\n%s```\n\n" lang (org-remove-indentation value))))

(defun org-rlr-typst-export-block (export-block contents info)
  "Transcode an EXPORT-BLOCK element, passing Typst blocks through verbatim."
  (if (member (org-element-property :type export-block) '("TYPST" "TYP"))
      (concat (org-remove-indentation (org-element-property :value export-block)) "\n")
    (org-export-with-backend 'ascii export-block contents info)))


;;;; Headline, Section

(defun org-rlr-typst-headline (headline contents info)
  "Transcode a HEADLINE element into a Typst heading."
  (unless (org-element-property :footnote-section-p headline)
    (let* ((level (+ (org-export-get-relative-level headline info)
                      (1- (plist-get info :rlr-typst-toplevel-hlevel))))
           (title (org-export-data (org-element-property :title headline) info))
           (todo (and (plist-get info :with-todo-keywords)
                      (let ((todo (org-element-property :todo-keyword headline)))
                        (and todo (concat (org-export-data todo info) " ")))))
           (priority (and (plist-get info :with-priority)
                          (let ((char (org-element-property :priority headline)))
                            (and char (format "[#%c] " char)))))
           (tags (and (plist-get info :with-tags)
                      (let ((tag-list (org-export-get-tags headline info)))
                        (and tag-list (concat "  " (org-make-tag-string tag-list))))))
           (heading (concat todo priority title tags))
           (label (and (org-rlr-typst--headline-referred-p headline info)
                       (or (org-string-nw-p (org-element-property :CUSTOM_ID headline))
                           (org-export-get-reference headline info)))))
      (concat (make-string (max 1 level) ?=) " " heading
              (and label (format " <%s>" (org-rlr-typst--label label)))
              "\n\n" (or contents "")))))

(defun org-rlr-typst-section (_section contents _info)
  "Transcode a SECTION element, passing its content through."
  contents)


;;;; Drawer

(defun org-rlr-typst-drawer (_drawer contents _info)
  "Transcode a DRAWER element, passing its content through.
Org's own export core already excludes LOGBOOK drawers by default (see
`org-export-with-drawers'), so a drawer reaching this function is one
the user chose to keep -- e.g. a folded-away container for `#+TYPST:'
lines or a `#+begin_export typst' block, as in `rlr-org-standard-form.el'
-style settings drawers. Dropping CONTENTS unconditionally here would
silently discard that."
  contents)


;;;; Horizontal Rule

(defun org-rlr-typst-horizontal-rule (_horizontal-rule _contents _info)
  "Transcode a HORIZONTAL-RULE object into a Typst full-width line."
  "#line(length: 100%)\n\n")


;;;; Keyword

(defun org-rlr-typst-keyword (keyword _contents _info)
  "Transcode a KEYWORD element into Typst format."
  (pcase (org-element-property :key keyword)
    ((or "TYPST" "TYP") (org-element-property :value keyword))
    ("TOC"
     (let ((case-fold-search t)
           (value (org-element-property :value keyword)))
       (when (string-match-p "\\<headlines\\>" value)
         "#outline()")))
    (_ nil)))


;;;; LaTeX Fragment, LaTeX Environment

(defun org-rlr-typst-latex-fragment (latex-fragment _contents info)
  "Transcode a LATEX-FRAGMENT object into a `mitex' call.
Inline fragments (`$...$', `\\(...\\)') become `#mi(...)'; display
fragments (`$$...$$', `\\[...\\]') become a standalone `#mitex(...)'."
  (when (plist-get info :with-latex)
    (let ((frag (org-element-property :value latex-fragment)))
      (cond
       ((string-prefix-p "\\(" frag)
        (format "#mi(%s)" (org-rlr-typst--raw (substring frag 2 -2))))
       ((string-prefix-p "\\[" frag)
        (format "\n#mitex(%s)\n\n" (org-rlr-typst--raw (substring frag 2 -2))))
       ((string-prefix-p "$$" frag)
        (format "\n#mitex(%s)\n\n" (org-rlr-typst--raw (substring frag 2 -2))))
       (t
        (format "#mi(%s)" (org-rlr-typst--raw (substring frag 1 -1))))))))

(defun org-rlr-typst-latex-environment (latex-environment _contents info)
  "Transcode a LATEX-ENVIRONMENT element into a standalone `mitex' call."
  (when (plist-get info :with-latex)
    (let* ((body (org-remove-indentation (org-element-property :value latex-environment)))
           (fence (org-rlr-typst--fence-for body)))
      (format "#mitex(%s\n%s\n%s)\n\n" fence body fence))))


;;;; Line Break

(defun org-rlr-typst-line-break (_line-break _contents _info)
  "Transcode a LINE-BREAK object into a Typst manual line break."
  "\\\n")


;;;; Link

(defun org-rlr-typst-link (link desc info)
  "Transcode a LINK object into Typst format.
DESC is the description part of the link, or nil."
  (let* ((type (org-element-property :type link))
         (raw-path (org-element-property :path link))
         (raw-link (org-element-property :raw-link link)))
    (cond
     ;; Internal destination: headline, custom-id, id, fuzzy, or radio target.
     ((member type '("custom-id" "id" "fuzzy" "radio"))
      (let ((destination
             (pcase type
               ("fuzzy" (org-export-resolve-fuzzy-link link info))
               ("radio" (org-export-resolve-radio-link link info))
               (_ (org-export-resolve-id-link link info)))))
        (if (not destination)
            (or desc raw-link)
          (let ((label
                 (org-rlr-typst--label
                  (or (org-string-nw-p (org-element-property :CUSTOM_ID destination))
                      (org-export-get-reference destination info)))))
            (if (org-string-nw-p desc)
                (format "#link(<%s>)[%s]" label desc)
              (format "@%s" label))))))
     ;; Inline image.
     ((org-export-inline-image-p link org-html-inline-image-rules)
      (let* ((path (if (string= type "file") raw-path (concat type ":" raw-path)))
             (parent (org-export-get-parent-element link))
             (caption (org-export-data (org-export-get-caption parent) info)))
        (if (org-string-nw-p caption)
            (format "#figure(image(%S), caption: [%s])\n\n" path caption)
          (format "#image(%S)" path))))
     ;; Any other link: external URL, mailto, etc.
     (t
      (let ((path (if (member type '("http" "https" "mailto" "ftp")) raw-link
                     (concat type ":" raw-path))))
        (format "#link(%S)[%s]" path (if (org-string-nw-p desc) desc path)))))))


;;;; Property Drawer, Node Property

(defun org-rlr-typst-property-drawer (_property-drawer contents _info)
  "Transcode a PROPERTY-DRAWER element, passing its content through.
Org's own export core already excludes property drawers by default
\(see `org-export-with-properties'), so CONTENTS is empty unless the
user explicitly opted in with `#+OPTIONS: prop:t' or similar."
  (and (org-string-nw-p contents) contents))

(defun org-rlr-typst-node-property (node-property _contents _info)
  "Transcode a NODE-PROPERTY element into Typst comment syntax."
  (format "// %s:%s"
          (org-element-property :key node-property)
          (let ((value (org-element-property :value node-property)))
            (if value (concat " " value) ""))))


;;;; Paragraph

(defun org-rlr-typst-paragraph (_paragraph contents _info)
  "Transcode a PARAGRAPH element into a Typst paragraph."
  (concat (org-trim contents) "\n\n"))


;;;; Plain List, Item

(defun org-rlr-typst-plain-list (_plain-list contents _info)
  "Transcode a PLAIN-LIST element, passing its items through."
  (concat contents "\n"))

(defun org-rlr-typst-item (item contents info)
  "Transcode an ITEM element into a Typst list item.
Ordered/unordered is decided from ITEM's own bullet rather than solely
from its parent list's `:type': Org merges contiguous same-indentation
lists into a single list structure (typed after its first item) even
when later items switch between `-' and `1.' bullets, so the parent
type alone isn't reliable for mixed runs."
  (let* ((parent-type (org-element-property :type (org-export-get-parent item)))
         (ordered (string-match-p "\\`[ \t]*[0-9]+[.)]"
                                   (or (org-element-property :bullet item) "")))
         (checkbox (pcase (org-element-property :checkbox item)
                     (`on "[X] ") (`trans "[-] ") (`off "[ ] ") (_ "")))
         (body (org-trim (replace-regexp-in-string "\n" "\n  " (or contents "")))))
    (if (eq parent-type 'descriptive)
        (let ((tag (org-element-property :tag item)))
          (format "/ %s: %s\n" (org-export-data tag info) body))
      (format "%s %s%s\n" (if ordered "+" "-") checkbox body))))


;;;; Plain Text

(defun org-rlr-typst-plain-text (text info)
  "Transcode a TEXT string into Typst format."
  (when (plist-get info :with-smart-quotes)
    (setq text (org-export-activate-smart-quotes text :utf-8 info)))
  ;; Protect \, #, `, *, _, @, and $ -- always-reserved Typst markup characters.
  (setq text (replace-regexp-in-string "[\\#`*_@$]" "\\\\\\&" text))
  (when (plist-get info :with-special-strings)
    (setq text (replace-regexp-in-string "\\\\-" "" text))
    (setq text (replace-regexp-in-string "---" "—" text))
    (setq text (replace-regexp-in-string "--" "–" text))
    (setq text (replace-regexp-in-string "\\.\\.\\." "…" text)))
  text)


;;;; Entity, Subscript, Superscript

(defun org-rlr-typst-entity (entity _contents _info)
  "Transcode an ENTITY object into its UTF-8 representation."
  (org-element-property :utf-8 entity))

(defun org-rlr-typst-subscript (_subscript contents _info)
  "Transcode a SUBSCRIPT object into a Typst `#sub[...]' call."
  (format "#sub[%s]" contents))

(defun org-rlr-typst-superscript (_superscript contents _info)
  "Transcode a SUPERSCRIPT object into a Typst `#super[...]' call."
  (format "#super[%s]" contents))


;;;; Radio Target, Target

(defun org-rlr-typst-radio-target (target text info)
  "Transcode a RADIO-TARGET/TARGET object into labelled Typst text."
  (format "%s <%s>" text (org-rlr-typst--label (org-export-get-reference target info))))


;;;; Footnote Reference

(defun org-rlr-typst-footnote-reference (footnote-reference _contents info)
  "Transcode a FOOTNOTE-REFERENCE object into a Typst `#footnote[...]' call.
Later references to the same labelled footnote reuse its label instead
of repeating the definition."
  (let* ((label (org-element-property :label footnote-reference))
         (tag (and label (concat "fn-" (org-rlr-typst--label label)))))
    (if (org-export-footnote-first-reference-p footnote-reference info)
        (format "#footnote[%s]%s"
                (org-trim (org-export-data
                           (org-export-get-footnote-definition footnote-reference info)
                           info))
                (if tag (format " <%s>" tag) ""))
      (format "#footnote(<%s>)" tag))))


;;;; Quote Block, Center Block

(defun org-rlr-typst-quote-block (_quote-block contents _info)
  "Transcode a QUOTE-BLOCK element into a Typst `#quote(block: true)[...]' call."
  (format "#quote(block: true)[\n%s]\n\n" (org-trim contents)))

(defun org-rlr-typst-center-block (_center-block contents _info)
  "Transcode a CENTER-BLOCK element into a Typst `#align(center)[...]' call."
  (format "#align(center)[\n%s]\n\n" (org-trim contents)))


;;;; Special Block

(defun org-rlr-typst-special-block (special-block contents _info)
  "Transcode a SPECIAL-BLOCK element into a call to a same-named Typst function.
`#+begin_NAME ... #+end_NAME' becomes `#NAME[...]', so custom Typst
functions can be invoked directly from Org."
  (let ((type (org-element-property :type special-block)))
    (format "#%s[\n%s]\n\n" type (org-trim (or contents "")))))


;;;; Table

(defun org-rlr-typst-table-cell (table-cell contents info)
  "Transcode a TABLE-CELL element into a bracketed Typst table entry."
  (concat (format "[%s]" (or contents ""))
          (when (org-export-get-next-element table-cell info) ", ")))

(defun org-rlr-typst-table-row (table-row contents info)
  "Transcode a TABLE-ROW element, tagging it as header or data for the table."
  (if (eq (org-element-property :type table-row) 'rule)
      ""
    (let ((header-p (and (org-export-table-has-header-p
                          (org-export-get-parent-table table-row) info)
                         (eql (org-export-table-row-group table-row info) 1))))
      (concat (if header-p "H" "D") "\x1" contents "\n"))))

(defun org-rlr-typst-table (table contents info)
  "Transcode a TABLE element into a Typst `#table(...)' call."
  (if (eq (org-element-property :type table) 'table.el)
      ;; table.el tables aren't supported; fall back to a raw block.
      (format "```\n%s```\n\n"
              (org-trim (org-export-format-code-default table info)))
    (let* ((cols (cdr (org-export-table-dimensions table info)))
           (first-row (org-element-map table 'table-row #'identity info t))
           (aligns (and first-row
                        (org-element-map first-row 'table-cell
                          (lambda (cell)
                            (pcase (org-export-table-cell-alignment cell info)
                              ('right "right") ('center "center") (_ "left")))
                          info)))
           (lines (split-string contents "\n" t))
           (header-lines (seq-filter (lambda (l) (string-prefix-p "H\x1" l)) lines))
           (data-lines (seq-filter (lambda (l) (string-prefix-p "D\x1" l)) lines))
           (strip (lambda (l) (substring l 2))))
      (concat
       "#table(\n"
       (format "  columns: %d,\n" (max 1 cols))
       (if aligns (format "  align: (%s),\n" (mapconcat #'identity aligns ", ")) "")
       (when header-lines
         (concat "  table.header(\n"
                 (mapconcat (lambda (l) (concat "    " (funcall strip l) ",")) header-lines "\n")
                 "\n  ),\n"))
       (mapconcat (lambda (l) (concat "  " (funcall strip l) ",")) data-lines "\n")
       "\n)\n\n"))))


;;;; Template

(defun org-rlr-typst--uses-math-p (info)
  "Non-nil when the parse tree in INFO contains LaTeX math."
  (org-element-map (plist-get info :parse-tree) '(latex-fragment latex-environment)
    (lambda (_) t) info t))

(defun org-rlr-typst--has-manual-document-metadata-p (info)
  "Non-nil when a `#+TYPST:'/`#+TYP:' line already calls `#set document(...)'.
Used to skip the auto-generated `#set document(...)' metadata block
when the user is clearly hand-writing their own Typst preamble."
  (org-element-map (plist-get info :parse-tree) 'keyword
    (lambda (kw)
      (and (member (org-element-property :key kw) '("TYPST" "TYP"))
           (string-match-p "#set[ \t]+document(" (or (org-element-property :value kw) ""))))
    info t))

(defun org-rlr-typst-inner-template (contents info)
  "Return body of document after converting it to Typst syntax.
CONTENTS is the transcoded contents string.  INFO is a plist holding
export options."
  (concat
   (when (plist-get info :with-toc) "#outline()\n\n")
   contents))

(defun org-rlr-typst-template (contents info)
  "Return complete document string after Typst conversion.
CONTENTS is the transcoded contents string.  INFO is a plist used as
a communication channel."
  (concat
   (when (and (plist-get info :with-latex) (org-rlr-typst--uses-math-p info))
     (concat (plist-get info :rlr-typst-mitex-import) "\n\n"))
   (let* ((title (and (plist-get info :with-title)
                       (org-string-nw-p (org-export-data (plist-get info :title) info))))
          (author (and (plist-get info :with-author)
                       (org-string-nw-p (org-export-data (plist-get info :author) info))))
          (date (and (plist-get info :with-date)
                     (org-string-nw-p (org-export-data (org-export-get-date info) info)))))
     (when (and (or title author date)
                (not (org-rlr-typst--has-manual-document-metadata-p info)))
       (concat "#set document("
               (mapconcat #'identity
                           (delq nil
                                 (list (and title (format "title: [%s]" title))
                                       (and author (format "author: (%S)" (substring-no-properties author)))))
                           ", ")
               ")\n"
               (and date (format "// Date: %s\n" date))
               "\n")))
   contents))


;;; Interactive functions

;;;###autoload
(defun org-rlr-typst-export-as-typst (&optional async subtreep visible-only)
  "Export current buffer to a Typst buffer.

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

Export is done in a buffer named \"*Org Typst Export*\"."
  (interactive)
  (org-export-to-buffer 'rlr-typst "*Org Typst Export*"
    async subtreep visible-only nil nil (lambda () (text-mode))))

;;;###autoload
(defun org-rlr-typst-export-to-typst (&optional async subtreep visible-only)
  "Export current buffer to a Typst file.

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
    (org-export-to-file 'rlr-typst outfile async subtreep visible-only)))

;;;###autoload
(defun org-rlr-typst-publish-to-typst (plist filename pub-dir)
  "Publish an Org file to Typst.

FILENAME is the filename of the Org file to be published.  PLIST is
the property list for the given project.  PUB-DIR is the publishing
directory.

Return output file name."
  (org-publish-org-to 'rlr-typst filename ".typ" plist pub-dir))

(provide 'ox-rlr-typst)

;;; ox-rlr-typst.el ends here
