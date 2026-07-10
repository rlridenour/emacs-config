;;; rlr-touying-scaffold.el --- Scaffold a new Touying presentation -*- lexical-binding: t; -*-

;; Creates a new Touying presentation directory containing config.typ,
;; talk.org, a live slide deck, and a flowing handout, following the
;; config.typ / content.typ / slides.typ / handout.typ pattern where the
;; slide deck and handout are the two things you actually compile.
;; content.typ itself is generated from talk.org via ox-touying.el (if
;; loaded) -- edit talk.org and re-export rather than hand-editing
;; content.typ.
;;
;; Uses the "basic-theme" Touying package (@local/basic-theme:0.1.0):
;; heading levels map onto section (=) / frame (==) by default (pass
;; slide-level: 3 for a talk that needs a subsection (==) level between
;; them, with frames at ===), the theme supports "white"/"black"/"gray"
;; variants, and plain content under a heading needs no wrapper -- it
;; becomes a slide automatically, which keeps content.typ close to a
;; plain Org-mode export. The generated handout numbers every heading
;; (1, 1.1, 1.2, 2, ...) and draws a line above each handout-note, to
;; mark reader-only text that wasn't part of what the audience saw.
;;
;; Usage: M-x rlr/new-touying-presentation

(require 'seq)

(defun rlr/touying-slugify (title)
  "Build a lowercase, hyphenated filename slug from TITLE.
Words of two letters or fewer, and the words \"the\" and \"and\", are
dropped."
  (let ((words (split-string (downcase title) "[^a-z0-9]+" t)))
    (mapconcat #'identity
               (seq-filter (lambda (w) (and (> (length w) 2)
                                            (not (member w '("the" "and")))))
                           words)
               "-")))

(defun rlr/touying--write-file (path content)
  "Write CONTENT to PATH, refusing to overwrite an existing file."
  (when (file-exists-p path)
    (user-error "File already exists: %s" path))
  (with-temp-file path
    (insert content)))

(defun rlr/touying-config-template (slug title)
  "Return the contents of config.typ for a presentation titled TITLE.
SLUG names the corresponding slides/handout files in the comments."
  (format "// config.typ
// Shared configuration for both the live slide deck (%1$s-slides.typ) and
// the continuous handout (%1$s-handout.typ).
//
// content.typ defines its content as a function that takes title-slide/
// pause/speaker-note/handout-note/two-column-slide/full-slide as
// parameters -- plain body content under a heading needs no wrapper at
// all; Touying automatically turns it into a slide when the theme's
// slide-fn is registered (see basic-theme.with(...) below), which keeps
// content.typ close to a plain Org-mode export. Each entry point below
// supplies its own implementations of the remaining parameters:
// %1$s-slides.typ passes the real Touying building blocks (real
// pagination, animations, speaker notes); %1$s-handout.typ passes plain,
// non-paginating stand-ins so the whole thing renders as one flowing
// document instead of a slide deck.

#import \"@preview/touying:0.7.4\": *
#import \"@local/basic-theme:0.1.0\": (
  basic-theme,
  basic-theme-date-format,
  univ-logo,
  title-slide as live-title-slide,
  pause as live-pause,
  speaker-note as live-speaker-note,
  two-column-slide as live-two-column-slide,
  full-slide as live-full-slide,
)

// Presentation metadata, shared between the live title slide (which
// reads it via Touying's `self.info`) and the handout title \"slide\"
// (which has no Touying context and so renders it directly).
#let presentation-info = (
  title: [%2$s],
  subtitle: [],
  author: [Dr. Ridenour],
  date: datetime.today(),
  institution: [Department of Philosophy],
)

// variant: \"white\" (default), \"black\", or \"gray\".
//
// slide-level: 2 (default) for a talk with no subsections (`=`
// section, `==` frame directly), or 3 if this talk uses subsections
// (`=` section, `==` subsection, `===` frame).
#let project(variant: \"white\", slide-level: 2, body) = {
  show: basic-theme.with(
    aspect-ratio: \"16-9\",
    variant: variant,
    slide-level: slide-level,
    config-common(
      show-notes-on-second-screen: right,
    ),
    config-info(
      ..presentation-info,
      logo: univ-logo(),
    ),
  )

  body
}

// Handout notes never show on the live deck.
#let live-handout-note(body) = none

// -- Handout: a single flowing document, no slide pagination ---------------

// Portrait US letter, 12pt body text; no theme/pagination machinery at
// all. Headings (section, and frame, and subsection if slide-level: 3
// is used) render plainly with their own numbering (1, 1.1, 1.2, ...)
// -- there's no box, so a frame heading doesn't need special hiding/
// relocation the way it did when its title had to be pulled inside one.
#let handout-project(body) = {
  set page(paper: \"us-letter\")
  set text(size: 12pt)
  set heading(numbering: \"1.1\")
  body
}

// The document title is not a \"slide\" in the same sense as the others
// -- kept outside any box, same as section/subsection titles.
#let handout-title-slide() = align(center)[
  #text(size: 1.4em, weight: \"bold\", presentation-info.title)

  #if presentation-info.subtitle not in (none, []) {
    text(size: 1.15em, weight: \"bold\", presentation-info.subtitle)
  }

  #v(0.5em)

  #presentation-info.author

  #presentation-info.institution

  #presentation-info.date.display(basic-theme-date-format)
]

// No animation reveal in a flowing document: everything is simply shown.
#let handout-pause = none

// Speaker notes are presenter-only; never shown in the handout.
#let handout-speaker-note(body) = none

// A plain two-up grid; there's no pagination to preserve here.
#let handout-two-column-slide(columns: (1fr, 1fr), gutter: 2em, ..bodies) = grid(
  columns: columns,
  gutter: gutter,
  ..bodies.pos(),
)

// There's no full-bleed page in a flowing document, and a `100%%` height
// inside body would otherwise resolve against the whole rest of the
// page -- bound it to a fixed-height box instead, so the graphic shows
// inline at a sane size.
#let handout-full-slide(fill: auto, body) = box(width: 100%%, height: 300pt, clip: true, body)

// A handout note is reader-only context that never appeared on the live
// slide -- a line above it marks that boundary, so it's clear the text
// below the line wasn't part of what the audience saw.
#let handout-note(body) = {
  v(0.5em)
  line(length: 100%%, stroke: 0.5pt + gray)
  v(0.5em)
  body
}
"
          slug title))

