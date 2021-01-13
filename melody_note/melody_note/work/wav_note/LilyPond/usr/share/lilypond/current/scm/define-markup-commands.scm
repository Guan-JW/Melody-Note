;;;; This file is part of LilyPond, the GNU music typesetter.
;;;;
;;;; Copyright (C) 2000--2012  Han-Wen Nienhuys <hanwen@xs4all.nl>
;;;;                  Jan Nieuwenhuizen <janneke@gnu.org>
;;;;
;;;; LilyPond is free software: you can redistribute it and/or modify
;;;; it under the terms of the GNU General Public License as published by
;;;; the Free Software Foundation, either version 3 of the License, or
;;;; (at your option) any later version.
;;;;
;;;; LilyPond is distributed in the hope that it will be useful,
;;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;;; GNU General Public License for more details.
;;;;
;;;; You should have received a copy of the GNU General Public License
;;;; along with LilyPond.  If not, see <http://www.gnu.org/licenses/>.

;;;
;;; Markup commands and markup-list commands definitions.
;;;
;;; Markup commands which are part of LilyPond, are defined
;;; in the (lily) module, which is the current module in this file,
;;; using the `define-markup-command' macro.
;;;
;;; Usage:
;;;
;;; (define-markup-command (command-name layout props args...)
;;;   args-signature
;;;   [ #:category category ]
;;;   [ #:properties property-bindings ]
;;;   documentation-string
;;;   ..body..)
;;;
;;; with:
;;;   command-name
;;;     the name of the markup command
;;;
;;;   layout and props
;;;     arguments that are automatically passed to the command when it
;;;     is interpreted.
;;;     `layout' is an output def, which properties can be accessed
;;;     using `ly:output-def-lookup'.
;;;     `props' is a list of property settings which can be accessed
;;;     using `chain-assoc-get' (more on that below)
;;;
;;;   args...
;;;     the command arguments.
;;;     There is no limitation on the order of command arguments.
;;;     However, markup functions taking a markup as their last
;;;     argument are somewhat special as you can apply them to a
;;;     markup list, and the result is a markup list where the
;;;     markup function (with the specified leading arguments) has
;;;     been applied to every element of the original markup list.
;;;
;;;     Since replicating the leading arguments for applying a
;;;     markup function to a markup list is cheap mostly for
;;;     Scheme arguments, you avoid performance pitfalls by just
;;;     using Scheme arguments for the leading arguments of markup
;;;     functions that take a markup as their last argument.
;;;
;;;   args-signature
;;;     the arguments signature, i.e., a list of type predicates which
;;;     are used to type check the arguments, and also to define the general
;;;     argument types (markup, markup-list, scheme) that the command is
;;;     expecting.
;;;     For instance, if a command expects a number, then a markup, the
;;;     signature would be: (number? markup?)
;;;
;;;   category
;;;     for documentation purpose, builtin markup commands are grouped by
;;;     category.  This can be any symbol.  When documentation is generated,
;;;     the symbol is converted to a capitalized string, where hyphens are
;;;     replaced by spaces.
;;;
;;;   property-bindings
;;;     this is used both for documentation generation, and to ease
;;;     programming the command itself.  It is list of
;;;        (property-name default-value)
;;;     or (property-name)
;;;     elements.  Each property is looked-up in the `props' argument, and
;;;     the symbol naming the property is bound to its value.
;;;     When the property is not found in `props', then the symbol is bound
;;;     to the given default value.  When no default value is given, #f is
;;;     used instead.
;;;     Thus, using the following property bindings:
;;;       ((thickness 0.1)
;;;        (font-size 0))
;;;     is equivalent to writing:
;;;       (let ((thickness (chain-assoc-get 'thickness props 0.1))
;;;             (font-size (chain-assoc-get 'font-size props 0)))
;;;         ..body..)
;;;     When a command `B' internally calls an other command `A', it may
;;;     desirable to see in `B' documentation all the properties and
;;;     default values used by `A'.  In that case, add `A-markup' to the
;;;     property-bindings of B.  (This is used when generating
;;;     documentation, but won't create bindings.)
;;;
;;;   documentation-string
;;;     the command documentation string (used to generate manuals)
;;;
;;;   body
;;;     the command body.  The function is supposed to return a stencil.
;;;
;;; Each markup command definition shall have a documentation string
;;; with description, syntax and example.

(use-modules (ice-9 regex))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; utility functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public empty-stencil (ly:make-stencil '()
                                              empty-interval empty-interval))
(define-public point-stencil (ly:make-stencil "" '(0 . 0) '(0 . 0)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; geometric shapes
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-markup-command (draw-line layout props dest)
  (number-pair?)
  #:category graphic
  #:properties ((thickness 1))
  "
@cindex drawing lines within text

A simple line.
@lilypond[verbatim,quote]
\\markup {
  \\draw-line #'(4 . 4)
  \\override #'(thickness . 5)
  \\draw-line #'(-3 . 0)
}
@end lilypond"
  (let ((th (* (ly:output-def-lookup layout 'line-thickness)
               thickness))
        (x (car dest))
        (y (cdr dest)))
    (make-line-stencil th 0 0 x y)))

(define-markup-command (draw-dashed-line layout props dest)
  (number-pair?)
  #:category graphic
  #:properties ((thickness 1)
                (on 1)
                (off 1)
                (phase 0)
                (full-length #t))
  "
@cindex drawing dashed lines within text

A dashed line.

If @code{full-length} is set to #t (default) the dashed-line extends to the
whole length given by @var{dest}, without white space at beginning or end.
@code{off} will then be altered to fit.
To insist on the given (or default) values of @code{on}, @code{off} use
@code{\\override #'(full-length . #f)}
Manual settings for @code{on},@code{off} and @code{phase} are possible.
@lilypond[verbatim,quote]
\\markup {
  \\draw-dashed-line #'(5.1 . 2.3)
  \\override #'(on . 0.3)
  \\override #'(off . 0.5)
  \\draw-dashed-line #'(5.1 . 2.3)
}
@end lilypond"
  (let* ((line-thickness (ly:output-def-lookup layout 'line-thickness))
         ;; Calculate the thickness to be used.
         (th (* line-thickness thickness))
         (half-thick (/ th 2))
         ;; Get the extensions in x- and y-direction.
         (x (car dest))
         (y (cdr dest))
         ;; Calculate the length of the dashed line.
         (line-length (sqrt (+ (expt x 2) (expt y 2)))))

    (if (and full-length (not (= (+ on off) 0)))
        (begin
          ;; Add double-thickness to avoid overlapping.
          (set! off (+ (* 2 th) off))
          (let* (;; Make a guess how often the off/on-pair should be printed
                 ;; after the initial `on´.
                 ;; Assume a minimum of 1 to avoid division by zero.
                 (guess (max 1 (round (/ (- line-length on) (+ off on)))))
                 ;; Not sure about the value or why corr is necessary at all,
                 ;; but it seems to be necessary.
                 (corr (if (= on 0)
                           (/ line-thickness 10)
                           0))
                 ;; Calculate a new value for off to fit the
                 ;; line-length.
                 (new-off (/ (- line-length corr (* (1+ guess) on)) guess))
                 )
            (cond

             ;; Settings for (= on 0). Resulting in a dotted line.

             ;; If line-length isn't shorter than `th´, change the given
             ;; value for `off´ to fit the line-length.
             ((and (= on 0) (< th line-length))
              (set! off new-off))

             ;; If the line-length is shorter than `th´, it makes no
             ;; sense to adjust `off´. The rounded edges of the lines
             ;; would prevent any nice output.
             ;; Do nothing.
             ;; This will result in a single dot for very short lines.
             ((and (= on 0) (>= th line-length))
              #f)

             ;; Settings for (not (= on 0)). Resulting in a dashed line.

             ;; If line-length isn't shorter than one go of on-off-on,
             ;; change the given value for `off´ to fit the line-length.
             ((< (+ (* 2 on) off) line-length)
              (set! off new-off))
             ;; If the line-length is too short, but greater than
             ;; (* 4 th) set on/off to (/ line-length 3)
             ((< (* 4 th) line-length)
              (set! on (/ line-length 3))
              (set! off (/ line-length 3)))
             ;; If the line-length is shorter than (* 4 th), it makes
             ;; no sense trying to adjust on/off. The rounded edges of
             ;; the lines would prevent any nice output.
             ;; Simply set `on´ to line-length.
             (else
              (set! on line-length))))))

    ;; If `on´ or `off´ is negative, or the sum of `on' and `off' equals zero a
    ;; ghostscript-error occurs while calling
    ;; (ly:make-stencil (list 'dashed-line th on off x y phase) x-ext y-ext)
    ;; Better be paranoid.
    (if (or (= (+ on off) 0)
            (negative? on)
            (negative? off))
        (begin
          (ly:warning "Can't print a line - setting on/off to default")
          (set! on 1)
          (set! off 1)))

    ;; To give the lines produced by \draw-line and \draw-dashed-line the same
    ;; length, half-thick has to be added to the stencil-extensions.
    (ly:make-stencil
     (list 'dashed-line th on off x y phase)
     (interval-widen (ordered-cons 0 x) half-thick)
     (interval-widen (ordered-cons 0 y) half-thick))))

(define-markup-command (draw-dotted-line layout props dest)
  (number-pair?)
  #:category graphic
  #:properties ((thickness 1)
                (off 1)
                (phase 0))
  "
@cindex drawing dotted lines within text

A dotted line.

The dotted-line always extends to the whole length given by @var{dest}, without
white space at beginning or end.
Manual settings for @code{off} are possible to get larger or smaller space
between the dots.
The given (or default) value of @code{off} will be altered to fit the
line-length.
@lilypond[verbatim,quote]
\\markup {
  \\draw-dotted-line #'(5.1 . 2.3)
  \\override #'(thickness . 2)
  \\override #'(off . 0.2)
  \\draw-dotted-line #'(5.1 . 2.3)
}
@end lilypond"

  (let ((new-props (prepend-alist-chain 'on 0
                                        (prepend-alist-chain 'full-length #t props))))

    (interpret-markup layout
                      new-props
                      (markup #:draw-dashed-line dest))))

(define-markup-command (draw-hline layout props)
  ()
  #:category graphic
  #:properties ((draw-line-markup)
                (line-width)
                (span-factor 1))
  "
@cindex drawing a line across a page

Draws a line across a page, where the property @code{span-factor}
controls what fraction of the page is taken up.
@lilypond[verbatim,quote]
\\markup {
  \\column {
    \\draw-hline
    \\override #'(span-factor . 1/3)
    \\draw-hline
  }
}
@end lilypond"
  (interpret-markup layout
                    props
                    (markup #:draw-line (cons (* line-width
                                                 span-factor)
                                              0))))

(define-markup-command (draw-circle layout props radius thickness filled)
  (number? number? boolean?)
  #:category graphic
  "
@cindex drawing circles within text

A circle of radius @var{radius} and thickness @var{thickness},
optionally filled.

@lilypond[verbatim,quote]
\\markup {
  \\draw-circle #2 #0.5 ##f
  \\hspace #2
  \\draw-circle #2 #0 ##t
}
@end lilypond"
  (make-circle-stencil radius thickness filled))

(define-markup-command (triangle layout props filled)
  (boolean?)
  #:category graphic
  #:properties ((thickness 0.1)
                (font-size 0)
                (baseline-skip 2))
  "
@cindex drawing triangles within text

A triangle, either filled or empty.

@lilypond[verbatim,quote]
\\markup {
  \\triangle ##t
  \\hspace #2
  \\triangle ##f
}
@end lilypond"
  (let ((ex (* (magstep font-size) 0.8 baseline-skip)))
    (ly:make-stencil
     `(polygon '(0.0 0.0
                     ,ex 0.0
                     ,(* 0.5 ex)
                     ,(* 0.86 ex))
               ,thickness
               ,filled)
     (cons 0 ex)
     (cons 0 (* .86 ex)))))

(define-markup-command (circle layout props arg)
  (markup?)
  #:category graphic
  #:properties ((thickness 1)
                (font-size 0)
                (circle-padding 0.2))
  "
@cindex circling text

Draw a circle around @var{arg}.  Use @code{thickness},
@code{circle-padding} and @code{font-size} properties to determine line
thickness and padding around the markup.

@lilypond[verbatim,quote]
\\markup {
  \\circle {
    Hi
  }
}
@end lilypond"
  (let ((th (* (ly:output-def-lookup layout 'line-thickness)
               thickness))
        (pad (* (magstep font-size) circle-padding))
        (m (interpret-markup layout props arg)))
    (circle-stencil m th pad)))

(define-markup-command (ellipse layout props arg)
  (markup?)
  #:category graphic
  #:properties ((thickness 1)
                (font-size 0)
                (x-padding 0.2)
                (y-padding 0.2))
  "
@cindex drawing ellipse around text

Draw an ellipse around @var{arg}.  Use @code{thickness},
@code{x-padding}, @code{y-padding} and @code{font-size} properties to determine
line thickness and padding around the markup.

@lilypond[verbatim,quote]
\\markup {
  \\ellipse {
    Hi
  }
}
@end lilypond"
  (let ((th (* (ly:output-def-lookup layout 'line-thickness)
               thickness))
        (pad-x (* (magstep font-size) x-padding))
        (pad-y (* (magstep font-size) y-padding))
        (m (interpret-markup layout props arg)))
    (ellipse-stencil m th pad-x pad-y)))

(define-markup-command (oval layout props arg)
  (markup?)
  #:category graphic
  #:properties ((thickness 1)
                (font-size 0)
                (x-padding 0.75)
                (y-padding 0.75))
  "
@cindex drawing oval around text

Draw an oval around @var{arg}.  Use @code{thickness},
@code{x-padding}, @code{x-padding} and @code{font-size} properties to determine
line thickness and padding around the markup.

@lilypond[verbatim,quote]
\\markup {
  \\oval {
    Hi
  }
}
@end lilypond"
  (let ((th (* (ly:output-def-lookup layout 'line-thickness)
               thickness))
        (pad-x (* (magstep font-size) x-padding))
        (pad-y (* (magstep font-size) y-padding))
        (m (interpret-markup layout props arg)))
    (oval-stencil m th pad-x pad-y)))

(define-markup-command (with-url layout props url arg)
  (string? markup?)
  #:category graphic
  "
@cindex inserting URL links into text

Add a link to URL @var{url} around @var{arg}.  This only works in
the PDF backend.

@lilypond[verbatim,quote]
\\markup {
  \\with-url #\"http://lilypond.org/\" {
    LilyPond ... \\italic {
      music notation for everyone
    }
  }
}
@end lilypond"
  (let* ((stil (interpret-markup layout props arg))
         (xextent (ly:stencil-extent stil X))
         (yextent (ly:stencil-extent stil Y))
         (old-expr (ly:stencil-expr stil))
         (url-expr (list 'url-link url `(quote ,xextent) `(quote ,yextent))))

    (ly:stencil-add (ly:make-stencil url-expr xextent yextent) stil)))

(define-markup-command (page-link layout props page-number arg)
  (number? markup?)
  #:category other
  "
@cindex referencing page numbers in text

Add a link to the page @var{page-number} around @var{arg}.  This only works
in the PDF backend.

@lilypond[verbatim,quote]
\\markup {
  \\page-link #2  { \\italic { This links to page 2... } }
}
@end lilypond"
  (let* ((stil (interpret-markup layout props arg))
         (xextent (ly:stencil-extent stil X))
         (yextent (ly:stencil-extent stil Y))
         (old-expr (ly:stencil-expr stil))
         (link-expr (list 'page-link page-number `(quote ,xextent) `(quote ,yextent))))

    (ly:stencil-add (ly:make-stencil link-expr xextent yextent) stil)))

(define-markup-command (with-link layout props label arg)
  (symbol? markup?)
  #:category other
  "
@cindex referencing page labels in text

Add a link to the page holding label @var{label} around @var{arg}.  This
only works in the PDF backend.

@lilypond[verbatim,quote]
\\markup {
  \\with-link #'label {
    \\italic { This links to the page containing the label... }
  }
}
@end lilypond"
  (let* ((arg-stencil (interpret-markup layout props arg))
         (x-ext (ly:stencil-extent arg-stencil X))
         (y-ext (ly:stencil-extent arg-stencil Y)))
    (ly:stencil-add
     (ly:make-stencil
      `(delay-stencil-evaluation
        ,(delay (let* ((table (ly:output-def-lookup layout 'label-page-table))
                       (page-number (if (list? table)
                                        (assoc-get label table)
                                        #f)))
                  (list 'page-link page-number
                        `(quote ,x-ext) `(quote ,y-ext)))))
      x-ext
      y-ext)
     arg-stencil)))


(define-markup-command (beam layout props width slope thickness)
  (number? number? number?)
  #:category graphic
  "
@cindex drawing beams within text

Create a beam with the specified parameters.
@lilypond[verbatim,quote]
\\markup {
  \\beam #5 #1 #2
}
@end lilypond"
  (let* ((y (* slope width))
         (yext (cons (min 0 y) (max 0 y)))
         (half (/ thickness 2)))

    (ly:make-stencil
     `(polygon ',(list
                  0 (/ thickness -2)
                  width (+ (* width slope)  (/ thickness -2))
                  width (+ (* width slope)  (/ thickness 2))
                  0 (/ thickness 2))
               ,(ly:output-def-lookup layout 'blot-diameter)
               #t)
     (cons 0 width)
     (cons (+ (- half) (car yext))
           (+ half (cdr yext))))))

(define-markup-command (underline layout props arg)
  (markup?)
  #:category font
  #:properties ((thickness 1) (offset 2))
  "
@cindex underlining text

Underline @var{arg}.  Looks at @code{thickness} to determine line
thickness, and @code{offset} to determine line y-offset.

@lilypond[verbatim,quote]
\\markup \\fill-line {
  \\underline \"underlined\"
  \\override #'(offset . 5)
  \\override #'(thickness . 1)
  \\underline \"underlined\"
  \\override #'(offset . 1)
  \\override #'(thickness . 5)
  \\underline \"underlined\"
}
@end lilypond"
  (let* ((thick (ly:output-def-lookup layout 'line-thickness))
         (underline-thick (* thickness thick))
         (markup (interpret-markup layout props arg))
         (x1 (car (ly:stencil-extent markup X)))
         (x2 (cdr (ly:stencil-extent markup X)))
         (y (* thick (- offset)))
         (line (make-line-stencil underline-thick x1 y x2 y)))
    (ly:stencil-add markup line)))

(define-markup-command (box layout props arg)
  (markup?)
  #:category font
  #:properties ((thickness 1)
                (font-size 0)
                (box-padding 0.2))
  "
@cindex enclosing text within a box

Draw a box round @var{arg}.  Looks at @code{thickness},
@code{box-padding} and @code{font-size} properties to determine line
thickness and padding around the markup.

@lilypond[verbatim,quote]
\\markup {
  \\override #'(box-padding . 0.5)
  \\box
  \\line { V. S. }
}
@end lilypond"
  (let* ((th (* (ly:output-def-lookup layout 'line-thickness)
                thickness))
         (pad (* (magstep font-size) box-padding))
         (m (interpret-markup layout props arg)))
    (box-stencil m th pad)))

(define-markup-command (filled-box layout props xext yext blot)
  (number-pair? number-pair? number?)
  #:category graphic
  "
@cindex drawing solid boxes within text
@cindex drawing boxes with rounded corners

Draw a box with rounded corners of dimensions @var{xext} and
@var{yext}.  For example,
@verbatim
\\filled-box #'(-.3 . 1.8) #'(-.3 . 1.8) #0
@end verbatim
creates a box extending horizontally from -0.3 to 1.8 and
vertically from -0.3 up to 1.8, with corners formed from a
circle of diameter@tie{}0 (i.e., sharp corners).

@lilypond[verbatim,quote]
\\markup {
  \\filled-box #'(0 . 4) #'(0 . 4) #0
  \\filled-box #'(0 . 2) #'(-4 . 2) #0.4
  \\filled-box #'(1 . 8) #'(0 . 7) #0.2
  \\with-color #white
  \\filled-box #'(-4.5 . -2.5) #'(3.5 . 5.5) #0.7
}
@end lilypond"
  (ly:round-filled-box
   xext yext blot))

(define-markup-command (rounded-box layout props arg)
  (markup?)
  #:category graphic
  #:properties ((thickness 1)
                (corner-radius 1)
                (font-size 0)
                (box-padding 0.5))
  "@cindex enclosing text in a box with rounded corners
   @cindex drawing boxes with rounded corners around text
Draw a box with rounded corners around @var{arg}.  Looks at @code{thickness},
@code{box-padding} and @code{font-size} properties to determine line
thickness and padding around the markup; the @code{corner-radius} property
makes it possible to define another shape for the corners (default is 1).

@lilypond[quote,verbatim,relative=2]
c4^\\markup {
  \\rounded-box {
    Overtura
  }
}
c,8. c16 c4 r
@end lilypond"
  (let ((th (* (ly:output-def-lookup layout 'line-thickness)
               thickness))
        (pad (* (magstep font-size) box-padding))
        (m (interpret-markup layout props arg)))
    (ly:stencil-add (rounded-box-stencil m th pad corner-radius)
                    m)))

(define-markup-command (rotate layout props ang arg)
  (number? markup?)
  #:category align
  "
@cindex rotating text

Rotate object with @var{ang} degrees around its center.

@lilypond[verbatim,quote]
\\markup {
  default
  \\hspace #2
  \\rotate #45
  \\line {
    rotated 45°
  }
}
@end lilypond"
  (let* ((stil (interpret-markup layout props arg)))
    (ly:stencil-rotate stil ang 0 0)))

(define-markup-command (whiteout layout props arg)
  (markup?)
  #:category other
  "
@cindex adding a white background to text

Provide a white background for @var{arg}.

@lilypond[verbatim,quote]
\\markup {
  \\combine
    \\filled-box #'(-1 . 10) #'(-3 . 4) #1
    \\whiteout whiteout
}
@end lilypond"
  (stencil-whiteout (interpret-markup layout props arg)))

(define-markup-command (pad-markup layout props amount arg)
  (number? markup?)
  #:category align
  "
@cindex padding text
@cindex putting space around text

Add space around a markup object.
Identical to @code{pad-around}.

@lilypond[verbatim,quote]
\\markup {
  \\box {
    default
  }
  \\hspace #2
  \\box {
    \\pad-markup #1 {
      padded
    }
  }
}
@end lilypond"
  (let* ((m (interpret-markup layout props arg))
         (x (interval-widen (ly:stencil-extent m X) amount))
         (y (interval-widen (ly:stencil-extent m Y) amount)))
    (ly:stencil-add (make-transparent-box-stencil x y)
                    m)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; space
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-markup-command (strut layout props)
  ()
  #:category other
  "
@cindex creating vertical spaces in text

Create a box of the same height as the space in the current font."
  (let ((m (ly:text-interface::interpret-markup layout props " ")))
    (ly:make-stencil (ly:stencil-expr m)
                     '(0 . 0)
                     (ly:stencil-extent m X)
                     )))

(define-markup-command (hspace layout props amount)
  (number?)
  #:category align
  "
@cindex creating horizontal spaces in text

Create an invisible object taking up horizontal space @var{amount}.

@lilypond[verbatim,quote]
\\markup {
  one
  \\hspace #2
  two
  \\hspace #8
  three
}
@end lilypond"
  (ly:make-stencil "" (cons 0 amount) empty-interval))

(define-markup-command (vspace layout props amount)
  (number?)
  #:category align
  "
@cindex creating vertical spaces in text

Create an invisible object taking up vertical space
of @var{amount} multiplied by 3.

@lilypond[verbatim,quote]
\\markup {
    \\center-column {
    one
    \\vspace #2
    two
    \\vspace #5
    three
  }
}
@end lilypond"
  (let ((amount (* amount 3.0)))
    (ly:make-stencil "" empty-interval (cons 0 amount))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; importing graphics.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-markup-command (stencil layout props stil)
  (ly:stencil?)
  #:category other
  "
@cindex importing stencils into text

Use a stencil as markup.

@lilypond[verbatim,quote]
\\markup {
  \\stencil #(make-circle-stencil 2 0 #t)
}
@end lilypond"
  stil)

(define bbox-regexp
  (make-regexp "%%BoundingBox:[ \t]+([0-9-]+)[ \t]+([0-9-]+)[ \t]+([0-9-]+)[ \t]+([0-9-]+)"))

(define (get-postscript-bbox string)
  "Extract the bbox from STRING, or return #f if not present."
  (let*
      ((match (regexp-exec bbox-regexp string)))

    (if match
        (map (lambda (x)
               (string->number (match:substring match x)))
             (cdr (iota 5)))

        #f)))

(define-markup-command (epsfile layout props axis size file-name)
  (number? number? string?)
  #:category graphic
  "
@cindex inlining an Encapsulated PostScript image

Inline an EPS image.  The image is scaled along @var{axis} to
@var{size}.

@lilypond[verbatim,quote]
\\markup {
  \\general-align #Y #DOWN {
    \\epsfile #X #20 #\"context-example.eps\"
    \\epsfile #Y #20 #\"context-example.eps\"
  }
}
@end lilypond"
  (if (ly:get-option 'safe)
      (interpret-markup layout props "not allowed in safe")
      (eps-file->stencil axis size file-name)
      ))

(define-markup-command (postscript layout props str)
  (string?)
  #:category graphic
  "
@cindex inserting PostScript directly into text
This inserts @var{str} directly into the output as a PostScript
command string.

@lilypond[verbatim,quote]
ringsps = #\"
  0.15 setlinewidth
  0.9 0.6 moveto
  0.4 0.6 0.5 0 361 arc
  stroke
  1.0 0.6 0.5 0 361 arc
  stroke
  \"

rings = \\markup {
  \\with-dimensions #'(-0.2 . 1.6) #'(0 . 1.2)
  \\postscript #ringsps
}

\\relative c'' {
  c2^\\rings
  a2_\\rings
}
@end lilypond"
  ;; FIXME
  (ly:make-stencil
   (list 'embedded-ps
         (format #f "
gsave currentpoint translate
0.1 setlinewidth
 ~a
grestore
"
                 str))
   '(0 . 0) '(0 . 0)))

(define-markup-command (path layout props thickness commands) (number? list?)
  #:category graphic
  #:properties ((line-cap-style 'round)
                (line-join-style 'round)
                (filled #f))
  "
@cindex paths, drawing
@cindex drawing paths
Draws a path with line @var{thickness} according to the
directions given in @var{commands}.  @var{commands} is a list of
lists where the @code{car} of each sublist is a drawing command and
the @code{cdr} comprises the associated arguments for each command.

There are seven commands available to use in the list
@code{commands}: @code{moveto}, @code{rmoveto}, @code{lineto},
@code{rlineto}, @code{curveto}, @code{rcurveto}, and
@code{closepath}.  Note that the commands that begin with @emph{r}
are the relative variants of the other three commands.

The commands @code{moveto}, @code{rmoveto}, @code{lineto}, and
@code{rlineto} take 2 arguments; they are the X and Y coordinates
for the destination point.

The commands @code{curveto} and @code{rcurveto} create cubic
Bézier curves, and take 6 arguments; the first two are the X and Y
coordinates for the first control point, the second two are the X
and Y coordinates for the second control point, and the last two
are the X and Y coordinates for the destination point.

The @code{closepath} command takes zero arguments and closes the
current subpath in the active path.

Note that a sequence of commands @emph{must} begin with a
@code{moveto} or @code{rmoveto} to work with the SVG output.

Line-cap styles and line-join styles may be customized by
overriding the @code{line-cap-style} and @code{line-join-style}
properties, respectively.  Available line-cap styles are
@code{'butt}, @code{'round}, and @code{'square}.  Available
line-join styles are @code{'miter}, @code{'round}, and
@code{'bevel}.

The property @code{filled} specifies whether or not the path is
filled with color.

@lilypond[verbatim,quote]
samplePath =
  #'((moveto 0 0)
     (lineto -1 1)
     (lineto 1 1)
     (lineto 1 -1)
     (curveto -5 -5 -5 5 -1 0)
     (closepath))

\\markup {
  \\path #0.25 #samplePath

  \\override #'(line-join-style . miter) \\path #0.25 #samplePath

  \\override #'(filled . #t) \\path #0.25 #samplePath
}
@end lilypond"
  (let* ((half-thickness (/ thickness 2))
         (current-point '(0 . 0))
         (set-point (lambda (lst) (set! current-point lst)))
         (relative? (lambda (x)
                      (string-prefix? "r" (symbol->string (car x)))))
         ;; For calculating extents, we want to modify the command
         ;; list so that all coordinates are absolute.
         (new-commands (map (lambda (x)
                              (cond
                               ;; for rmoveto, rlineto
                               ((and (relative? x) (= 3 (length x)))
                                (let ((cp (cons
                                           (+ (car current-point)
                                              (second x))
                                           (+ (cdr current-point)
                                              (third x)))))
                                  (set-point cp)
                                  (list (car cp)
                                        (cdr cp))))
                               ;; for rcurveto
                               ((and (relative? x) (= 7 (length x)))
                                (let* ((old-cp current-point)
                                       (cp (cons
                                            (+ (car old-cp)
                                               (sixth x))
                                            (+ (cdr old-cp)
                                               (seventh x)))))
                                  (set-point cp)
                                  (list (+ (car old-cp) (second x))
                                        (+ (cdr old-cp) (third x))
                                        (+ (car old-cp) (fourth x))
                                        (+ (cdr old-cp) (fifth x))
                                        (car cp)
                                        (cdr cp))))
                               ;; for moveto, lineto
                               ((= 3 (length x))
                                (set-point (cons (second x)
                                                 (third x)))
                                (drop x 1))
                               ;; for curveto
                               ((= 7 (length x))
                                (set-point (cons (sixth x)
                                                 (seventh x)))
                                (drop x 1))
                               ;; keep closepath for filtering;
                               ;; see `without-closepath'.
                               (else x)))
                            commands))
         ;; path-min-max does not accept 0-arg lists,
         ;; and since closepath does not affect extents, filter
         ;; out those commands here.
         (without-closepath (filter (lambda (x)
                                      (not (equal? 'closepath (car x))))
                                    new-commands))
         (extents (path-min-max
                   ;; set the origin to the first moveto
                   (list (list-ref (car without-closepath) 0)
                         (list-ref (car without-closepath) 1))
                   without-closepath))
         (X-extent (cons (list-ref extents 0) (list-ref extents 1)))
         (Y-extent (cons (list-ref extents 2) (list-ref extents 3)))
         (command-list (fold-right append '() commands)))

    ;; account for line thickness
    (set! X-extent (interval-widen X-extent half-thickness))
    (set! Y-extent (interval-widen Y-extent half-thickness))

    (ly:make-stencil
     `(path ,thickness `(,@',command-list)
            ',line-cap-style ',line-join-style ,filled)
     X-extent
     Y-extent)))

(define-markup-command (score layout props score)
  (ly:score?)
  #:category music
  #:properties ((baseline-skip))
  "
@cindex inserting music into text

Inline an image of music.  The reference point (usually the middle
staff line) of the lowest staff in the top system is placed on the
baseline.

@lilypond[verbatim,quote]
\\markup {
  \\score {
    \\new PianoStaff <<
      \\new Staff \\relative c' {
        \\key f \\major
        \\time 3/4
        \\mark \\markup { Allegro }
        f2\\p( a4)
        c2( a4)
        bes2( g'4)
        f8( e) e4 r
      }
      \\new Staff \\relative c {
        \\clef bass
        \\key f \\major
        \\time 3/4
        f8( a c a c a
        f c' es c es c)
        f,( bes d bes d bes)
        f( g bes g bes g)
      }
    >>
    \\layout {
      indent = 0.0\\cm
      \\context {
        \\Score
        \\override RehearsalMark
          #'break-align-symbols = #'(time-signature key-signature)
        \\override RehearsalMark
          #'self-alignment-X = #LEFT
      }
      \\context {
        \\Staff
        \\override TimeSignature
          #'break-align-anchor-alignment = #LEFT
      }
    }
  }
}
@end lilypond"
  (let ((output (ly:score-embedded-format score layout)))

    (if (ly:music-output? output)
        (let ((paper-systems
               (vector->list
                (ly:paper-score-paper-systems output))))
          (if (pair? paper-systems)
              ;; shift such that the refpoint of the bottom staff of
              ;; the first system is the baseline of the score
              (ly:stencil-translate-axis
               (stack-stencils Y DOWN baseline-skip
                               (map paper-system-stencil paper-systems))
               (- (car (paper-system-staff-extents (car paper-systems))))
               Y)
              empty-stencil))
	(begin
	  (ly:warning (_"no systems found in \\score markup, does it have a \\layout block?"))
	  empty-stencil))))

(define-markup-command (null layout props)
  ()
  #:category other
  "
@cindex creating empty text objects

An empty markup with extents of a single point.

@lilypond[verbatim,quote]
\\markup {
  \\null
}
@end lilypond"
  point-stencil)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; basic formatting.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-markup-command (simple layout props str)
  (string?)
  #:category font
  "
@cindex simple text strings

A simple text string; @code{\\markup @{ foo @}} is equivalent with
@code{\\markup @{ \\simple #\"foo\" @}}.

Note: for creating standard text markup or defining new markup commands,
the use of @code{\\simple} is unnecessary.

@lilypond[verbatim,quote]
\\markup {
  \\simple #\"simple\"
  \\simple #\"text\"
  \\simple #\"strings\"
}
@end lilypond"
  (interpret-markup layout props str))

(define-markup-command (tied-lyric layout props str)
  (string?)
  #:category music
  #:properties ((word-space))
  "
@cindex simple text strings with tie characters

Like simple-markup, but use tie characters for @q{~} tilde symbols.

@lilypond[verbatim,quote]
\\markup \\column {
  \\tied-lyric #\"Siam navi~all'onde~algenti Lasciate~in abbandono\"
  \\tied-lyric #\"Impetuosi venti I nostri~affetti sono\"
  \\tied-lyric #\"Ogni diletto~e scoglio Tutta la vita~e~un mar.\"
}
@end lilypond"
  (define (replace-ties tie str)
    (if (string-contains str "~")
        (let*
            ((half-space (/ word-space 2))
             (parts (string-split str #\~))
             (tie-str (markup #:hspace half-space
                              #:musicglyph tie
                              #:hspace half-space))
             (joined  (list-join parts tie-str)))
          (make-concat-markup joined))
        str))

  (define short-tie-regexp (make-regexp "~[^.]~"))
  (define (match-short str) (regexp-exec short-tie-regexp str))

  (define (replace-short str mkp)
    (let ((match (match-short str)))
      (if (not match)
          (make-concat-markup (list
                               mkp
                               (replace-ties "ties.lyric.default" str)))
          (let ((new-str (match:suffix match))
                (new-mkp (make-concat-markup (list
                                              mkp
                                              (replace-ties "ties.lyric.default"
                                                            (match:prefix match))
                                              (replace-ties "ties.lyric.short"
                                                            (match:substring match))))))
            (replace-short new-str new-mkp)))))

  (interpret-markup layout
                    props
                    (replace-short str (markup))))

(define-public empty-markup
  (make-simple-markup ""))

;; helper for justifying lines.
(define (get-fill-space word-count line-width word-space text-widths)
  "Calculate the necessary paddings between each two adjacent texts.
  The lengths of all texts are stored in @var{text-widths}.
  The normal formula for the padding between texts a and b is:
  padding = line-width/(word-count - 1) - (length(a) + length(b))/2
  The first and last padding have to be calculated specially using the
  whole length of the first or last text.
  All paddings are checked to be at least word-space, to ensure that
  no texts collide.
  Return a list of paddings."
  (cond
   ((null? text-widths) '())

   ;; special case first padding
   ((= (length text-widths) word-count)
    (cons
     (- (- (/ line-width (1- word-count)) (car text-widths))
        (/ (car (cdr text-widths)) 2))
     (get-fill-space word-count line-width word-space (cdr text-widths))))
   ;; special case last padding
   ((= (length text-widths) 2)
    (list (- (/ line-width (1- word-count))
             (+ (/ (car text-widths) 2) (car (cdr text-widths)))) 0))
   (else
    (let ((default-padding
            (- (/ line-width (1- word-count))
               (/ (+ (car text-widths) (car (cdr text-widths))) 2))))
      (cons
       (if (> word-space default-padding)
           word-space
           default-padding)
       (get-fill-space word-count line-width word-space (cdr text-widths)))))))

(define-markup-command (fill-line layout props args)
  (markup-list?)
  #:category align
  #:properties ((text-direction RIGHT)
                (word-space 0.6)
                (line-width #f))
  "Put @var{markups} in a horizontal line of width @var{line-width}.
The markups are spaced or flushed to fill the entire line.
If there are no arguments, return an empty stencil.

@lilypond[verbatim,quote]
\\markup {
  \\column {
    \\fill-line {
      Words evenly spaced across the page
    }
    \\null
    \\fill-line {
      \\line { Text markups }
      \\line {
        \\italic { evenly spaced }
      }
      \\line { across the page }
    }
  }
}
@end lilypond"
  (let* ((orig-stencils (interpret-markup-list layout props args))
         (stencils
          (map (lambda (stc)
                 (if (ly:stencil-empty? stc)
                     point-stencil
                     stc)) orig-stencils))
         (text-widths
          (map (lambda (stc)
                 (if (ly:stencil-empty? stc)
                     0.0
                     (interval-length (ly:stencil-extent stc X))))
               stencils))
         (text-width (apply + text-widths))
         (word-count (length stencils))
         (line-width (or line-width (ly:output-def-lookup layout 'line-width)))
         (fill-space
          (cond
           ((= word-count 1)
            (list
             (/ (- line-width text-width) 2)
             (/ (- line-width text-width) 2)))
           ((= word-count 2)
            (list
             (- line-width text-width)))
           (else
            (get-fill-space word-count line-width word-space text-widths))))

         (line-contents (if (= word-count 1)
                            (list
                             point-stencil
                             (car stencils)
                             point-stencil)
                            stencils)))

    (if (null? (remove ly:stencil-empty? orig-stencils))
        empty-stencil
        (begin
          (if (= text-direction LEFT)
              (set! line-contents (reverse line-contents)))
          (set! line-contents
                (stack-stencils-padding-list
                 X RIGHT fill-space line-contents))
          (if (> word-count 1)
              ;; shift s.t. stencils align on the left edge, even if
              ;; first stencil had negative X-extent (e.g. center-column)
              ;; (if word-count = 1, X-extents are already normalized in
              ;; the definition of line-contents)
              (set! line-contents
                    (ly:stencil-translate-axis
                     line-contents
                     (- (car (ly:stencil-extent (car stencils) X)))
                     X)))
          line-contents))))

(define-markup-command (line layout props args)
  (markup-list?)
  #:category align
  #:properties ((word-space)
                (text-direction RIGHT))
  "Put @var{args} in a horizontal line.  The property @code{word-space}
determines the space between markups in @var{args}.

@lilypond[verbatim,quote]
\\markup {
  \\line {
    one two three
  }
}
@end lilypond"
  (let ((stencils (interpret-markup-list layout props args)))
    (if (= text-direction LEFT)
        (set! stencils (reverse stencils)))
    (stack-stencil-line word-space stencils)))

(define-markup-command (concat layout props args)
  (markup-list?)
  #:category align
  "
@cindex concatenating text
@cindex ligatures in text

Concatenate @var{args} in a horizontal line, without spaces in between.
Strings and simple markups are concatenated on the input level, allowing
ligatures.  For example, @code{\\concat @{ \"f\" \\simple #\"i\" @}} is
equivalent to @code{\"fi\"}.

@lilypond[verbatim,quote]
\\markup {
  \\concat {
    one
    two
    three
  }
}
@end lilypond"
  (define (concat-string-args arg-list)
    (fold-right (lambda (arg result-list)
                  (let ((result (if (pair? result-list)
                                    (car result-list)
                                    '())))
                    (if (and (pair? arg) (eqv? (car arg) simple-markup))
                        (set! arg (cadr arg)))
                    (if (and (string? result) (string? arg))
                        (cons (string-append arg result) (cdr result-list))
                        (cons arg result-list))))
                '()
                arg-list))

  (interpret-markup layout
                    (prepend-alist-chain 'word-space 0 props)
                    (make-line-markup
                     (make-override-lines-markup-list
                      (cons 'word-space
                            (chain-assoc-get 'word-space props))
                      (if (markup-command-list? args)
                          args
                          (concat-string-args args))))))

(define (wordwrap-stencils stencils
                           justify base-space line-width text-dir)
  "Perform simple wordwrap, return stencil of each line."
  (define space (if justify
                    ;; justify only stretches lines.
		    (* 0.7 base-space)
		    base-space))
  (define (stencil-len s)
    (interval-end (ly:stencil-extent s X)))
  (define (maybe-shift line)
    (if (= text-dir LEFT)
        (ly:stencil-translate-axis
         line
         (- line-width (stencil-len line))
         X)
        line))
  (if (null? stencils)
      '()
      (let loop ((lines '())
                 (todo stencils))
        (let word-loop
            ((line (first todo))
             (todo (cdr todo))
             (word-list (list (first todo))))
          (cond
           ((pair? todo)
            (let ((new (if (= text-dir LEFT)
                           (ly:stencil-stack (car todo) X RIGHT line space)
                           (ly:stencil-stack line X RIGHT (car todo) space))))
              (cond
               ((<= (stencil-len new) line-width)
                (word-loop new (cdr todo)
                           (cons (car todo) word-list)))
               (justify
                (let* ((word-list
                        ;; This depends on stencil stacking being
                        ;; associative so that stacking
                        ;; left-to-right and right-to-left leads to
                        ;; the same result
                        (if (= text-dir LEFT)
                            word-list
                            (reverse! word-list)))
                       (len (stencil-len line))
                       (stretch (- line-width len))
                       (spaces
                        (- (stencil-len
                            (stack-stencils X RIGHT (1+ space) word-list))
                           len)))
                  (if (zero? spaces)
                      ;; Uh oh, nothing to fill.
                      (loop (cons (maybe-shift line) lines) todo)
                      (loop (cons
                             (stack-stencils X RIGHT
                                             (+ space (/ stretch spaces))
                                             word-list)
                             lines)
                            todo))))
               (else ;; not justify
                (loop (cons (maybe-shift line) lines) todo)))))
           ;; todo is null
           (justify
            ;; Now we have the last line assembled with space
            ;; which is compressed.  We want to use the
            ;; uncompressed version instead if it fits, and the
            ;; justified version if it doesn't.
            (let* ((word-list
                    ;; This depends on stencil stacking being
                    ;; associative so that stacking
                    ;; left-to-right and right-to-left leads to
                    ;; the same result
                    (if (= text-dir LEFT)
                        word-list
                        (reverse! word-list)))
                   (big-line (stack-stencils X RIGHT base-space word-list))
                   (big-len (stencil-len big-line))
                   (len (stencil-len line)))
              (reverse! lines
                        (list
                         (if (> big-len line-width)
                             (stack-stencils X RIGHT
                                             (/
                                              (+
                                               (* (- big-len line-width)
                                                  space)
                                               (* (- line-width len)
                                                  base-space))
                                              (- big-len len))
                                             word-list)
                             (maybe-shift big-line))))))
           (else ;; not justify
            (reverse! lines (list (maybe-shift line)))))))))


(define-markup-list-command (wordwrap-internal layout props justify args)
  (boolean? markup-list?)
  #:properties ((line-width #f)
                (word-space)
                (text-direction RIGHT))
  "Internal markup list command used to define @code{\\justify} and @code{\\wordwrap}."
  (wordwrap-stencils (interpret-markup-list layout props args)
                     justify
                     word-space
                     (or line-width
                         (ly:output-def-lookup layout 'line-width))
                     text-direction))

(define-markup-command (justify layout props args)
  (markup-list?)
  #:category align
  #:properties ((baseline-skip)
                wordwrap-internal-markup-list)
  "
@cindex justifying text

Like @code{\\wordwrap}, but with lines stretched to justify the margins.
Use @code{\\override #'(line-width . @var{X})} to set the line width;
@var{X}@tie{}is the number of staff spaces.

@lilypond[verbatim,quote]
\\markup {
  \\justify {
    Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed
    do eiusmod tempor incididunt ut labore et dolore magna aliqua.
    Ut enim ad minim veniam, quis nostrud exercitation ullamco
    laboris nisi ut aliquip ex ea commodo consequat.
  }
}
@end lilypond"
  (stack-lines DOWN 0.0 baseline-skip
               (wordwrap-internal-markup-list layout props #t args)))

(define-markup-command (wordwrap layout props args)
  (markup-list?)
  #:category align
  #:properties ((baseline-skip)
                wordwrap-internal-markup-list)
  "Simple wordwrap.  Use @code{\\override #'(line-width . @var{X})} to set
the line width, where @var{X} is the number of staff spaces.

@lilypond[verbatim,quote]
\\markup {
  \\wordwrap {
    Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed
    do eiusmod tempor incididunt ut labore et dolore magna aliqua.
    Ut enim ad minim veniam, quis nostrud exercitation ullamco
    laboris nisi ut aliquip ex ea commodo consequat.
  }
}
@end lilypond"
  (stack-lines DOWN 0.0 baseline-skip
               (wordwrap-internal-markup-list layout props #f args)))

(define-markup-list-command (wordwrap-string-internal layout props justify arg)
  (boolean? string?)
  #:properties ((line-width)
                (word-space)
                (text-direction RIGHT))
  "Internal markup list command used to define @code{\\justify-string} and
@code{\\wordwrap-string}."
  (let* ((para-strings (regexp-split
                        (string-regexp-substitute
                         "\r" "\n"
                         (string-regexp-substitute "\r\n" "\n" arg))
                        "\n[ \t\n]*\n[ \t\n]*"))
         (list-para-words (map (lambda (str)
                                 (regexp-split str "[ \t\n]+"))
                               para-strings))
         (para-lines (map (lambda (words)
                            (let* ((stencils
                                    (map (lambda (x)
                                           (interpret-markup layout props x))
                                         words)))
                              (wordwrap-stencils stencils
                                                 justify word-space
                                                 line-width text-direction)))
                          list-para-words)))
    (concatenate para-lines)))

(define-markup-command (wordwrap-string layout props arg)
  (string?)
  #:category align
  #:properties ((baseline-skip)
                wordwrap-string-internal-markup-list)
  "Wordwrap a string.  Paragraphs may be separated with double newlines.

@lilypond[verbatim,quote]
\\markup {
  \\override #'(line-width . 40)
  \\wordwrap-string #\"Lorem ipsum dolor sit amet, consectetur
      adipisicing elit, sed do eiusmod tempor incididunt ut labore
      et dolore magna aliqua.


      Ut enim ad minim veniam, quis nostrud exercitation ullamco
      laboris nisi ut aliquip ex ea commodo consequat.


      Excepteur sint occaecat cupidatat non proident, sunt in culpa
      qui officia deserunt mollit anim id est laborum\"
}
@end lilypond"
  (stack-lines DOWN 0.0 baseline-skip
               (wordwrap-string-internal-markup-list layout props #f arg)))

(define-markup-command (justify-string layout props arg)
  (string?)
  #:category align
  #:properties ((baseline-skip)
                wordwrap-string-internal-markup-list)
  "Justify a string.  Paragraphs may be separated with double newlines

@lilypond[verbatim,quote]
\\markup {
  \\override #'(line-width . 40)
  \\justify-string #\"Lorem ipsum dolor sit amet, consectetur
      adipisicing elit, sed do eiusmod tempor incididunt ut labore
      et dolore magna aliqua.


      Ut enim ad minim veniam, quis nostrud exercitation ullamco
      laboris nisi ut aliquip ex ea commodo consequat.


      Excepteur sint occaecat cupidatat non proident, sunt in culpa
      qui officia deserunt mollit anim id est laborum\"
}
@end lilypond"
  (stack-lines DOWN 0.0 baseline-skip
               (wordwrap-string-internal-markup-list layout props #t arg)))

(define-markup-command (wordwrap-field layout props symbol)
  (symbol?)
  #:category align
  "Wordwrap the data which has been assigned to @var{symbol}.

@lilypond[verbatim,quote]
\\header {
  title = \"My title\"
  myText = \"Lorem ipsum dolor sit amet, consectetur adipisicing
    elit, sed do eiusmod tempor incididunt ut labore et dolore
    magna aliqua.  Ut enim ad minim veniam, quis nostrud
    exercitation ullamco laboris nisi ut aliquip ex ea commodo
    consequat.\"
}

\\paper {
  bookTitleMarkup = \\markup {
    \\column {
      \\fill-line { \\fromproperty #'header:title }
      \\null
      \\wordwrap-field #'header:myText
    }
  }
}

\\markup {
  \\null
}
@end lilypond"
  (let* ((m (chain-assoc-get symbol props)))
    (if (string? m)
        (wordwrap-string-markup layout props m)
        empty-stencil)))

(define-markup-command (justify-field layout props symbol)
  (symbol?)
  #:category align
  "Justify the data which has been assigned to @var{symbol}.

@lilypond[verbatim,quote]
\\header {
  title = \"My title\"
  myText = \"Lorem ipsum dolor sit amet, consectetur adipisicing
    elit, sed do eiusmod tempor incididunt ut labore et dolore magna
    aliqua.  Ut enim ad minim veniam, quis nostrud exercitation ullamco
    laboris nisi ut aliquip ex ea commodo consequat.\"
}

\\paper {
  bookTitleMarkup = \\markup {
    \\column {
      \\fill-line { \\fromproperty #'header:title }
      \\null
      \\justify-field #'header:myText
    }
  }
}

\\markup {
  \\null
}
@end lilypond"
  (let* ((m (chain-assoc-get symbol props)))
    (if (string? m)
        (justify-string-markup layout props m)
        empty-stencil)))

(define-markup-command (combine layout props arg1 arg2)
  (markup? markup?)
  #:category align
  "
@cindex merging text

Print two markups on top of each other.

Note: @code{\\combine} cannot take a list of markups enclosed in
curly braces as an argument; the follow example will not compile:

@example
\\combine @{ a list @}
@end example

@lilypond[verbatim,quote]
\\markup {
  \\fontsize #5
  \\override #'(thickness . 2)
  \\combine
    \\draw-line #'(0 . 4)
    \\arrow-head #Y #DOWN ##f
}
@end lilypond"
  (let* ((s1 (interpret-markup layout props arg1))
         (s2 (interpret-markup layout props arg2)))
    (ly:stencil-add s1 s2)))

;;
;; TODO: should extract baseline-skip from each argument somehow..
;;
(define-markup-command (column layout props args)
  (markup-list?)
  #:category align
  #:properties ((baseline-skip))
  "
@cindex stacking text in a column

Stack the markups in @var{args} vertically.  The property
@code{baseline-skip} determines the space between markups
in @var{args}.

@lilypond[verbatim,quote]
\\markup {
  \\column {
    one
    two
    three
  }
}
@end lilypond"
  (let ((arg-stencils (interpret-markup-list layout props args)))
    (stack-lines -1 0.0 baseline-skip arg-stencils)))

(define-markup-command (dir-column layout props args)
  (markup-list?)
  #:category align
  #:properties ((direction)
                (baseline-skip))
  "
@cindex changing direction of text columns

Make a column of @var{args}, going up or down, depending on the
setting of the @code{direction} layout property.

@lilypond[verbatim,quote]
\\markup {
  \\override #`(direction . ,UP) {
    \\dir-column {
      going up
    }
  }
  \\hspace #1
  \\dir-column {
    going down
  }
  \\hspace #1
  \\override #'(direction . 1) {
    \\dir-column {
      going up
    }
  }
}
@end lilypond"
  (stack-lines (if (number? direction) direction -1)
               0.0
               baseline-skip
               (interpret-markup-list layout props args)))

(define (general-column align-dir baseline mols)
  "Stack @var{mols} vertically, aligned to  @var{align-dir} horizontally."

  (let* ((aligned-mols (map (lambda (x) (ly:stencil-aligned-to x X align-dir)) mols))
         (stacked-stencil (stack-lines -1 0.0 baseline aligned-mols))
         (stacked-extent (ly:stencil-extent stacked-stencil X)))
    (ly:stencil-translate-axis stacked-stencil (- (car stacked-extent)) X )))

(define-markup-command (center-column layout props args)
  (markup-list?)
  #:category align
  #:properties ((baseline-skip))
  "
@cindex centering a column of text

Put @code{args} in a centered column.

@lilypond[verbatim,quote]
\\markup {
  \\center-column {
    one
    two
    three
  }
}
@end lilypond"
  (general-column CENTER baseline-skip (interpret-markup-list layout props args)))

(define-markup-command (left-column layout props args)
  (markup-list?)
  #:category align
  #:properties ((baseline-skip))
  "
@cindex text columns, left-aligned

Put @code{args} in a left-aligned column.

@lilypond[verbatim,quote]
\\markup {
  \\left-column {
    one
    two
    three
  }
}
@end lilypond"
  (general-column LEFT baseline-skip (interpret-markup-list layout props args)))

(define-markup-command (right-column layout props args)
  (markup-list?)
  #:category align
  #:properties ((baseline-skip))
  "
@cindex text columns, right-aligned

Put @code{args} in a right-aligned column.

@lilypond[verbatim,quote]
\\markup {
  \\right-column {
    one
    two
    three
  }
}
@end lilypond"
  (general-column RIGHT baseline-skip (interpret-markup-list layout props args)))

(define-markup-command (vcenter layout props arg)
  (markup?)
  #:category align
  "
@cindex vertically centering text

Align @code{arg} to its Y@tie{}center.

@lilypond[verbatim,quote]
\\markup {
  one
  \\vcenter
  two
  three
}
@end lilypond"
  (let* ((mol (interpret-markup layout props arg)))
    (ly:stencil-aligned-to mol Y CENTER)))

(define-markup-command (center-align layout props arg)
  (markup?)
  #:category align
  "
@cindex horizontally centering text

Align @code{arg} to its X@tie{}center.

@lilypond[verbatim,quote]
\\markup {
  \\column {
    one
    \\center-align
    two
    three
  }
}
@end lilypond"
  (let* ((mol (interpret-markup layout props arg)))
    (ly:stencil-aligned-to mol X CENTER)))

(define-markup-command (right-align layout props arg)
  (markup?)
  #:category align
  "
@cindex right aligning text

Align @var{arg} on its right edge.

@lilypond[verbatim,quote]
\\markup {
  \\column {
    one
    \\right-align
    two
    three
  }
}
@end lilypond"
  (let* ((m (interpret-markup layout props arg)))
    (ly:stencil-aligned-to m X RIGHT)))

(define-markup-command (left-align layout props arg)
  (markup?)
  #:category align
  "
@cindex left aligning text

Align @var{arg} on its left edge.

@lilypond[verbatim,quote]
\\markup {
  \\column {
    one
    \\left-align
    two
    three
  }
}
@end lilypond"
  (let* ((m (interpret-markup layout props arg)))
    (ly:stencil-aligned-to m X LEFT)))

(define-markup-command (general-align layout props axis dir arg)
  (integer? number? markup?)
  #:category align
  "
@cindex controlling general text alignment

Align @var{arg} in @var{axis} direction to the @var{dir} side.

@lilypond[verbatim,quote]
\\markup {
  \\column {
    one
    \\general-align #X #LEFT
    two
    three
    \\null
    one
    \\general-align #X #CENTER
    two
    three
    \\null
    \\line {
      one
      \\general-align #Y #UP
      two
      three
    }
    \\null
    \\line {
      one
      \\general-align #Y #3.2
      two
      three
    }
  }
}
@end lilypond"
  (let* ((m (interpret-markup layout props arg)))
    (ly:stencil-aligned-to m axis dir)))

(define-markup-command (halign layout props dir arg)
  (number? markup?)
  #:category align
  "
@cindex setting horizontal text alignment

Set horizontal alignment.  If @var{dir} is @w{@code{-1}}, then it is
left-aligned, while @code{+1} is right.  Values in between interpolate
alignment accordingly.

@lilypond[verbatim,quote]
\\markup {
  \\column {
    one
    \\halign #LEFT
    two
    three
    \\null
    one
    \\halign #CENTER
    two
    three
    \\null
    one
    \\halign #RIGHT
    two
    three
    \\null
    one
    \\halign #-5
    two
    three
  }
}
@end lilypond"
  (let* ((m (interpret-markup layout props arg)))
    (ly:stencil-aligned-to m X dir)))

(define-markup-command (with-dimensions layout props x y arg)
  (number-pair? number-pair? markup?)
  #:category other
  "
@cindex setting extent of text objects

Set the dimensions of @var{arg} to @var{x} and@tie{}@var{y}."
  (let* ((expr (ly:stencil-expr (interpret-markup layout props arg))))
    (ly:stencil-add
     (make-transparent-box-stencil x y)
     (ly:make-stencil
      `(delay-stencil-evaluation ,(delay expr))
      x y))))

(define-markup-command (pad-around layout props amount arg)
  (number? markup?)
  #:category align
  "Add padding @var{amount} all around @var{arg}.

@lilypond[verbatim,quote]
\\markup {
  \\box {
    default
  }
  \\hspace #2
  \\box {
    \\pad-around #0.5 {
      padded
    }
  }
}
@end lilypond"
  (let* ((m (interpret-markup layout props arg))
         (x (interval-widen (ly:stencil-extent m X) amount))
         (y (interval-widen (ly:stencil-extent m Y) amount)))
    (ly:stencil-add (make-transparent-box-stencil x y)
                    m)))

(define-markup-command (pad-x layout props amount arg)
  (number? markup?)
  #:category align
  "
@cindex padding text horizontally

Add padding @var{amount} around @var{arg} in the X@tie{}direction.

@lilypond[verbatim,quote]
\\markup {
  \\box {
    default
  }
  \\hspace #4
  \\box {
    \\pad-x #2 {
      padded
    }
  }
}
@end lilypond"
  (let* ((m (interpret-markup layout props arg))
         (x (ly:stencil-extent m X))
         (y (ly:stencil-extent m Y)))
    (ly:make-stencil (ly:stencil-expr m)
                     (interval-widen x amount)
                     y)))

(define-markup-command (put-adjacent layout props axis dir arg1 arg2)
  (integer? ly:dir? markup? markup?)
  #:category align
  "Put @var{arg2} next to @var{arg1}, without moving @var{arg1}."
  (let ((m1 (interpret-markup layout props arg1))
        (m2 (interpret-markup layout props arg2)))
    (ly:stencil-combine-at-edge m1 axis dir m2 0.0)))

(define-markup-command (transparent layout props arg)
  (markup?)
  #:category other
  "Make @var{arg} transparent.

@lilypond[verbatim,quote]
\\markup {
  \\transparent {
    invisible text
  }
}
@end lilypond"
  (let* ((m (interpret-markup layout props arg))
         (x (ly:stencil-extent m X))
         (y (ly:stencil-extent m Y)))
    (ly:make-stencil (list 'transparent-stencil (ly:stencil-expr m)) x y)))

(define-markup-command (pad-to-box layout props x-ext y-ext arg)
  (number-pair? number-pair? markup?)
  #:category align
  "Make @var{arg} take at least @var{x-ext}, @var{y-ext} space.

@lilypond[verbatim,quote]
\\markup {
  \\box {
    default
  }
  \\hspace #4
  \\box {
    \\pad-to-box #'(0 . 10) #'(0 . 3) {
      padded
    }
  }
}
@end lilypond"
  (ly:stencil-add (make-transparent-box-stencil x-ext y-ext)
                  (interpret-markup layout props arg)))

(define-markup-command (hcenter-in layout props length arg)
  (number? markup?)
  #:category align
  "Center @var{arg} horizontally within a box of extending
@var{length}/2 to the left and right.

@lilypond[quote,verbatim]
\\new StaffGroup <<
  \\new Staff {
    \\set Staff.instrumentName = \\markup {
      \\hcenter-in #12
      Oboe
    }
    c''1
  }
  \\new Staff {
    \\set Staff.instrumentName = \\markup {
      \\hcenter-in #12
      Bassoon
    }
    \\clef tenor
    c'1
  }
>>
@end lilypond"
  (interpret-markup layout props
                    (make-pad-to-box-markup
                     (cons (/ length -2) (/ length 2))
                     '(0 . 0)
                     (make-center-align-markup arg))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; property
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-markup-command (property-recursive layout props symbol)
  (symbol?)
  #:category other
  "Print out a warning when a header field markup contains some recursive
markup definition."
  (ly:warning "Recursive definition of property ~a detected!" symbol)
  empty-stencil)

(define-markup-command (fromproperty layout props symbol)
  (symbol?)
  #:category other
  "Read the @var{symbol} from property settings, and produce a stencil
from the markup contained within.  If @var{symbol} is not defined, it
returns an empty markup.

@lilypond[verbatim,quote]
\\header {
  myTitle = \"myTitle\"
  title = \\markup {
    from
    \\italic
    \\fromproperty #'header:myTitle
  }
}
\\markup {
  \\null
}
@end lilypond"
  (let ((m (chain-assoc-get symbol props)))
    (if (markup? m)
        ;; prevent infinite loops by clearing the interpreted property:
        (interpret-markup layout (cons (list (cons symbol `(,property-recursive-markup ,symbol))) props) m)
        empty-stencil)))

(define-markup-command (on-the-fly layout props procedure arg)
  (procedure? markup?)
  #:category other
  "Apply the @var{procedure} markup command to @var{arg}.
@var{procedure} should take a single argument."
  (let ((anonymous-with-signature (lambda (layout props arg) (procedure layout props arg))))
    (set-object-property! anonymous-with-signature
                          'markup-signature
                          (list markup?))
    (interpret-markup layout props (list anonymous-with-signature arg))))

(define-markup-command (footnote layout props mkup note)
  (markup? markup?)
  #:category other
  "Have footnote @var{note} act as an annotation to the markup @var{mkup}.

@lilypond[verbatim,quote]
\\markup {
  \\auto-footnote a b
  \\override #'(padding . 0.2)
  \\auto-footnote c d
}
@end lilypond
The footnote will not be annotated automatically."
  (ly:stencil-combine-at-edge
   (interpret-markup layout props mkup)
   X
   RIGHT
   (ly:make-stencil
    `(footnote (gensym "footnote") #f ,(interpret-markup layout props note))
    '(0 . 0)
    '(0 . 0))
   0.0))

(define-markup-command (auto-footnote layout props mkup note)
  (markup? markup?)
  #:category other
  #:properties ((raise 0.5)
                (padding 0.0))
  "Have footnote @var{note} act as an annotation to the markup @var{mkup}.

@lilypond[verbatim,quote]
\\markup {
  \\auto-footnote a b
  \\override #'(padding . 0.2)
  \\auto-footnote c d
}
@end lilypond
The footnote will be annotated automatically."
  (let* ((markup-stencil (interpret-markup layout props mkup))
         (footnote-hash (gensym "footnote"))
         (stencil-seed 0)
         (gauge-stencil (interpret-markup
                         layout
                         props
                         ((ly:output-def-lookup
                           layout
                           'footnote-numbering-function)
                          stencil-seed)))
         (x-ext (ly:stencil-extent gauge-stencil X))
         (y-ext (ly:stencil-extent gauge-stencil Y))
         (footnote-number
          `(delay-stencil-evaluation
            ,(delay
               (ly:stencil-expr
                (let* ((table
                        (ly:output-def-lookup layout
                                              'number-footnote-table))
                       (footnote-stencil (if (list? table)
                                             (assoc-get footnote-hash
                                                        table)
                                             empty-stencil))
                       (footnote-stencil (if (ly:stencil? footnote-stencil)
                                             footnote-stencil
                                             (begin
                                               (ly:programming-error
                                                "Cannot find correct footnote for a markup object.")
                                               empty-stencil)))
                       (gap (- (interval-length x-ext)
                               (interval-length
                                (ly:stencil-extent footnote-stencil X))))
                       (y-trans (- (+ (cdr y-ext)
                                      raise)
                                   (cdr (ly:stencil-extent footnote-stencil
                                                           Y)))))
                  (ly:stencil-translate footnote-stencil
                                        (cons gap y-trans)))))))
         (main-stencil (ly:stencil-combine-at-edge
                        markup-stencil
                        X
                        RIGHT
                        (ly:make-stencil footnote-number x-ext y-ext)
                        padding)))
    (ly:stencil-add
     main-stencil
     (ly:make-stencil
      `(footnote ,footnote-hash #t ,(interpret-markup layout props note))
      '(0 . 0)
      '(0 . 0)))))

(define-markup-command (override layout props new-prop arg)
  (pair? markup?)
  #:category other
  "
@cindex overriding properties within text markup

Add the argument @var{new-prop} to the property list.  Properties
may be any property supported by @rinternals{font-interface},
@rinternals{text-interface} and
@rinternals{instrument-specific-markup-interface}.

@lilypond[verbatim,quote]
\\markup {
  \\line {
    \\column {
      default
      baseline-skip
    }
    \\hspace #2
    \\override #'(baseline-skip . 4) {
      \\column {
        increased
        baseline-skip
      }
    }
  }
}
@end lilypond"
  (interpret-markup layout (cons (list new-prop) props) arg))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; files
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-markup-command (verbatim-file layout props name)
  (string?)
  #:category other
  "Read the contents of file @var{name}, and include it verbatim.

@lilypond[verbatim,quote]
\\markup {
  \\verbatim-file #\"simple.ly\"
}
@end lilypond"
  (interpret-markup layout props
                    (if  (ly:get-option 'safe)
                         "verbatim-file disabled in safe mode"
                         (let* ((str (ly:gulp-file name))
                                (lines (string-split str #\nl)))
                           (make-typewriter-markup
                            (make-column-markup lines))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; fonts.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(define-markup-command (smaller layout props arg)
  (markup?)
  #:category font
  "Decrease the font size relative to the current setting.

@lilypond[verbatim,quote]
\\markup {
  \\fontsize #3.5 {
    some large text
    \\hspace #2
    \\smaller {
      a bit smaller
    }
    \\hspace #2
    more large text
  }
}
@end lilypond"
  (interpret-markup layout props
                    `(,fontsize-markup -1 ,arg)))

(define-markup-command (larger layout props arg)
  (markup?)
  #:category font
  "Increase the font size relative to the current setting.

@lilypond[verbatim,quote]
\\markup {
  default
  \\hspace #2
  \\larger
  larger
}
@end lilypond"
  (interpret-markup layout props
                    `(,fontsize-markup 1 ,arg)))

(define-markup-command (finger layout props arg)
  (markup?)
  #:category font
  "Set @var{arg} as small numbers.

@lilypond[verbatim,quote]
\\markup {
  \\finger {
    1 2 3 4 5
  }
}
@end lilypond"
  (interpret-markup layout
                    (cons '((font-size . -5) (font-encoding . fetaText)) props)
                    arg))

(define-markup-command (abs-fontsize layout props size arg)
  (number? markup?)
  #:category font
  "Use @var{size} as the absolute font size to display @var{arg}.
Adjusts @code{baseline-skip} and @code{word-space} accordingly.

@lilypond[verbatim,quote]
\\markup {
  default text font size
  \\hspace #2
  \\abs-fontsize #16 { text font size 16 }
  \\hspace #2
  \\abs-fontsize #12 { text font size 12 }
}
@end lilypond"
  (let* ((ref-size (ly:output-def-lookup layout 'text-font-size 12))
         (text-props (list (ly:output-def-lookup layout 'text-font-defaults)))
         (ref-word-space (chain-assoc-get 'word-space text-props 0.6))
         (ref-baseline (chain-assoc-get 'baseline-skip text-props 3))
         (magnification (/ size ref-size)))
    (interpret-markup
     layout
     (cons
      `((baseline-skip . ,(* magnification ref-baseline))
        (word-space . ,(* magnification ref-word-space))
        (font-size . ,(magnification->font-size magnification)))
      props)
     arg)))

(define-markup-command (fontsize layout props increment arg)
  (number? markup?)
  #:category font
  #:properties ((font-size 0)
                (word-space 1)
                (baseline-skip 2))
  "Add @var{increment} to the font-size.  Adjusts @code{baseline-skip}
accordingly.

@lilypond[verbatim,quote]
\\markup {
  default
  \\hspace #2
  \\fontsize #-1.5
  smaller
}
@end lilypond"
  (interpret-markup
   layout
   (cons
    `((baseline-skip . ,(* baseline-skip (magstep increment)))
      (word-space . ,(* word-space (magstep increment)))
      (font-size . ,(+ font-size increment)))
    props)
   arg))

(define-markup-command (magnify layout props sz arg)
  (number? markup?)
  #:category font
  "
@cindex magnifying text

Set the font magnification for its argument.  In the following
example, the middle@tie{}A is 10% larger:

@example
A \\magnify #1.1 @{ A @} A
@end example

Note: Magnification only works if a font name is explicitly selected.
Use @code{\\fontsize} otherwise.

@lilypond[verbatim,quote]
\\markup {
  default
  \\hspace #2
  \\magnify #1.5 {
    50% larger
  }
}
@end lilypond"
  (interpret-markup
   layout
   (prepend-alist-chain 'font-size (magnification->font-size sz) props)
   arg))

(define-markup-command (bold layout props arg)
  (markup?)
  #:category font
  "Switch to bold font-series.

@lilypond[verbatim,quote]
\\markup {
  default
  \\hspace #2
  \\bold
  bold
}
@end lilypond"
  (interpret-markup layout (prepend-alist-chain 'font-series 'bold props) arg))

(define-markup-command (sans layout props arg)
  (markup?)
  #:category font
  "Switch to the sans serif font family.

@lilypond[verbatim,quote]
\\markup {
  default
  \\hspace #2
  \\sans {
    sans serif
  }
}
@end lilypond"
  (interpret-markup layout (prepend-alist-chain 'font-family 'sans props) arg))

(define-markup-command (number layout props arg)
  (markup?)
  #:category font
  "Set font family to @code{number}, which yields the font used for
time signatures and fingerings.  This font contains numbers and
some punctuation; it has no letters.

@lilypond[verbatim,quote]
\\markup {
  \\number {
    0 1 2 3 4 5 6 7 8 9 . ,
  }
}
@end lilypond"
  (interpret-markup layout (prepend-alist-chain 'font-encoding 'fetaText props) arg))

(define-markup-command (roman layout props arg)
  (markup?)
  #:category font
  "Set font family to @code{roman}.

@lilypond[verbatim,quote]
\\markup {
  \\sans \\bold {
    sans serif, bold
    \\hspace #2
    \\roman {
      text in roman font family
    }
    \\hspace #2
    return to sans
  }
}
@end lilypond"
  (interpret-markup layout (prepend-alist-chain 'font-family 'roman props) arg))

(define-markup-command (huge layout props arg)
  (markup?)
  #:category font
  "Set font size to +2.

@lilypond[verbatim,quote]
\\markup {
  default
  \\hspace #2
  \\huge
  huge
}
@end lilypond"
  (interpret-markup layout (prepend-alist-chain 'font-size 2 props) arg))

(define-markup-command (large layout props arg)
  (markup?)
  #:category font
  "Set font size to +1.

@lilypond[verbatim,quote]
\\markup {
  default
  \\hspace #2
  \\large
  large
}
@end lilypond"
  (interpret-markup layout (prepend-alist-chain 'font-size 1 props) arg))

(define-markup-command (normalsize layout props arg)
  (markup?)
  #:category font
  "Set font size to default.

@lilypond[verbatim,quote]
\\markup {
  \\teeny {
    this is very small
    \\hspace #2
    \\normalsize {
      normal size
    }
    \\hspace #2
    teeny again
  }
}
@end lilypond"
  (interpret-markup layout (prepend-alist-chain 'font-size 0 props) arg))

(define-markup-command (small layout props arg)
  (markup?)
  #:category font
  "Set font size to -1.

@lilypond[verbatim,quote]
\\markup {
  default
  \\hspace #2
  \\small
  small
}
@end lilypond"
  (interpret-markup layout (prepend-alist-chain 'font-size -1 props) arg))

(define-markup-command (tiny layout props arg)
  (markup?)
  #:category font
  "Set font size to -2.

@lilypond[verbatim,quote]
\\markup {
  default
  \\hspace #2
  \\tiny
  tiny
}
@end lilypond"
  (interpret-markup layout (prepend-alist-chain 'font-size -2 props) arg))

(define-markup-command (teeny layout props arg)
  (markup?)
  #:category font
  "Set font size to -3.

@lilypond[verbatim,quote]
\\markup {
  default
  \\hspace #2
  \\teeny
  teeny
}
@end lilypond"
  (interpret-markup layout (prepend-alist-chain 'font-size -3 props) arg))

(define-markup-command (fontCaps layout props arg)
  (markup?)
  #:category font
  "Set @code{font-shape} to @code{caps}

Note: @code{\\fontCaps} requires the installation and selection of
fonts which support the @code{caps} font shape."
  (interpret-markup layout (prepend-alist-chain 'font-shape 'caps props) arg))

;; Poor man's caps
(define-markup-command (smallCaps layout props arg)
  (markup?)
  #:category font
  "Emit @var{arg} as small caps.

Note: @code{\\smallCaps} does not support accented characters.

@lilypond[verbatim,quote]
\\markup {
  default
  \\hspace #2
  \\smallCaps {
    Text in small caps
  }
}
@end lilypond"
  (define (char-list->markup chars lower)
    (let ((final-string (string-upcase (reverse-list->string chars))))
      (if lower
          (markup #:fontsize -2 final-string)
          final-string)))
  (define (make-small-caps rest-chars currents current-is-lower prev-result)
    (if (null? rest-chars)
        (make-concat-markup
         (reverse! (cons (char-list->markup currents current-is-lower)
                         prev-result)))
        (let* ((ch (car rest-chars))
               (is-lower (char-lower-case? ch)))
          (if (or (and current-is-lower is-lower)
                  (and (not current-is-lower) (not is-lower)))
              (make-small-caps (cdr rest-chars)
                               (cons ch currents)
                               is-lower
                               prev-result)
              (make-small-caps (cdr rest-chars)
                               (list ch)
                               is-lower
                               (if (null? currents)
                                   prev-result
                                   (cons (char-list->markup
                                          currents current-is-lower)
                                         prev-result)))))))
  (interpret-markup layout props
                    (if (string? arg)
                        (make-small-caps (string->list arg) (list) #f (list))
                        arg)))

(define-markup-command (caps layout props arg)
  (markup?)
  #:category font
  "Copy of the @code{\\smallCaps} command.

@lilypond[verbatim,quote]
\\markup {
  default
  \\hspace #2
  \\caps {
    Text in small caps
  }
}
@end lilypond"
  (interpret-markup layout props (make-smallCaps-markup arg)))

(define-markup-command (dynamic layout props arg)
  (markup?)
  #:category font
  "Use the dynamic font.  This font only contains @b{s}, @b{f}, @b{m},
@b{z}, @b{p}, and @b{r}.  When producing phrases, like
@q{pi@`{u}@tie{}@b{f}}, the normal words (like @q{pi@`{u}}) should be
done in a different font.  The recommended font for this is bold and italic.
@lilypond[verbatim,quote]
\\markup {
  \\dynamic {
    sfzp
  }
}
@end lilypond"
  (interpret-markup
   layout (prepend-alist-chain 'font-encoding 'fetaText props) arg))

(define-markup-command (text layout props arg)
  (markup?)
  #:category font
  "Use a text font instead of music symbol or music alphabet font.

@lilypond[verbatim,quote]
\\markup {
  \\number {
    1, 2,
    \\text {
      three, four,
    }
    5
  }
}
@end lilypond"

  ;; ugh - latin1
  (interpret-markup layout (prepend-alist-chain 'font-encoding 'latin1 props)
                    arg))

(define-markup-command (italic layout props arg)
  (markup?)
  #:category font
  "Use italic @code{font-shape} for @var{arg}.

@lilypond[verbatim,quote]
\\markup {
  default
  \\hspace #2
  \\italic
  italic
}
@end lilypond"
  (interpret-markup layout (prepend-alist-chain 'font-shape 'italic props) arg))

(define-markup-command (typewriter layout props arg)
  (markup?)
  #:category font
  "Use @code{font-family} typewriter for @var{arg}.

@lilypond[verbatim,quote]
\\markup {
  default
  \\hspace #2
  \\typewriter
  typewriter
}
@end lilypond"
  (interpret-markup
   layout (prepend-alist-chain 'font-family 'typewriter props) arg))

(define-markup-command (upright layout props arg)
  (markup?)
  #:category font
  "Set @code{font-shape} to @code{upright}.  This is the opposite
of @code{italic}.

@lilypond[verbatim,quote]
\\markup {
  \\italic {
    italic text
    \\hspace #2
    \\upright {
      upright text
    }
    \\hspace #2
    italic again
  }
}
@end lilypond"
  (interpret-markup
   layout (prepend-alist-chain 'font-shape 'upright props) arg))

(define-markup-command (medium layout props arg)
  (markup?)
  #:category font
  "Switch to medium font-series (in contrast to bold).

@lilypond[verbatim,quote]
\\markup {
  \\bold {
    some bold text
    \\hspace #2
    \\medium {
      medium font series
    }
    \\hspace #2
    bold again
  }
}
@end lilypond"
  (interpret-markup layout (prepend-alist-chain 'font-series 'medium props)
                    arg))

(define-markup-command (normal-text layout props arg)
  (markup?)
  #:category font
  "Set all font related properties (except the size) to get the default
normal text font, no matter what font was used earlier.

@lilypond[verbatim,quote]
\\markup {
  \\huge \\bold \\sans \\caps {
    huge bold sans caps
    \\hspace #2
    \\normal-text {
      huge normal
    }
    \\hspace #2
    as before
  }
}
@end lilypond"
  ;; ugh - latin1
  (interpret-markup layout
                    (cons '((font-family . roman) (font-shape . upright)
                            (font-series . medium) (font-encoding . latin1))
                          props)
                    arg))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; symbols.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-markup-command (musicglyph layout props glyph-name)
  (string?)
  #:category music
  "@var{glyph-name} is converted to a musical symbol; for example,
@code{\\musicglyph #\"accidentals.natural\"} selects the natural sign from
the music font.  See @ruser{The Feta font} for a complete listing of
the possible glyphs.

@lilypond[verbatim,quote]
\\markup {
  \\musicglyph #\"f\"
  \\musicglyph #\"rests.2\"
  \\musicglyph #\"clefs.G_change\"
}
@end lilypond"
  (let* ((font (ly:paper-get-font layout
                                  (cons '((font-encoding . fetaMusic)
                                          (font-name . #f))

                                        props)))
         (glyph (ly:font-get-glyph font glyph-name)))
    (if (null? (ly:stencil-expr glyph))
        (ly:warning (_ "Cannot find glyph ~a") glyph-name))

    glyph))

(define-markup-command (doublesharp layout props)
  ()
  #:category music
  "Draw a double sharp symbol.

@lilypond[verbatim,quote]
\\markup {
  \\doublesharp
}
@end lilypond"
  (interpret-markup layout props (markup #:musicglyph (assoc-get 1 standard-alteration-glyph-name-alist ""))))

(define-markup-command (sesquisharp layout props)
  ()
  #:category music
  "Draw a 3/2 sharp symbol.

@lilypond[verbatim,quote]
\\markup {
  \\sesquisharp
}
@end lilypond"
  (interpret-markup layout props (markup #:musicglyph (assoc-get 3/4 standard-alteration-glyph-name-alist ""))))

(define-markup-command (sharp layout props)
  ()
  #:category music
  "Draw a sharp symbol.

@lilypond[verbatim,quote]
\\markup {
  \\sharp
}
@end lilypond"
  (interpret-markup layout props (markup #:musicglyph (assoc-get 1/2 standard-alteration-glyph-name-alist ""))))

(define-markup-command (semisharp layout props)
  ()
  #:category music
  "Draw a semisharp symbol.

@lilypond[verbatim,quote]
\\markup {
  \\semisharp
}
@end lilypond"
  (interpret-markup layout props (markup #:musicglyph (assoc-get 1/4 standard-alteration-glyph-name-alist ""))))

(define-markup-command (natural layout props)
  ()
  #:category music
  "Draw a natural symbol.

@lilypond[verbatim,quote]
\\markup {
  \\natural
}
@end lilypond"
  (interpret-markup layout props (markup #:musicglyph (assoc-get 0 standard-alteration-glyph-name-alist ""))))

(define-markup-command (semiflat layout props)
  ()
  #:category music
  "Draw a semiflat symbol.

@lilypond[verbatim,quote]
\\markup {
  \\semiflat
}
@end lilypond"
  (interpret-markup layout props (markup #:musicglyph (assoc-get -1/4 standard-alteration-glyph-name-alist ""))))

(define-markup-command (flat layout props)
  ()
  #:category music
  "Draw a flat symbol.

@lilypond[verbatim,quote]
\\markup {
  \\flat
}
@end lilypond"
  (interpret-markup layout props (markup #:musicglyph (assoc-get -1/2 standard-alteration-glyph-name-alist ""))))

(define-markup-command (sesquiflat layout props)
  ()
  #:category music
  "Draw a 3/2 flat symbol.

@lilypond[verbatim,quote]
\\markup {
  \\sesquiflat
}
@end lilypond"
  (interpret-markup layout props (markup #:musicglyph (assoc-get -3/4 standard-alteration-glyph-name-alist ""))))

(define-markup-command (doubleflat layout props)
  ()
  #:category music
  "Draw a double flat symbol.

@lilypond[verbatim,quote]
\\markup {
  \\doubleflat
}
@end lilypond"
  (interpret-markup layout props (markup #:musicglyph (assoc-get -1 standard-alteration-glyph-name-alist ""))))

(define-markup-command (with-color layout props color arg)
  (color? markup?)
  #:category other
  "
@cindex coloring text

Draw @var{arg} in color specified by @var{color}.

@lilypond[verbatim,quote]
\\markup {
  \\with-color #red
  red
  \\hspace #2
  \\with-color #green
  green
  \\hspace #2
  \\with-color #blue
  blue
}
@end lilypond"
  (let ((stil (interpret-markup layout props arg)))
    (ly:make-stencil (list 'color color (ly:stencil-expr stil))
                     (ly:stencil-extent stil X)
                     (ly:stencil-extent stil Y))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; glyphs
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-markup-command (arrow-head layout props axis dir filled)
  (integer? ly:dir? boolean?)
  #:category graphic
  "Produce an arrow head in specified direction and axis.
Use the filled head if @var{filled} is specified.
@lilypond[verbatim,quote]
\\markup {
  \\fontsize #5 {
    \\general-align #Y #DOWN {
      \\arrow-head #Y #UP ##t
      \\arrow-head #Y #DOWN ##f
      \\hspace #2
      \\arrow-head #X #RIGHT ##f
      \\arrow-head #X #LEFT ##f
    }
  }
}
@end lilypond"
  (let*
      ((name (format #f "arrowheads.~a.~a~a"
                     (if filled
                         "close"
                         "open")
                     axis
                     dir)))
    (ly:font-get-glyph
     (ly:paper-get-font layout (cons '((font-encoding . fetaMusic))
                                     props))
     name)))

(define-markup-command (lookup layout props glyph-name)
  (string?)
  #:category other
  "Lookup a glyph by name.

@lilypond[verbatim,quote]
\\markup {
  \\override #'(font-encoding . fetaBraces) {
    \\lookup #\"brace200\"
    \\hspace #2
    \\rotate #180
    \\lookup #\"brace180\"
  }
}
@end lilypond"
  (ly:font-get-glyph (ly:paper-get-font layout props)
                     glyph-name))

(define-markup-command (char layout props num)
  (integer?)
  #:category other
  "Produce a single character.  Characters encoded in hexadecimal
format require the prefix @code{#x}.

@lilypond[verbatim,quote]
\\markup {
  \\char #65 \\char ##x00a9
}
@end lilypond"
  (ly:text-interface::interpret-markup layout props (ly:wide-char->utf-8 num)))

(define number->mark-letter-vector (make-vector 25 #\A))

(do ((i 0 (1+ i))
     (j 0 (1+ j)))
    ((>= i 26))
  (if (= i (- (char->integer #\I) (char->integer #\A)))
      (set! i (1+ i)))
  (vector-set! number->mark-letter-vector j
               (integer->char (+ i (char->integer #\A)))))

(define number->mark-alphabet-vector (list->vector
                                      (map (lambda (i) (integer->char (+ i (char->integer #\A)))) (iota 26))))

(define (number->markletter-string vec n)
  "Double letters for big marks."
  (let* ((lst (vector-length vec)))

    (if (>= n lst)
        (string-append (number->markletter-string vec (1- (quotient n lst)))
                       (number->markletter-string vec (remainder n lst)))
        (make-string 1 (vector-ref vec n)))))

(define-markup-command (markletter layout props num)
  (integer?)
  #:category other
  "Make a markup letter for @var{num}.  The letters start with A
to@tie{}Z (skipping letter@tie{}I), and continue with double letters.

@lilypond[verbatim,quote]
\\markup {
  \\markletter #8
  \\hspace #2
  \\markletter #26
}
@end lilypond"
  (ly:text-interface::interpret-markup layout props
                                       (number->markletter-string number->mark-letter-vector num)))

(define-markup-command (markalphabet layout props num)
  (integer?)
  #:category other
  "Make a markup letter for @var{num}.  The letters start with A to@tie{}Z
and continue with double letters.

@lilypond[verbatim,quote]
\\markup {
  \\markalphabet #8
  \\hspace #2
  \\markalphabet #26
}
@end lilypond"
  (ly:text-interface::interpret-markup layout props
                                       (number->markletter-string number->mark-alphabet-vector num)))

(define-public (horizontal-slash-interval num forward number-interval mag)
  (if forward
      (cond ;; ((= num 6) (interval-widen number-interval (* mag 0.5)))
       ;; ((= num 5) (interval-widen number-interval (* mag 0.5)))
       (else (interval-widen number-interval (* mag 0.25))))
      (cond ((= num 6) (interval-widen number-interval (* mag 0.5)))
            ;; ((= num 5) (interval-widen number-interval (* mag 0.5)))
            (else (interval-widen number-interval (* mag 0.25))))
      ))

(define-public (adjust-slash-stencil num forward stencil mag)
  (if forward
      (cond ((= num 2)
             (ly:stencil-translate stencil (cons (* mag -0.00) (* mag 0.2))))
            ((= num 3)
             (ly:stencil-translate stencil (cons (* mag -0.00) (* mag 0.2))))
            ;; ((= num 5)
            ;;     (ly:stencil-translate stencil (cons (* mag -0.00) (* mag -0.07))))
            ;; ((= num 7)
            ;;     (ly:stencil-translate stencil (cons (* mag -0.00) (* mag -0.15))))
            (else stencil))
      (cond ((= num 6)
             (ly:stencil-translate stencil (cons (* mag -0.00) (* mag 0.15))))
            ;; ((= num 8)
            ;;     (ly:stencil-translate stencil (cons (* mag -0.00) (* mag -0.15))))
            (else stencil))
      )
  )

(define (slashed-digit-internal layout props num forward font-size thickness)
  (let* ((mag (magstep font-size))
         (thickness (* mag
                       (ly:output-def-lookup layout 'line-thickness)
                       thickness))
         ;; backward slashes might use slope and point in the other direction!
         (dy (* mag (if forward 0.4 -0.4)))
         (number-stencil (interpret-markup layout
                                           (prepend-alist-chain 'font-encoding 'fetaText props)
                                           (number->string num)))
         (num-x (horizontal-slash-interval num forward (ly:stencil-extent number-stencil X) mag))
         (center (interval-center (ly:stencil-extent number-stencil Y)))
         ;; Use the real extents of the slash, not the whole number,
         ;; because we might translate the slash later on!
         (num-y (interval-widen (cons center center) (abs dy)))
         (is-sane (and (interval-sane? num-x) (interval-sane? num-y)))
         (slash-stencil (if is-sane
                            (make-line-stencil thickness
                                               (car num-x) (- (interval-center num-y) dy)
                                               (cdr num-x) (+ (interval-center num-y) dy))
                            #f)))
    (if (ly:stencil? slash-stencil)
        (begin
          ;; for some numbers we need to shift the slash/backslash up or
          ;; down to make the slashed digit look better
          (set! slash-stencil (adjust-slash-stencil num forward slash-stencil mag))
          (set! number-stencil
                (ly:stencil-add number-stencil slash-stencil)))
        (ly:warning "Unable to create slashed digit ~a" num))
    number-stencil))


(define-markup-command (slashed-digit layout props num)
  (integer?)
  #:category other
  #:properties ((font-size 0)
                (thickness 1.6))
  "
@cindex slashed digits

A feta number, with slash.  This is for use in the context of
figured bass notation.
@lilypond[verbatim,quote]
\\markup {
  \\slashed-digit #5
  \\hspace #2
  \\override #'(thickness . 3)
  \\slashed-digit #7
}
@end lilypond"
  (slashed-digit-internal layout props num #t font-size thickness))

(define-markup-command (backslashed-digit layout props num)
  (integer?)
  #:category other
  #:properties ((font-size 0)
                (thickness 1.6))
  "
@cindex backslashed digits

A feta number, with backslash.  This is for use in the context of
figured bass notation.
@lilypond[verbatim,quote]
\\markup {
  \\backslashed-digit #5
  \\hspace #2
  \\override #'(thickness . 3)
  \\backslashed-digit #7
}
@end lilypond"
  (slashed-digit-internal layout props num #f font-size thickness))

;; eyeglasses
(define eyeglassespath
  '((moveto 0.42 0.77)
    (rcurveto 0 0.304 -0.246 0.55 -0.55 0.55)
    (rcurveto -0.304 0 -0.55 -0.246 -0.55 -0.55)
    (rcurveto 0 -0.304 0.246 -0.55 0.55 -0.55)
    (rcurveto 0.304 0 0.55 0.246 0.55 0.55)
    (closepath)
    (moveto 2.07 0.77)
    (rcurveto 0 0.304 -0.246 0.55 -0.55 0.55)
    (rcurveto -0.304 0 -0.55 -0.246 -0.55 -0.55)
    (rcurveto 0 -0.304 0.246 -0.55 0.55 -0.55)
    (rcurveto 0.304 0 0.55 0.246 0.55 0.55)
    (closepath)
    (moveto 1.025 0.935)
    (rcurveto 0 0.182 -0.148 0.33 -0.33 0.33)
    (rcurveto -0.182 0 -0.33 -0.148 -0.33 -0.33)
    (moveto -0.68 0.77)
    (rlineto 0.66 1.43)
    (rcurveto 0.132 0.286 0.55 0.44 0.385 -0.33)
    (moveto 2.07 0.77)
    (rlineto 0.66 1.43)
    (rcurveto 0.132 0.286 0.55 0.44 0.385 -0.33)))

(define-markup-command (eyeglasses layout props)
  ()
  #:category other
  "Prints out eyeglasses, indicating strongly to look at the conductor.
@lilypond[verbatim,quote]
\\markup { \\eyeglasses }
@end lilypond"
  (interpret-markup layout props
                    (make-override-markup '(line-cap-style . butt)
                                          (make-path-markup 0.15 eyeglassespath))))

(define-markup-command (left-brace layout props size)
  (number?)
  #:category other
  "
A feta brace in point size @var{size}.

@lilypond[verbatim,quote]
\\markup {
  \\left-brace #35
  \\hspace #2
  \\left-brace #45
}
@end lilypond"
  (let* ((font (ly:paper-get-font layout
                                  (cons '((font-encoding . fetaBraces)
                                          (font-name . #f))
                                        props)))
         (glyph-count (1- (ly:otf-glyph-count font)))
         (scale (ly:output-def-lookup layout 'output-scale))
         (scaled-size (/ (ly:pt size) scale))
         (glyph (lambda (n)
                  (ly:font-get-glyph font (string-append "brace"
                                                         (number->string n)))))
         (get-y-from-brace (lambda (brace)
                             (interval-length
                              (ly:stencil-extent (glyph brace) Y))))
         (find-brace (binary-search 0 glyph-count get-y-from-brace scaled-size))
         (glyph-found (glyph find-brace)))

    (if (or (null? (ly:stencil-expr glyph-found))
            (< scaled-size (interval-length (ly:stencil-extent (glyph 0) Y)))
            (> scaled-size (interval-length
                            (ly:stencil-extent (glyph glyph-count) Y))))
        (begin
          (ly:warning (_ "no brace found for point size ~S ") size)
          (ly:warning (_ "defaulting to ~S pt")
                      (/ (* scale (interval-length
                                   (ly:stencil-extent glyph-found Y)))
                         (ly:pt 1)))))
    glyph-found))

(define-markup-command (right-brace layout props size)
  (number?)
  #:category other
  "
A feta brace in point size @var{size}, rotated 180 degrees.

@lilypond[verbatim,quote]
\\markup {
  \\right-brace #45
  \\hspace #2
  \\right-brace #35
}
@end lilypond"
  (interpret-markup layout props (markup #:rotate 180 #:left-brace size)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; the note command.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; TODO: better syntax.

(define-markup-command (note-by-number layout props log dot-count dir)
  (number? number? number?)
  #:category music
  #:properties ((font-size 0)
                (flag-style '())
                (style '()))
  "
@cindex notes within text by log and dot-count

Construct a note symbol, with stem and flag.  By using fractional values for
@var{dir}, longer or shorter stems can be obtained.
Supports all note-head-styles.
Supported flag-styles are @code{default}, @code{old-straight-flag},
@code{modern-straight-flag} and @code{flat-flag}.

@lilypond[verbatim,quote]
\\markup {
  \\note-by-number #3 #0 #DOWN
  \\hspace #2
  \\note-by-number #1 #2 #0.8
}
@end lilypond"
  (define (get-glyph-name-candidates dir log style)
    (map (lambda (dir-name)
           (format #f "noteheads.~a~a" dir-name
                   (if (and (symbol? style)
                            (not (equal? 'default style)))
                       (select-head-glyph style (min log 2))
                       (min log 2))))
         (list (if (= dir UP) "u" "d")
               "s")))

  (define (get-glyph-name font cands)
    (if (null? cands)
        ""
        (if (ly:stencil-empty? (ly:font-get-glyph font (car cands)))
            (get-glyph-name font (cdr cands))
            (car cands))))

  (define (buildflags flag-stencil remain curr-stencil spacing)
    ;; Function to recursively create a stencil with @code{remain} flags
    ;; from the single-flag stencil @code{curr-stencil}, which is already
    ;; translated to the position of the previous flag position.
    ;;
    ;; Copy and paste from /scm/flag-styles.scm
    (if (> remain 0)
        (let* ((translated-stencil
                (ly:stencil-translate-axis curr-stencil spacing Y))
               (new-stencil (ly:stencil-add flag-stencil translated-stencil)))
          (buildflags new-stencil (- remain 1) translated-stencil spacing))
        flag-stencil))

  (define (straight-flag-mrkp flag-thickness flag-spacing
                              upflag-angle upflag-length
                              downflag-angle downflag-length
                              dir)
    ;; Create a stencil for a straight flag.  @var{flag-thickness} and
    ;; @var{flag-spacing} are given in staff spaces, @var{upflag-angle} and
    ;; @var{downflag-angle} are given in degrees, and @var{upflag-length} and
    ;; @var{downflag-length} are given in staff spaces.
    ;;
    ;; All lengths are scaled according to the font size of the note.
    ;;
    ;; From /scm/flag-styles.scm, modified to fit here.

    (let* ((stem-up (> dir 0))
           ;; scale with the note size
           (factor (magstep font-size))
           (stem-thickness (* factor 0.1))
           (line-thickness (ly:output-def-lookup layout 'line-thickness))
           (half-stem-thickness (/ (* stem-thickness line-thickness) 2))
           (raw-length (if stem-up upflag-length downflag-length))
           (angle (if stem-up upflag-angle downflag-angle))
           (flag-length (+ (* raw-length factor) half-stem-thickness))
           (flag-end (if (= angle 0)
                         (cons flag-length (* half-stem-thickness dir))
                         (polar->rectangular flag-length angle)))
           (thickness (* flag-thickness factor))
           (thickness-offset (cons 0 (* -1 thickness dir)))
           (spacing (* -1 flag-spacing factor dir))
           (start (cons (- half-stem-thickness) (* half-stem-thickness dir)))
           ;; The points of a round-filled-polygon need to be given in
           ;; clockwise order, otherwise the polygon will be enlarged by
           ;; blot-size*2!
           (points (if stem-up
                       (list start
                             flag-end
                             (offset-add flag-end thickness-offset)
                             (offset-add start thickness-offset))
                       (list start
                             (offset-add start thickness-offset)
                             (offset-add flag-end thickness-offset)
                             flag-end)))
           (stencil (ly:round-filled-polygon points half-stem-thickness))
           ;; Log for 1/8 is 3, so we need to subtract 3
           (flag-stencil (buildflags stencil (- log 3) stencil spacing)))
      flag-stencil))

  (let* ((font (ly:paper-get-font layout (cons '((font-encoding . fetaMusic))
                                               props)))
         (size-factor (magstep font-size))
         (blot (ly:output-def-lookup layout 'blot-diameter))
         (head-glyph-name
          (let ((result (get-glyph-name font
                                        (get-glyph-name-candidates
                                         (sign dir) log style))))
            (if (string-null? result)
                ;; If no glyph name can be found, select default heads.
                ;; Though this usually means an unsupported style has been
                ;; chosen, it also prevents unrelated 'style settings from
                ;; other grobs (e.g., TextSpanner and TimeSignature) leaking
                ;; into markup.
                (get-glyph-name font
                                (get-glyph-name-candidates
                                 (sign dir) log 'default))
                result)))
         (head-glyph (ly:font-get-glyph font head-glyph-name))
         (ancient-flags? (or (eq? style 'mensural) (eq? style 'neomensural)))
         (attach-indices (ly:note-head::stem-attachment font head-glyph-name))
         (stem-length (* size-factor (max 3 (- log 1))))
         ;; With ancient-flags we want a tighter stem
         (stem-thickness (* size-factor (if ancient-flags? 0.1 0.13)))
         (stemy (* dir stem-length))
         (attach-off (cons (interval-index
                            (ly:stencil-extent head-glyph X)
                            (* (sign dir) (car attach-indices)))
                           ;; fixme, this is inconsistent between X & Y.
                           (* (sign dir)
                              (interval-index
                               (ly:stencil-extent head-glyph Y)
                               (cdr attach-indices)))))
         ;; For a tighter stem (with ancient-flags) the stem-width has to be
         ;; adjusted.
         (stem-X-corr (if ancient-flags? (* 0.5 dir stem-thickness) 0))
         (stem-glyph (and (> log 0)
                          (ly:round-filled-box
                           (ordered-cons (+ stem-X-corr (car attach-off))
                                         (+ stem-X-corr (car attach-off)
                                            (* (- (sign dir)) stem-thickness)))
                           (cons (min stemy (cdr attach-off))
                                 (max stemy (cdr attach-off)))
                           (/ stem-thickness 3))))
         (dot (ly:font-get-glyph font "dots.dot"))
         (dotwid (interval-length (ly:stencil-extent dot X)))
         (dots (and (> dot-count 0)
                    (apply ly:stencil-add
                           (map (lambda (x)
                                  (ly:stencil-translate-axis
                                   dot (* 2 x dotwid) X))
                                (iota dot-count)))))
         ;; Straight-flags. Values taken from /scm/flag-style.scm
         (modern-straight-flag (straight-flag-mrkp 0.55 1 -18 1.1 22 1.2 dir))
         (old-straight-flag (straight-flag-mrkp 0.55 1 -45 1.2 45 1.4 dir))
         (flat-flag (straight-flag-mrkp 0.55 1.0 0 1.0 0 1.0 dir))
         ;; Calculate a corrective to avoid a gap between
         ;; straight-flags and the stem.
         (flag-style-Y-corr (if (or (eq? flag-style 'modern-straight-flag)
                                    (eq? flag-style 'old-straight-flag)
                                    (eq? flag-style 'flat-flag))
                                (/ blot 10 (* -1 dir))
                                0))
         (flaggl (and (> log 2)
                      (ly:stencil-translate
                       (cond ((eq? flag-style 'modern-straight-flag)
                              modern-straight-flag)
                             ((eq? flag-style 'old-straight-flag)
                              old-straight-flag)
                             ((eq? flag-style 'flat-flag)
                              flat-flag)
                             (else
                              (ly:font-get-glyph font
                                                 (format #f (if ancient-flags?
                                                                "flags.mensural~a2~a"
                                                                "flags.~a~a")
                                                         (if (> dir 0) "u" "d")
                                                         log))))
                       (cons (+ (car attach-off)
                                ;; For tighter stems (with ancient-flags) the
                                ;; flag has to be adjusted different.
                                (if (and (not ancient-flags?) (< dir 0))
                                    stem-thickness
                                    0))
                             (+ stemy flag-style-Y-corr))))))

    ;; If there is a flag on an upstem and the stem is short, move the dots
    ;; to avoid the flag.  16th notes get a special case because their flags
    ;; hang lower than any other flags.
    ;; Not with ancient flags or straight-flags.
    (if (and dots (> dir 0) (> log 2)
             (or (eq? flag-style 'default) (null? flag-style))
             (not ancient-flags?)
             (or (< dir 1.15) (and (= log 4) (< dir 1.3))))
        (set! dots (ly:stencil-translate-axis dots 0.5 X)))
    (if flaggl
        (set! stem-glyph (ly:stencil-add flaggl stem-glyph)))
    (if (ly:stencil? stem-glyph)
        (set! stem-glyph (ly:stencil-add stem-glyph head-glyph))
        (set! stem-glyph head-glyph))
    (if (ly:stencil? dots)
        (set! stem-glyph
              (ly:stencil-add
               (ly:stencil-translate-axis
                dots
                (+ (cdr (ly:stencil-extent head-glyph X)) dotwid)
                X)
               stem-glyph)))
    stem-glyph))

(define-public log2
  (let ((divisor (log 2)))
    (lambda (z) (inexact->exact (/ (log z) divisor)))))

(define (parse-simple-duration duration-string)
  "Parse the `duration-string', e.g. ''4..'' or ''breve.'',
and return a (log dots) list."
  (let ((match (regexp-exec (make-regexp "(breve|longa|maxima|[0-9]+)(\\.*)")
                            duration-string)))
    (if (and match (string=? duration-string (match:substring match 0)))
        (let ((len (match:substring match 1))
              (dots (match:substring match 2)))
          (list (cond ((string=? len "breve") -1)
                      ((string=? len "longa") -2)
                      ((string=? len "maxima") -3)
                      (else (log2 (string->number len))))
                (if dots (string-length dots) 0)))
        (ly:error (_ "not a valid duration string: ~a") duration-string))))

(define-markup-command (note layout props duration dir)
  (string? number?)
  #:category music
  #:properties (note-by-number-markup)
  "
@cindex notes within text by string

This produces a note with a stem pointing in @var{dir} direction, with
the @var{duration} for the note head type and augmentation dots.  For
example, @code{\\note #\"4.\" #-0.75} creates a dotted quarter note, with
a shortened down stem.

@lilypond[verbatim,quote]
\\markup {
  \\override #'(style . cross) {
    \\note #\"4..\" #UP
  }
  \\hspace #2
  \\note #\"breve\" #0
}
@end lilypond"
  (let ((parsed (parse-simple-duration duration)))
    (note-by-number-markup layout props (car parsed) (cadr parsed) dir)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; the rest command.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-markup-command (rest-by-number layout props log dot-count)
  (number? number?)
  #:category music
  #:properties ((font-size 0)
                (style '())
                (multi-measure-rest #f))
  "
@cindex rests or multi-measure-rests within text by log and dot-count

A rest or multi-measure-rest symbol.

@lilypond[verbatim,quote]
\\markup {
  \\rest-by-number #3 #2
  \\hspace #2
  \\rest-by-number #0 #1
  \\hspace #2
  \\override #'(multi-measure-rest . #t)
  \\rest-by-number #0 #0
}
@end lilypond"

  (define (get-glyph-name-candidates log style)
    (let* (;; Choose the style-string to be added.
           ;; If no glyph exists, select others for the specified styles
           ;; otherwise defaulting.
           (style-strg
            (cond (
                   ;; 'baroque needs to be special-cased, otherwise
                   ;; `select-head-glyph´ would catch neomensural-glyphs for
                   ;; this style, if (< log 0).
                   (eq? style 'baroque)
                   (string-append (number->string log) ""))
                  ((eq? style 'petrucci)
                   (string-append (number->string log) "mensural"))
                  ;; In other cases `select-head-glyph´ from output-lib.scm
                  ;; works for rest-glyphs, too.
                  ((and (symbol? style) (not (eq? style 'default)))
                   (select-head-glyph style log))
                  (else log)))
           ;; Choose ledgered glyphs for whole and half rest.
           ;; Except for the specified styles, logs and MultiMeasureRests.
           (ledger-style-rests
            (if (and (or (list? style)
                         (not (member style
                                      '(neomensural mensural petrucci))))
                     (not multi-measure-rest)
                     (or (= log 0) (= log 1)))
                "o"
                "")))
      (format #f "rests.~a~a" style-strg ledger-style-rests)))

  (define (get-glyph-name font cands)
    (if (ly:stencil-empty? (ly:font-get-glyph font cands))
        ""
        cands))

  (let* ((font
          (ly:paper-get-font layout
                             (cons '((font-encoding . fetaMusic)) props)))
         (rest-glyph-name
          (let ((result
                 (get-glyph-name font
                                 (get-glyph-name-candidates log style))))
            (if (string-null? result)
                ;; If no glyph name can be found, select default rests.  Though
                ;; this usually means an unsupported style has been chosen, it
                ;; also prevents unrelated 'style settings from other grobs
                ;; (e.g., TextSpanner and TimeSignature) leaking into markup.
                (get-glyph-name font (get-glyph-name-candidates log 'default))
                result)))
         (rest-glyph (ly:font-get-glyph font rest-glyph-name))
         (dot (ly:font-get-glyph font "dots.dot"))
         (dot-width (interval-length (ly:stencil-extent dot X)))
         (dots (and (> dot-count 0)
                    (apply ly:stencil-add
                           (map (lambda (x)
                                  (ly:stencil-translate-axis
                                   dot (* 2 x dot-width) X))
                                (iota dot-count))))))

    ;; Apart from mensural-, neomensural- and petrucci-style ledgered
    ;; glyphs are taken for whole and half rests.
    ;; If they are dotted, move the dots in X-direction to avoid collision.
    (if (and dots
             (< log 2)
             (>= log 0)
             (not (member style '(neomensural mensural petrucci))))
        (set! dots (ly:stencil-translate-axis dots dot-width X)))

    ;; Add dots to the rest-glyph.
    ;;
    ;; Not sure how to vertical align dots.
    ;; For now the dots are centered for half, whole or longer rests.
    ;; Otherwise placed near the top of the rest.
    ;;
    ;; Dots for rests with (< log 0) dots are allowed, but not
    ;; if multi-measure-rest is set #t.
    (if (and (not multi-measure-rest) dots)
        (set! rest-glyph
              (ly:stencil-add
               (ly:stencil-translate
                dots
                (cons
                 (+ (cdr (ly:stencil-extent rest-glyph X)) dot-width)
                 (if (< log 2)
                     (interval-center (ly:stencil-extent rest-glyph Y))
                     (- (interval-end (ly:stencil-extent rest-glyph Y))
                        (/ (* 2 dot-width) 3)))))
               rest-glyph)))
    rest-glyph))

(define-markup-command (rest layout props duration)
  (string?)
  #:category music
  #:properties ((style '())
                (multi-measure-rest #f)
                (multi-measure-rest-number #t)
                (word-space 0.6))
  "
@cindex rests or multi-measure-rests within text by string

This produces a rest, with the @var{duration} for the rest type and
augmentation dots.
@code{\"breve\"}, @code{\"longa\"} and @code{\"maxima\"} are valid
input-strings.

Printing MultiMeasureRests could be enabled with
@code{\\override #'(multi-measure-rest . #t)}
If MultiMeasureRests are taken, the MultiMeasureRestNumber is printed above.
This is enabled for all styles using default-glyphs.
Could be disabled with @code{\\override #'(multi-measure-rest-number . #f)}

@lilypond[verbatim,quote]
\\markup {
  \\rest #\"4..\"
  \\hspace #2
  \\rest #\"breve\"
  \\hspace #2
  \\override #'(multi-measure-rest . #t)
  {
  \\rest #\"7\"
  \\hspace #2
  \\override #'(multi-measure-rest-number . #f)
  \\rest #\"7\"
  }
}
@end lilypond"
  ;; Get the number of mmr-glyphs.
  ;; Store them in a list.
  ;; example: (mmr-numbers 25) -> '(3 0 0 1)
  (define (mmr-numbers nmbr)
    (let* ((8-bar-glyph (floor (/ nmbr 8)))
           (8-remainder (remainder nmbr 8))
           (4-bar-glyph (floor (/ 8-remainder 4)))
           (4-remainder (remainder nmbr 4))
           (2-bar-glyph (floor (/ 4-remainder 2)))
           (2-remainder (remainder 4-remainder 2))
           (1-bar-glyph (floor (/ 2-remainder 1))))
      (list 8-bar-glyph 4-bar-glyph 2-bar-glyph 1-bar-glyph)))

  ;; Get the correct mmr-glyphs.
  ;; Store them in a list.
  ;; example:
  ;; (get-mmr-glyphs '(1 0 1 0) '("rests.M3" "rests.M2" "rests.M1" "rests.0"))
  ;; -> ("rests.M3" "rests.M1")
  (define (get-mmr-glyphs lst1 lst2)
    (define (helper l1 l2 l3)
      (if (null? l1)
          (reverse l3)
          (helper (cdr l1)
                  (cdr l2)
                  (append (make-list (car l1) (car l2)) l3))))
    (helper lst1 lst2 '()))

  ;; If duration is not valid, print a warning and return empty-stencil
  (if (or (and (not (integer? (car (parse-simple-duration duration))))
               (not multi-measure-rest))
          (and (= (string-length (car (string-split duration #\. ))) 1)
               (= (string->number (car (string-split duration #\. ))) 0)))
      (begin
        (ly:warning (_ "not a valid duration string: ~a - ignoring") duration)
        empty-stencil)
      (let* (
             ;; For simple rests:
             ;; Get a (log dots) list.
             (parsed (parse-simple-duration duration))
             ;; Create the rest-stencil
             (stil
              (rest-by-number-markup layout props (car parsed) (cadr parsed)))
             ;; For MultiMeasureRests:
             ;; Get the duration-part of duration
             (dur-part-string (car (string-split duration #\. )))
             ;; Get the duration of MMR:
             ;; If not a number (eg. "maxima") calculate it.
             (mmr-duration
              (or (string->number dur-part-string) (expt 2 (abs (car parsed)))))
             ;; Get a list of the correct number of each mmr-glyph.
             (count-mmr-glyphs-list (mmr-numbers mmr-duration))
             ;; Create a list of mmr-stencils,
             ;; translating the glyph for a whole rest.
             (mmr-stils-list
              (map
               (lambda (x)
                 (let ((single-mmr-stil
                        (rest-by-number-markup layout props (* -1 x) 0)))
                   (if (= x 0)
                       (ly:stencil-translate-axis
                        single-mmr-stil
                        ;; Ugh, hard-coded, why 1?
                        1
                        Y)
                       single-mmr-stil)))
               (get-mmr-glyphs count-mmr-glyphs-list (reverse (iota 4)))))
             ;; Adjust the space between the mmr-glyphs,
             ;; if not default-glyphs are used.
             (word-space (if (member style
                                     '(neomensural mensural petrucci))
                             (/ (* word-space 2) 3)
                             word-space))
             ;; Create the final mmr-stencil
             ;; via `stack-stencil-line´ from /scm/markup.scm
             (mmr-stil (stack-stencil-line word-space mmr-stils-list)))

        ;; Print the number above a multi-measure-rest
        ;; Depends on duration, style and multi-measure-rest-number set #t
        (if (and multi-measure-rest
                 multi-measure-rest-number
                 (> mmr-duration 1)
                 (not (member style '(neomensural mensural petrucci))))
            (let* ((mmr-stil-x-center
                    (interval-center (ly:stencil-extent mmr-stil X)))
                   (duration-markup
                    (markup
                     #:fontsize -2
                     #:override '(font-encoding . fetaText)
                     (number->string mmr-duration)))
                   (mmr-number-stil
                    (interpret-markup layout props duration-markup))
                   (mmr-number-stil-x-center
                    (interval-center (ly:stencil-extent mmr-number-stil X))))

              (set! mmr-stil (ly:stencil-combine-at-edge
                              mmr-stil
                              Y UP
                              (ly:stencil-translate-axis
                               mmr-number-stil
                               (- mmr-stil-x-center mmr-number-stil-x-center)
                               X)
                              ;; Ugh, hardcoded
                              0.8))))
        (if multi-measure-rest
            mmr-stil
            stil))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; fermata markup
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-markup-command (fermata layout props) ()
  #:category music
  #:properties ((direction UP))
  "Create a fermata glyph.  When @var{direction} is @code{DOWN}, use
an inverted glyph.  Note that within music, one would usually use the
@code{\\fermata} articulation instead of a markup.

@lilypond[verbatim,quote]
 { c1^\\markup \\fermata d1_\\markup \\fermata }

\\markup { \\fermata \\override #`(direction . ,DOWN) \\fermata }
@end lilypond
"
  (interpret-markup layout props
                    (if (eqv? direction DOWN)
                        (markup #:musicglyph "scripts.dfermata")
                        (markup #:musicglyph "scripts.ufermata"))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; translating.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-markup-command (lower layout props amount arg)
  (number? markup?)
  #:category align
  "
@cindex lowering text

Lower @var{arg} by the distance @var{amount}.
A negative @var{amount} indicates raising; see also @code{\\raise}.

@lilypond[verbatim,quote]
\\markup {
  one
  \\lower #3
  two
  three
}
@end lilypond"
  (ly:stencil-translate-axis (interpret-markup layout props arg)
                             (- amount) Y))

(define-markup-command (translate-scaled layout props offset arg)
  (number-pair? markup?)
  #:category align
  #:properties ((font-size 0))
  "
@cindex translating text
@cindex scaling text

Translate @var{arg} by @var{offset}, scaling the offset by the
@code{font-size}.

@lilypond[verbatim,quote]
\\markup {
  \\fontsize #5 {
    * \\translate #'(2 . 3) translate
    \\hspace #2
    * \\translate-scaled #'(2 . 3) translate-scaled
  }
}
@end lilypond"
  (let* ((factor (magstep font-size))
         (scaled (cons (* factor (car offset))
                       (* factor (cdr offset)))))
    (ly:stencil-translate (interpret-markup layout props arg)
                          scaled)))

(define-markup-command (raise layout props amount arg)
  (number? markup?)
  #:category align
  "
@cindex raising text

Raise @var{arg} by the distance @var{amount}.
A negative @var{amount} indicates lowering, see also @code{\\lower}.

The argument to @code{\\raise} is the vertical displacement amount,
measured in (global) staff spaces.  @code{\\raise} and @code{\\super}
raise objects in relation to their surrounding markups.

If the text object itself is positioned above or below the staff, then
@code{\\raise} cannot be used to move it, since the mechanism that
positions it next to the staff cancels any shift made with
@code{\\raise}.  For vertical positioning, use the @code{padding}
and/or @code{extra-offset} properties.

@lilypond[verbatim,quote]
\\markup {
  C
  \\small
  \\bold
  \\raise #1.0
  9/7+
}
@end lilypond"
  (ly:stencil-translate-axis (interpret-markup layout props arg) amount Y))

(define-markup-command (fraction layout props arg1 arg2)
  (markup? markup?)
  #:category other
  #:properties ((font-size 0))
  "
@cindex creating text fractions

Make a fraction of two markups.
@lilypond[verbatim,quote]
\\markup {
  π ≈
  \\fraction 355 113
}
@end lilypond"
  (let* ((m1 (interpret-markup layout props arg1))
         (m2 (interpret-markup layout props arg2))
         (factor (magstep font-size))
         (boxdimen (cons (* factor -0.05) (* factor 0.05)))
         (padding (* factor 0.2))
         (baseline (* factor 0.6))
         (offset (* factor 0.75)))
    (set! m1 (ly:stencil-aligned-to m1 X CENTER))
    (set! m2 (ly:stencil-aligned-to m2 X CENTER))
    (let* ((x1 (ly:stencil-extent m1 X))
           (x2 (ly:stencil-extent m2 X))
           (line (ly:round-filled-box (interval-union x1 x2) boxdimen 0.0))
           ;; should stack mols separately, to maintain LINE on baseline
           (stack (stack-lines DOWN padding baseline (list m1 line m2))))
      (set! stack
            (ly:stencil-aligned-to stack Y CENTER))
      (set! stack
            (ly:stencil-aligned-to stack X LEFT))
      ;; should have EX dimension
      ;; empirical anyway
      (ly:stencil-translate-axis stack offset Y))))

(define-markup-command (normal-size-super layout props arg)
  (markup?)
  #:category font
  #:properties ((baseline-skip))
  "
@cindex setting superscript in standard font size

Set @var{arg} in superscript with a normal font size.

@lilypond[verbatim,quote]
\\markup {
  default
  \\normal-size-super {
    superscript in standard size
  }
}
@end lilypond"
  (ly:stencil-translate-axis
   (interpret-markup layout props arg)
   (* 0.5 baseline-skip) Y))

(define-markup-command (super layout props arg)
  (markup?)
  #:category font
  #:properties ((font-size 0)
                (baseline-skip))
  "
@cindex superscript text

Set @var{arg} in superscript.

@lilypond[verbatim,quote]
\\markup {
  E =
  \\concat {
    mc
    \\super
    2
  }
}
@end lilypond"
  (ly:stencil-translate-axis
   (interpret-markup
    layout
    (cons `((font-size . ,(- font-size 3))) props)
    arg)
   (* 0.5 baseline-skip)
   Y))

(define-markup-command (translate layout props offset arg)
  (number-pair? markup?)
  #:category align
  "
@cindex translating text

Translate @var{arg} relative to its surroundings.  @var{offset}
is a pair of numbers representing the displacement in the X and Y axis.

@lilypond[verbatim,quote]
\\markup {
  *
  \\translate #'(2 . 3)
  \\line { translated two spaces right, three up }
}
@end lilypond"
  (ly:stencil-translate (interpret-markup layout props arg)
                        offset))

(define-markup-command (sub layout props arg)
  (markup?)
  #:category font
  #:properties ((font-size 0)
                (baseline-skip))
  "
@cindex subscript text

Set @var{arg} in subscript.

@lilypond[verbatim,quote]
\\markup {
  \\concat {
    H
    \\sub {
      2
    }
    O
  }
}
@end lilypond"
  (ly:stencil-translate-axis
   (interpret-markup
    layout
    (cons `((font-size . ,(- font-size 3))) props)
    arg)
   (* -0.5 baseline-skip)
   Y))

(define-markup-command (normal-size-sub layout props arg)
  (markup?)
  #:category font
  #:properties ((baseline-skip))
  "
@cindex setting subscript in standard font size

Set @var{arg} in subscript with a normal font size.

@lilypond[verbatim,quote]
\\markup {
  default
  \\normal-size-sub {
    subscript in standard size
  }
}
@end lilypond"
  (ly:stencil-translate-axis
   (interpret-markup layout props arg)
   (* -0.5 baseline-skip)
   Y))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; brackets.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-markup-command (hbracket layout props arg)
  (markup?)
  #:category graphic
  "
@cindex placing horizontal brackets around text

Draw horizontal brackets around @var{arg}.

@lilypond[verbatim,quote]
\\markup {
  \\hbracket {
    \\line {
      one two three
    }
  }
}
@end lilypond"
  (let ((th 0.1) ;; todo: take from GROB.
        (m (interpret-markup layout props arg)))
    (bracketify-stencil m X th (* 2.5 th) th)))

(define-markup-command (bracket layout props arg)
  (markup?)
  #:category graphic
  "
@cindex placing vertical brackets around text

Draw vertical brackets around @var{arg}.

@lilypond[verbatim,quote]
\\markup {
  \\bracket {
    \\note #\"2.\" #UP
  }
}
@end lilypond"
  (let ((th 0.1) ;; todo: take from GROB.
        (m (interpret-markup layout props arg)))
    (bracketify-stencil m Y th (* 2.5 th) th)))

(define-markup-command (parenthesize layout props arg)
  (markup?)
  #:category graphic
  #:properties ((angularity 0)
                (padding)
                (size 1)
                (thickness 1)
                (width 0.25))
  "
@cindex placing parentheses around text

Draw parentheses around @var{arg}.  This is useful for parenthesizing
a column containing several lines of text.

@lilypond[verbatim,quote]
\\markup {
  \\line {
    \\parenthesize {
      \\column {
        foo
        bar
      }
    }
    \\override #'(angularity . 2) {
      \\parenthesize {
        \\column {
          bah
          baz
        }
      }
    }
  }
}
@end lilypond"
  (let* ((markup (interpret-markup layout props arg))
         (scaled-width (* size width))
         (scaled-thickness
          (* (chain-assoc-get 'line-thickness props 0.1)
             thickness))
         (half-thickness
          (min (* size 0.5 scaled-thickness)
               (* (/ 4 3.0) scaled-width)))
         (padding (chain-assoc-get 'padding props half-thickness)))
    (parenthesize-stencil
     markup half-thickness scaled-width angularity padding)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Delayed markup evaluation
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-markup-command (page-ref layout props label gauge default)
  (symbol? markup? markup?)
  #:category other
  "
@cindex referencing page numbers in text

Reference to a page number.  @var{label} is the label set on the referenced
page (using the @code{\\label} command), @var{gauge} a markup used to estimate
the maximum width of the page number, and @var{default} the value to display
when @var{label} is not found."
  (let* ((gauge-stencil (interpret-markup layout props gauge))
         (x-ext (ly:stencil-extent gauge-stencil X))
         (y-ext (ly:stencil-extent gauge-stencil Y)))
   (ly:stencil-add
    (make-transparent-box-stencil x-ext y-ext))
    (ly:make-stencil
     `(delay-stencil-evaluation
       ,(delay (ly:stencil-expr
                (let* ((table (ly:output-def-lookup layout 'label-page-table))
                       (page-number (if (list? table)
                                        (assoc-get label table)
                                        #f))
                       (page-markup (if page-number (format #f "~a" page-number) default))
                       (page-stencil (interpret-markup layout props page-markup))
                       (gap (- (interval-length x-ext)
                               (interval-length (ly:stencil-extent page-stencil X)))))
                  (interpret-markup layout props
                                    (markup #:hspace gap page-markup))))))
     x-ext
     y-ext)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; scaling
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-markup-command (scale layout props factor-pair arg)
  (number-pair? markup?)
  #:category graphic
  "
@cindex scaling markup
@cindex mirroring markup

Scale @var{arg}.  @var{factor-pair} is a pair of numbers
representing the scaling-factor in the X and Y axes.
Negative values may be used to produce mirror images.

@lilypond[verbatim,quote]
\\markup {
  \\line {
    \\scale #'(2 . 1)
    stretched
    \\scale #'(1 . -1)
    mirrored
  }
}
@end lilypond"
  (let ((stil (interpret-markup layout props arg))
        (sx (car factor-pair))
        (sy (cdr factor-pair)))
    (ly:stencil-scale stil sx sy)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Repeating
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-markup-command (pattern layout props count axis space pattern)
  (integer? integer? number? markup?)
  #:category other
  "
Prints @var{count} times a @var{pattern} markup.
Patterns are spaced apart by @var{space}.
Patterns are distributed on @var{axis}.

@lilypond[verbatim, quote]
\\markup \\column {
  \"Horizontally repeated :\"
  \\pattern #7 #X #2 \\flat
  \\null
  \"Vertically repeated :\"
  \\pattern #3 #Y #0.5 \\flat
}
@end lilypond"
  (let ((pattern-width (interval-length
                        (ly:stencil-extent (interpret-markup layout props pattern) X)))
        (new-props (prepend-alist-chain 'word-space 0 (prepend-alist-chain 'baseline-skip 0 props))))
    (let loop ((i (1- count)) (patterns (markup)))
      (if (zero? i)
          (interpret-markup
           layout
           new-props
           (if (= axis X)
               (markup patterns pattern)
               (markup #:column (patterns pattern))))
          (loop (1- i)
                (if (= axis X)
                    (markup patterns pattern #:hspace space)
                    (markup #:column (patterns pattern #:vspace space))))))))

(define-markup-command (fill-with-pattern layout props space dir pattern left right)
  (number? ly:dir? markup? markup? markup?)
  #:category align
  #:properties ((word-space)
                (line-width))
  "
Put @var{left} and @var{right} in a horizontal line of width @code{line-width}
with a line of markups @var{pattern} in between.
Patterns are spaced apart by @var{space}.
Patterns are aligned to the @var{dir} markup.

@lilypond[verbatim, quote]
\\markup \\column {
  \"right-aligned :\"
  \\fill-with-pattern #1 #RIGHT . first right
  \\fill-with-pattern #1 #RIGHT . second right
  \\null
  \"center-aligned :\"
  \\fill-with-pattern #1.5 #CENTER - left right
  \\null
  \"left-aligned :\"
  \\override #'(line-width . 50)
  \\fill-with-pattern #2 #LEFT : left first
  \\override #'(line-width . 50)
  \\fill-with-pattern #2 #LEFT : left second
}
@end lilypond"
  (let* ((pattern-x-extent (ly:stencil-extent (interpret-markup layout props pattern) X))
         (pattern-width (interval-length pattern-x-extent))
         (left-width (interval-length (ly:stencil-extent (interpret-markup layout props left) X)))
         (right-width (interval-length (ly:stencil-extent (interpret-markup layout props right) X)))
         (middle-width (max 0 (- line-width (+ (+ left-width right-width) (* word-space 2)))))
         (period (+ space pattern-width))
         (count (truncate (/ (- middle-width pattern-width) period)))
         (x-offset (+ (* (- (- middle-width (* count period)) pattern-width) (/ (1+ dir) 2)) (abs (car pattern-x-extent)))))
    (interpret-markup layout props
                      (markup left
                              #:with-dimensions (cons 0 middle-width) '(0 . 0)
                              #:translate (cons x-offset 0)
                              #:pattern (1+ count) X space pattern
                              right))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Replacements
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-markup-command (replace layout props replacements arg)
  (list? markup?)
  #:category font
  "
Used to automatically replace a string by another in the markup @var{arg}.
Each pair of the alist @var{replacements} specifies what should be replaced.
The @code{key} is the string to be replaced by the @code{value} string.

@lilypond[verbatim, quote]
\\markup \\replace #'((\"thx\" . \"Thanks!\")) thx
@end lilypond"
  (interpret-markup
   layout
   (internal-add-text-replacements
    props
    replacements)
   (markup arg)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Markup list commands
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (space-lines baseline stils)
  (let space-stil ((stils stils)
                   (result (list)))
    (if (null? stils)
        (reverse! result)
        (let* ((stil (car stils))
               (dy-top (max (- (/ baseline 1.5)
                               (interval-bound (ly:stencil-extent stil Y) UP))
                            0.0))
               (dy-bottom (max (+ (/ baseline 3.0)
                                  (interval-bound (ly:stencil-extent stil Y) DOWN))
                               0.0))
               (new-stil (ly:make-stencil
                          (ly:stencil-expr stil)
                          (ly:stencil-extent stil X)
                          (cons (- (interval-bound (ly:stencil-extent stil Y) DOWN)
                                   dy-bottom)
                                (+ (interval-bound (ly:stencil-extent stil Y) UP)
                                   dy-top)))))
          (space-stil (cdr stils) (cons new-stil result))))))

(define-markup-list-command (justified-lines layout props args)
  (markup-list?)
  #:properties ((baseline-skip)
                wordwrap-internal-markup-list)
  "
@cindex justifying lines of text

Like @code{\\justify}, but return a list of lines instead of a single markup.
Use @code{\\override-lines #'(line-width . @var{X})} to set the line width;
@var{X}@tie{}is the number of staff spaces."
  (space-lines baseline-skip
               (interpret-markup-list layout props
                                      (make-wordwrap-internal-markup-list #t args))))

(define-markup-list-command (wordwrap-lines layout props args)
  (markup-list?)
  #:properties ((baseline-skip)
                wordwrap-internal-markup-list)
  "Like @code{\\wordwrap}, but return a list of lines instead of a single markup.
Use @code{\\override-lines #'(line-width . @var{X})} to set the line width,
where @var{X} is the number of staff spaces."
  (space-lines baseline-skip
               (interpret-markup-list layout props
                                      (make-wordwrap-internal-markup-list #f args))))

(define-markup-list-command (column-lines layout props args)
  (markup-list?)
  #:properties ((baseline-skip))
  "Like @code{\\column}, but return a list of lines instead of a single markup.
@code{baseline-skip} determines the space between each markup in @var{args}."
  (space-lines baseline-skip
               (interpret-markup-list layout props args)))

(define-markup-list-command (override-lines layout props new-prop args)
  (pair? markup-list?)
  "Like @code{\\override}, for markup lists."
  (interpret-markup-list layout (cons (list new-prop) props) args))

(define-markup-list-command (map-markup-commands layout props compose args)
  (procedure? markup-list?)
  "This applies the function @var{compose} to every markup in
@var{args} (including elements of markup list command calls) in order
to produce a new markup list.  Since the return value from a markup
list command call is not a markup list but rather a list of stencils,
this requires passing those stencils off as the results of individual
markup calls.  That way, the results should work out as long as no
markups rely on side effects."
  (let ((key (make-symbol "key")))
    (catch
     key
     (lambda ()
       ;; if `compose' does not actually interpret its markup
       ;; argument, we still need to return a list of stencils,
       ;; created from the single returned stencil
       (list
        (interpret-markup layout props
                          (compose
                           (make-on-the-fly-markup
                            (lambda (layout props m)
                              ;; here all effects of `compose' on the
                              ;; properties should be visible, so we
                              ;; call interpret-markup-list at this
                              ;; point of time and harvest its
                              ;; stencils
                              (throw key
                                     (interpret-markup-list
                                      layout props args)))
                            (make-null-markup))))))
     (lambda (key stencils)
       (map
        (lambda (sten)
          (interpret-markup layout props
                            (compose (make-stencil-markup sten))))
        stencils)))))