(defun rlr/touying-content-fallback-template (title)
  "Return a minimal content.typ for a presentation titled TITLE.
Only used when ox-touying.el isn't loaded, so talk.org can't be
exported yet -- once it's loaded, re-export talk.org instead of
hand-editing this file."
  (format "// content.typ
// Slide content for %1$s, written once as a function of its building
// blocks so it can render either as live Touying slides (*-slides.typ) or
// as a flowing handout (*-handout.typ).
//
// Plain content under a heading needs no wrapper; only speaker-note/
// handout-note (which must differ between the live deck and the
// handout) and the two special layouts (two-column-slide, full-slide)
// are explicit calls.
//
// This is a placeholder -- ox-touying.el wasn't loaded when this
// presentation was scaffolded, so content.typ could not be generated
// from talk.org. Load ox-touying.el and M-x
// rlr/org-export-to-touying-content from talk.org to regenerate it.

#let content(
  title-slide,
  pause,
  speaker-note,
  handout-note,
  two-column-slide,
  full-slide,
) = [
  #title-slide()

]
"
          title))

(defun rlr/touying-org-template (title)
  "Return the contents of talk.org for a presentation titled TITLE.
Exported to content.typ via `rlr/org-export-to-touying-content' (see
ox-touying.el) -- edit this file and re-export rather than
hand-editing content.typ."
  (format "#+TITLE: %1$s

# Edit this file, then M-x rlr/org-export-to-touying-content to
# regenerate content.typ -- don't hand-edit content.typ, since
# re-exporting will overwrite it. Conventions:
#
#   * Section     -> `= Section` (its own section slide)
#   ** A slide     -> `== A slide` (a frame -- no wrapper needed for
#                     plain body text)
#   #+begin_speakernote ... #+end_speakernote -> #speaker-note[...]
#   #+begin_handoutnote ... #+end_handoutnote -> #handout-note[...]
#   @@typst:#pause@@ -> a progressive reveal
#   #+begin_columns containing two #+begin_column ... #+end_column
#     blocks -> #two-column-slide[...][...]
#   #+begin_fullslide ... #+end_fullslide -> #full-slide(...); a lone
#     image link inside becomes a full-bleed image
#   #+begin_statement ... #+end_statement -> big centered text, sized
#     via a preceding #+ATTR_TOUYING: :size 3em (default 2em); nest
#     inside #+begin_fullslide for a blank, title-less statement slide
"
          title))

(defun rlr/touying-slides-template (slug)
  "Return the contents of the live-deck entry file for SLUG."
  (format "// %1$s-slides.typ
// Entry point for the live slide deck: applies the Touying config and
// renders content.typ's content using the real Touying building blocks.

#import \"config.typ\": (
  project,
  live-title-slide,
  live-pause,
  live-speaker-note,
  live-handout-note,
  live-two-column-slide,
  live-full-slide,
)
#import \"content.typ\": content

#show: project

#content(
  live-title-slide,
  live-pause,
  live-speaker-note,
  live-handout-note,
  live-two-column-slide,
  live-full-slide,
)
"
          slug))

(defun rlr/touying-handout-template (slug)
  "Return the contents of the handout entry file for SLUG."
  (format "// %1$s-handout.typ
// Handout compile: same content as %1$s-slides.typ, rendered as a single
// continuous document instead of paginated slides — no page break between
// slides, animations collapsed to their final state, handout notes shown,
// and speaker notes omitted. Compile with: typst compile %1$s-handout.typ

#import \"config.typ\": (
  handout-project,
  handout-title-slide,
  handout-pause,
  handout-speaker-note,
  handout-note,
  handout-two-column-slide,
  handout-full-slide,
)
#import \"content.typ\": content

#show: handout-project

#content(
  handout-title-slide,
  handout-pause,
  handout-speaker-note,
  handout-note,
  handout-two-column-slide,
  handout-full-slide,
)
"
          slug))

(defun rlr/touying--generate-content-file (org-file content-file title)
  "Generate CONTENT-FILE by exporting ORG-FILE with ox-touying.el.
Falls back to a minimal static template if ox-touying.el isn't loaded
(and can't be found on `load-path')."
  (if (require 'ox-touying nil t)
      (with-current-buffer (find-file-noselect org-file)
        (org-mode)
        (rlr/org-export-to-touying-content))
    (rlr/touying--write-file content-file (rlr/touying-content-fallback-template title))))

;;;###autoload
(defun rlr/new-touying-presentation (title dir)
  "Scaffold a new Touying presentation called TITLE inside DIR.

Creates a subdirectory of DIR (named after a slug derived from TITLE)
containing config.typ, talk.org, a slides/handout pair whose filenames
are prefixed with that slug (e.g. \"my-talk-slides.typ\" and
\"my-talk-handout.typ\"), and content.typ -- generated from talk.org via
ox-touying.el (see `rlr/touying--generate-content-file'). The slug is
TITLE lower-cased, hyphenated, with the words \"the\" and \"and\", and
any two-letter-or-shorter words, removed."
  (interactive
   (list (read-string "Presentation title: ")
         (read-directory-name "Create in directory: " default-directory)))
  (let* ((slug (rlr/touying-slugify title)))
    (when (string-empty-p slug)
      (user-error "Title \"%s\" has no usable words for a filename" title))
    (let* ((project-dir (expand-file-name slug dir))
           (config-file (expand-file-name "config.typ" project-dir))
           (org-file (expand-file-name "talk.org" project-dir))
           (content-file (expand-file-name "content.typ" project-dir))
           (slides-file (expand-file-name (concat slug "-slides.typ") project-dir))
           (handout-file (expand-file-name (concat slug "-handout.typ") project-dir)))
      (make-directory project-dir t)
      (rlr/touying--write-file config-file (rlr/touying-config-template slug title))
      (rlr/touying--write-file org-file (rlr/touying-org-template title))
      (rlr/touying--write-file slides-file (rlr/touying-slides-template slug))
      (rlr/touying--write-file handout-file (rlr/touying-handout-template slug))
      (rlr/touying--generate-content-file org-file content-file title)
      (find-file org-file)
      (message "Created Touying presentation \"%s\" in %s" title project-dir))))

(defun compile-typst-lecture ()
  "Compiles the slides.typ and handout.typ files in the directory."
  (interactive)
    (shell-command "compile-touying-deck"))

(provide 'rlr-touying-scaffold)
;;; rlr-touying-scaffold.el ends here
