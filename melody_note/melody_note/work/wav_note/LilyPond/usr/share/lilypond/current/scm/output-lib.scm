;;;; This file is part of LilyPond, the GNU music typesetter.
;;;;
;;;; Copyright (C) 1998--2012 Jan Nieuwenhuizen <janneke@gnu.org>
;;;; Han-Wen Nienhuys <hanwen@xs4all.nl>
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


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; general

(define-public (grob::has-interface grob iface)
  (memq iface (ly:grob-interfaces grob)))

(define-public (grob::is-live? grob)
  (pair? (ly:grob-basic-properties grob)))

(define-public (make-stencil-boxer thickness padding callback)
  "Return function that adds a box around the grob passed as argument."
  (lambda (grob)
    (box-stencil (callback grob) thickness padding)))

(define-public (make-stencil-circler thickness padding callback)
  "Return function that adds a circle around the grob passed as argument."
  (lambda (grob)
    (circle-stencil (callback grob) thickness padding)))

(define-public (print-circled-text-callback grob)
  (grob-interpret-markup grob (make-circle-markup
                               (ly:grob-property grob 'text))))

(define-public (event-cause grob)
  (let ((cause (ly:grob-property  grob 'cause)))

    (cond
     ((ly:stream-event? cause) cause)
     ((ly:grob? cause) (event-cause cause))
     (else #f))))

(define-public (grob-interpret-markup grob text)
  (let* ((layout (ly:grob-layout grob))
         (defs (ly:output-def-lookup layout 'text-font-defaults))
         (props (ly:grob-alist-chain grob defs)))

    (ly:text-interface::interpret-markup layout props text)))

(define-public (grob::unpure-Y-extent-from-stencil pure-function)
  "The unpure height will come from a stencil whereas the pure
   height will come from @code{pure-function}."
  (ly:make-unpure-pure-container ly:grob::stencil-height pure-function))

(define-public grob::unpure-horizontal-skylines-from-stencil
  (ly:make-unpure-pure-container
   ly:grob::horizontal-skylines-from-stencil
   ly:grob::pure-simple-horizontal-skylines-from-extents))

(define-public grob::always-horizontal-skylines-from-stencil
  (ly:make-unpure-pure-container
   ly:grob::horizontal-skylines-from-stencil))

(define-public grob::unpure-vertical-skylines-from-stencil
  (ly:make-unpure-pure-container
   ly:grob::vertical-skylines-from-stencil
   ly:grob::pure-simple-vertical-skylines-from-extents))

(define-public grob::always-vertical-skylines-from-stencil
  (ly:make-unpure-pure-container
   ly:grob::vertical-skylines-from-stencil))

(define-public grob::always-vertical-skylines-from-element-stencils
  (ly:make-unpure-pure-container
   ly:grob::vertical-skylines-from-element-stencils
   ly:grob::pure-vertical-skylines-from-element-stencils))

(define-public grob::always-horizontal-skylines-from-element-stencils
  (ly:make-unpure-pure-container
   ly:grob::horizontal-skylines-from-element-stencils
   ly:grob::pure-horizontal-skylines-from-element-stencils))

;; Using this as a callback for a grob's Y-extent promises
;; that the grob's stencil does not depend on line-spacing.
;; We use this promise to figure the space required by Clefs
;; and such at the note-spacing stage.

(define-public grob::always-Y-extent-from-stencil
  (ly:make-unpure-pure-container ly:grob::stencil-height))

(define-public (layout-line-thickness grob)
  "Get the line thickness of the @var{grob}'s corresponding layout."
  (let* ((layout (ly:grob-layout grob))
         (line-thickness (ly:output-def-lookup layout 'line-thickness)))

    line-thickness))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; beam slope

;; even though kievan noteheads do not have stems, their
;; invisible stems help with beam placement
;; this assures that invisible stems for kievan notes are aligned
;; to the center of kievan noteheads. that is thus where the beams'
;; x extrema will fall
(define-public (stem::kievan-offset-callback grob)
  (let* ((note-heads (ly:grob-object grob 'note-heads))
         (note-heads-grobs (if (not (null? note-heads))
                               (ly:grob-array->list note-heads)
                               '()))
         (first-note-head (if (not (null? note-heads-grobs))
                              (car note-heads-grobs)
                              '()))
         (note-head-w (if (not (null? first-note-head))
                          (ly:grob-extent first-note-head first-note-head X)
                          '(0 . 0))))
    (interval-center note-head-w)))


;; sets position of beams for Kievan notation
(define-public (beam::get-kievan-positions grob)
  (let* ((stems (ly:grob-object grob 'stems))
         (stems-grobs (if (not (null? stems))
                          (ly:grob-array->list stems)
                          '()))
         (first-stem (if (not (null? stems-grobs))
                         (car stems-grobs)
                         '()))
         (note-heads (if (not (null? first-stem))
                         (ly:grob-object first-stem 'note-heads)
                         '()))
         (note-heads-grobs (if (not (null? note-heads))
                               (ly:grob-array->list note-heads)
                               '()))
         (first-note-head (if (not (null? note-heads-grobs))
                              (car note-heads-grobs)
                              '()))
         (next-stem (if (not (null? stems))
                        (cadr stems-grobs)
                        '()))
         (next-note-heads (if (not (null? next-stem))
                              (ly:grob-object next-stem 'note-heads)
                              '()))
         (next-note-heads-grobs (if (not (null? next-note-heads))
                                    (ly:grob-array->list next-note-heads)
                                    '()))
         (next-note-head (if (not (null? next-note-heads-grobs))
                             (car next-note-heads-grobs)
                             '()))
         (left-pos (ly:grob-property first-note-head 'Y-offset))
         (right-pos (ly:grob-property next-note-head 'Y-offset))
         (direction (ly:grob-property grob 'direction))
         (first-nh-height (ly:grob::stencil-height first-note-head))
         (next-nh-height (ly:grob::stencil-height next-note-head))
         (left-height (if (= direction DOWN)
                          (+ (car first-nh-height) 0.75)
                          (- (cdr first-nh-height) 0.75)))
         (right-height (if (= direction DOWN)
                           (+ (car next-nh-height) 0.75)
                           (- (cdr next-nh-height) 0.75))))
    (cons (+ left-pos left-height) (+ right-pos right-height))))

(define-public (beam::get-kievan-quantized-positions grob)
  (let* ((pos (ly:grob-property grob 'positions))
         (stems (ly:grob-object grob 'stems))
         (stems-grobs (if (not (null? stems))
                          (ly:grob-array->list stems)
                          '())))
    (for-each
     (lambda (g)
       (ly:grob-set-property! g 'stem-begin-position 0)
       (ly:grob-set-property! g 'length 0))
     stems-grobs)
    pos))

;; calculates each slope of a broken beam individually
(define-public (beam::place-broken-parts-individually grob)
  (ly:beam::quanting grob '(+inf.0 . -inf.0) #f))

;; calculates the slope of a beam as a single unit,
;; even if it is broken.  this assures that the beam
;; will pick up where it left off after a line break
(define-public (beam::align-with-broken-parts grob)
  (ly:beam::quanting grob '(+inf.0 . -inf.0) #t))

;; uses the broken beam style from edition peters combines the
;; values of place-broken-parts-individually and align-with-broken-parts above,
;; favoring place-broken-parts-individually when the beam naturally has a steeper
;; incline and align-with-broken-parts when the beam is flat
(define-public (beam::slope-like-broken-parts grob)
  (define (slope y x)
    (/ (- (cdr y) (car y)) (- (cdr x) (car x))))
  (let* ((quant1 (ly:beam::quanting grob '(+inf.0 . -inf.0) #t))
         (original (ly:grob-original grob))
         (siblings (if (ly:grob? original)
                       (ly:spanner-broken-into original)
                       '())))
    (if (null? siblings)
        quant1
        (let* ((quant2 (ly:beam::quanting grob '(+inf.0 . -inf.0) #f))
               (x-span (ly:grob-property grob 'X-positions))
               (slope1 (slope quant1 x-span))
               (slope2 (slope quant2 x-span))
               (quant2 (if (not (= (sign slope1) (sign slope2)))
                           '(0 . 0)
                           quant2))
               (factor (/ (atan (abs slope1)) PI-OVER-TWO))
               (base (cons-map
                      (lambda (x)
                        (+ (* (x quant1) (- 1 factor))
                           (* (x quant2) factor)))
                      (cons car cdr))))
          (ly:beam::quanting grob base #f)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; cross-staff stuff

(define-public (script-or-side-position-cross-staff g)
  (or
   (ly:script-interface::calc-cross-staff g)
   (ly:side-position-interface::calc-cross-staff g)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; side-position stuff

(define-public (only-if-beamed g)
  (any (lambda (x) (ly:grob? (ly:grob-object x 'beam)))
       (ly:grob-array->list (ly:grob-object g 'side-support-elements))))

(define-public side-position-interface::y-aligned-side
  (ly:make-unpure-pure-container
   ly:side-position-interface::y-aligned-side
   ly:side-position-interface::pure-y-aligned-side))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; self-alignment stuff

(define-public self-alignment-interface::y-aligned-on-self
  (ly:make-unpure-pure-container
   ly:self-alignment-interface::y-aligned-on-self
   ly:self-alignment-interface::pure-y-aligned-on-self))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; staff symbol

(define staff-symbol-referencer::callback
  (ly:make-unpure-pure-container ly:staff-symbol-referencer::callback))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; note heads

(define-public (stem::calc-duration-log grob)
  (ly:duration-log
   (ly:event-property (event-cause grob) 'duration)))

(define (stem-stub::do-calculations grob)
  (and (ly:grob-property (ly:grob-parent grob X) 'cross-staff)
       (not (ly:grob-property (ly:grob-parent grob X) 'transparent))))

(define-public (stem-stub::pure-height grob beg end)
  (if (stem-stub::do-calculations grob)
      '(0 . 0)
      '(+inf.0 . -inf.0)))

(define-public (stem-stub::width grob)
  (if (stem-stub::do-calculations grob)
      (grob::x-parent-width grob)
      '(+inf.0 . -inf.0)))

(define-public (stem-stub::extra-spacing-height grob)
  (if (stem-stub::do-calculations grob)
      (let* ((dad (ly:grob-parent grob X))
             (refp (ly:grob-common-refpoint grob dad Y))
             (stem_ph (ly:grob-pure-height dad refp 0 INFINITY-INT))
             (my_ph (ly:grob-pure-height grob refp 0 INFINITY-INT))
             ;; only account for distance if stem is on different staff than stub
             (dist (if (grob::has-interface refp 'hara-kiri-group-spanner-interface)
                       0
                       (- (car my_ph) (car stem_ph)))))
        (if (interval-empty? (interval-intersection stem_ph my_ph)) #f (coord-translate stem_ph dist)))
      #f))

(define-public (note-head::calc-kievan-duration-log grob)
  (min 3
       (ly:duration-log
        (ly:event-property (event-cause grob) 'duration))))

(define-public (note-head::calc-duration-log grob)
  (min 2
       (ly:duration-log
        (ly:event-property (event-cause grob) 'duration))))

(define-public (dots::calc-dot-count grob)
  (ly:duration-dot-count
   (ly:event-property (event-cause grob) 'duration)))

(define-public (dots::calc-staff-position grob)
  (let* ((head (ly:grob-parent grob Y))
         (log (ly:grob-property head 'duration-log)))

    (cond
     ((or (not (grob::has-interface head 'rest-interface))
          (not (integer? log))) 0)
     ((= log 7) 4)
     ((> log 4) 3)
     ((= log 0) -1)
     ((= log 1) 1)
     ((= log -1) 1)
     (else 0))))

;; Kept separate from note-head::calc-glyph-name to allow use by
;; markup commands \note and \note-by-number
(define-public (select-head-glyph style log)
  "Select a note head glyph string based on note head style @var{style}
and duration-log @var{log}."
  (case style
    ;; "default" style is directly handled in note-head.cc as a
    ;; special case (HW says, mainly for performance reasons).
    ;; Therefore, style "default" does not appear in this case
    ;; statement.  -- jr
    ((xcircle) "2xcircle")
    ((harmonic) "0harmonic")
    ((harmonic-black) "2harmonic")
    ((harmonic-mixed) (if (<= log 1) "0harmonic"
                          "2harmonic"))
    ((baroque)
     ;; Oops, I actually would not call this "baroque", but, for
     ;; backwards compatibility to 1.4, this is supposed to take
     ;; brevis, longa and maxima from the neo-mensural font and all
     ;; other note heads from the default font.  -- jr
     (if (< log 0)
         (string-append (number->string log) "neomensural")
         (number->string log)))
    ((altdefault)
     ;; Like default, but brevis is drawn with double vertical lines
     (if (= log -1)
         (string-append (number->string log) "double")
         (number->string log)))
    ((mensural)
     (string-append (number->string log) (symbol->string style)))
    ((petrucci)
     (if (< log 0)
         (string-append (number->string log) "mensural")
         (string-append (number->string log) (symbol->string style))))
    ((blackpetrucci)
     (if (< log 0)
         (string-append (number->string log) "blackmensural")
         (string-append (number->string log) (symbol->string style))))
    ((semipetrucci)
     (if (< log 0)
         (string-append (number->string log) "semimensural")
         (string-append (number->string log) "petrucci")))
    ((neomensural)
     (string-append (number->string log) (symbol->string style)))
    ((kievan)
     (string-append (number->string log) "kievan"))
    (else
     (if (string-match "vaticana*|hufnagel*|medicaea*" (symbol->string style))
         (symbol->string style)
         (string-append (number->string (max 0 log))
                        (symbol->string style))))))

(define-public (note-head::calc-glyph-name grob)
  (let* ((style (ly:grob-property grob 'style))
         (log (if (string-match "kievan*" (symbol->string style))
                  (min 3 (ly:grob-property grob 'duration-log))
                  (min 2 (ly:grob-property grob 'duration-log)))))
    (select-head-glyph style log)))

(define-public (note-head::brew-ez-stencil grob)
  (let* ((log (ly:grob-property grob 'duration-log))
         (pitch (ly:event-property (event-cause grob) 'pitch))
         (pitch-index (ly:pitch-notename pitch))
         (note-names (ly:grob-property grob 'note-names))
         (pitch-string (if (and (vector? note-names)
                                (> (vector-length note-names) pitch-index))
                           (vector-ref note-names pitch-index)
                           (string
                            (integer->char
                             (+ (modulo (+ pitch-index 2) 7)
                                (char->integer #\A))))))
         (staff-space (ly:staff-symbol-staff-space grob))
         (line-thickness (ly:staff-symbol-line-thickness grob))
         (stem (ly:grob-object grob 'stem))
         (stem-thickness (* (if (ly:grob? stem)
                                (ly:grob-property stem 'thickness)
                                1.3)
                            line-thickness))
         (radius (/ (+ staff-space line-thickness) 2))
         (letter (markup #:center-align #:vcenter pitch-string))
         (filled-circle (markup #:draw-circle radius 0 #t)))

    (ly:stencil-translate-axis
     (grob-interpret-markup
      grob
      (if (>= log 2)
          (make-combine-markup
           filled-circle
           (make-with-color-markup white letter))
          (make-combine-markup
           (make-combine-markup
            filled-circle
            (make-with-color-markup white (make-draw-circle-markup
                                           (- radius stem-thickness) 0 #t)))
           letter)))
     radius X)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; clipping

(define-public (make-rhythmic-location bar-num num den)
  (cons
   bar-num (ly:make-moment num den)))

(define-public (rhythmic-location? a)
  (and (pair? a)
       (integer? (car a))
       (ly:moment? (cdr a))))

(define-public (make-graceless-rhythmic-location loc)
  (make-rhythmic-location
   (car loc)
   (ly:moment-main-numerator (rhythmic-location-measure-position loc))
   (ly:moment-main-denominator (rhythmic-location-measure-position loc))))

(define-public rhythmic-location-measure-position cdr)
(define-public rhythmic-location-bar-number car)

(define-public (rhythmic-location<? a b)
  (cond
   ((< (car a) (car b)) #t)
   ((> (car a) (car b)) #f)
   (else
    (ly:moment<? (cdr a) (cdr b)))))

(define-public (rhythmic-location<=? a b)
  (not (rhythmic-location<? b a)))
(define-public (rhythmic-location>=? a b)
  (not (rhythmic-location<? a b)))
(define-public (rhythmic-location>? a b)
  (rhythmic-location<? b a))

(define-public (rhythmic-location=? a b)
  (and (rhythmic-location<=? a b)
       (rhythmic-location<=? b a)))

(define-public (rhythmic-location->file-string a)
  (ly:format "~a.~a.~a"
             (car a)
             (ly:moment-main-numerator (cdr a))
             (ly:moment-main-denominator (cdr a))))

(define-public (rhythmic-location->string a)
  (ly:format "bar ~a ~a"
             (car a)
             (ly:moment->string (cdr a))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; break visibility

(define-public all-visible             #(#t #t #t))
(define-public begin-of-line-invisible #(#t #t #f))
(define-public center-invisible        #(#t #f #t))
(define-public end-of-line-invisible   #(#f #t #t))
(define-public begin-of-line-visible   #(#f #f #t))
(define-public center-visible          #(#f #t #f))
(define-public end-of-line-visible     #(#t #f #f))
(define-public all-invisible           #(#f #f #f))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; neighbor-interface routines


(define-public (shift-right-at-line-begin g)
  "Shift an item to the right, but only at the start of the line."
  (if (and (ly:item? g)
           (equal? (ly:item-break-dir g) RIGHT))
      (ly:grob-translate-axis! g 3.5 X)))

(define-public (pure-from-neighbor-interface::extra-spacing-height-at-beginning-of-line grob)
  (if (= 1 (ly:item-break-dir grob))
      (pure-from-neighbor-interface::extra-spacing-height grob)
      (cons -0.1 0.1)))

(define-public (pure-from-neighbor-interface::extra-spacing-height grob)
  (let* ((height (ly:grob-pure-height grob grob 0 INFINITY-INT))
         (from-neighbors (interval-union
                          height
                          (ly:axis-group-interface::pure-height
                           grob
                           0
                           INFINITY-INT))))
    (coord-operation - from-neighbors height)))

;; If there are neighbors, we place the height at their midpoint
;; to avoid protrusion of this pure height out of the vertical
;; axis group on either side.  This will minimize the impact of the
;; grob on pure minimum translations.

;; TODO - there is a double call to axis-group-interface::pure-height
;; here and then in the extra-spacing-height function above. Can/should this
;; be rolled into one?
(define-public (pure-from-neighbor-interface::pure-height grob beg end)
  (let* ((height (ly:axis-group-interface::pure-height
                  grob
                  0
                  INFINITY-INT))
         (c (interval-center height)))
    (if (interval-empty? height) empty-interval (cons c c))))

;; Minimizes the impact of the height on vertical spacing while allowing
;; it to appear in horizontal skylines of paper columns if necessary.
(define-public pure-from-neighbor-interface::height-if-pure
  (ly:make-unpure-pure-container #f pure-from-neighbor-interface::pure-height))

(define-public (pure-from-neighbor-interface::account-for-span-bar grob)
  (let* ((esh (pure-from-neighbor-interface::extra-spacing-height grob))
         (hsb (ly:grob-property grob 'has-span-bar))
         (ii (interval-intersection esh (cons -1.01 1.01))))
    (if (pair? hsb)
        (cons (car (if (and (car hsb)
                            (ly:grob-property grob 'allow-span-bar))
                       esh ii))
              (cdr (if (cdr hsb) esh ii)))
        ii)))

(define-public (pure-from-neighbor-interface::extra-spacing-height-including-staff grob)
  (let ((esh (pure-from-neighbor-interface::extra-spacing-height grob))
        (to-staff (coord-operation -
                                   (interval-widen
                                    '(0 . 0)
                                    (ly:staff-symbol-staff-radius grob))
                                   (ly:grob::stencil-height grob))))
    (interval-union esh to-staff)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Tuplets

(define-public (tuplet-number::calc-direction grob)
  (ly:tuplet-bracket::calc-direction (ly:grob-object grob 'bracket)))

(define-public (tuplet-number::calc-denominator-text grob)
  (number->string (ly:event-property (event-cause grob) 'denominator)))

(define-public (tuplet-number::calc-fraction-text grob)
  (let ((ev (event-cause grob)))

    (format #f "~a:~a"
            (ly:event-property ev 'denominator)
            (ly:event-property ev 'numerator))))

;; a formatter function, which is simply a wrapper around an existing
;; tuplet formatter function. It takes the value returned by the given
;; function and appends a note of given length.
(define-public ((tuplet-number::append-note-wrapper function note) grob)
  (let ((txt (if function (function grob) #f)))

    (if txt
        (markup txt #:fontsize -5 #:note note UP)
        (markup #:fontsize -5 #:note note UP))))

;; Print a tuplet denominator with a different number than the one derived from
;; the actual tuplet fraction
(define-public ((tuplet-number::non-default-tuplet-denominator-text denominator)
                grob)
  (number->string (if denominator
                      denominator
                      (ly:event-property (event-cause grob) 'denominator))))

;; Print a tuplet fraction with different numbers than the ones derived from
;; the actual tuplet fraction
(define-public ((tuplet-number::non-default-tuplet-fraction-text
                 denominator numerator) grob)
  (let* ((ev (event-cause grob))
         (den (if denominator denominator (ly:event-property ev 'denominator)))
         (num (if numerator numerator (ly:event-property ev 'numerator))))

    (format #f "~a:~a" den num)))

;; Print a tuplet fraction with note durations appended to the numerator and the
;; denominator
(define-public ((tuplet-number::fraction-with-notes
                 denominatornote numeratornote) grob)
  (let* ((ev (event-cause grob))
         (denominator (ly:event-property ev 'denominator))
         (numerator (ly:event-property ev 'numerator)))

    ((tuplet-number::non-default-fraction-with-notes
      denominator denominatornote numerator numeratornote) grob)))

;; Print a tuplet fraction with note durations appended to the numerator and the
;; denominator
(define-public ((tuplet-number::non-default-fraction-with-notes
                 denominator denominatornote numerator numeratornote) grob)
  (let* ((ev (event-cause grob))
         (den (if denominator denominator (ly:event-property ev 'denominator)))
         (num (if numerator numerator (ly:event-property ev 'numerator))))

    (make-concat-markup (list
                         (make-simple-markup (format #f "~a" den))
                         (markup #:fontsize -5 #:note denominatornote UP)
                         (make-simple-markup " : ")
                         (make-simple-markup (format #f "~a" num))
                         (markup #:fontsize -5 #:note numeratornote UP)))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Color

(define-public (color? x)
  (and (list? x)
       (= 3 (length x))
       (every number? x)
       (every (lambda (y) (<= 0 y 1)) x)))

(define-public (rgb-color r g b) (list r g b))

;; predefined colors
(define-public black       '(0.0 0.0 0.0))
(define-public white       '(1.0 1.0 1.0))
(define-public red         '(1.0 0.0 0.0))
(define-public green       '(0.0 1.0 0.0))
(define-public blue        '(0.0 0.0 1.0))
(define-public cyan        '(0.0 1.0 1.0))
(define-public magenta     '(1.0 0.0 1.0))
(define-public yellow      '(1.0 1.0 0.0))

(define-public grey        '(0.5 0.5 0.5))
(define-public darkred     '(0.5 0.0 0.0))
(define-public darkgreen   '(0.0 0.5 0.0))
(define-public darkblue    '(0.0 0.0 0.5))
(define-public darkcyan    '(0.0 0.5 0.5))
(define-public darkmagenta '(0.5 0.0 0.5))
(define-public darkyellow  '(0.5 0.5 0.0))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; key signature

(define-public (key-signature-interface::alteration-positions
                entry c0-position grob)
  (let ((step (car entry))
        (alter (cdr entry)))
    (if (pair? step)
        (list (+ (cdr step) (* (car step) 7) c0-position))
        (let* ((c-position (modulo c0-position 7))
               (positions
                (if (< alter 0)
                    ;; See (flat|sharp)-positions in define-grob-properties.scm
                    (ly:grob-property grob 'flat-positions '(3))
                    (ly:grob-property grob 'sharp-positions '(3))))
               (p (list-ref positions
                            (if (< c-position (length positions))
                                c-position 0)))
               (max-position (if (pair? p) (cdr p) p))
               (min-position (if (pair? p) (car p) (- max-position 6)))
               (first-position (+ (modulo (- (+ c-position step)
                                             min-position)
                                          7)
                                  min-position)))
          (define (prepend x l) (if (> x max-position)
                                    l
                                    (prepend (+ x 7) (cons x l))))
          (prepend first-position '())))))

(define-public (key-signature-interface::alteration-position
                step alter c0-position)
;; Deprecated.  Not a documented interface, and no longer used in LilyPond,
;; but needed for a popular file, LilyJAZZ.ily for version 2.16
  (if (pair? step)
    (+ (cdr step) (* (car step) 7) c0-position)
    (let* ((c-pos (modulo c0-position 7))
           (hi (list-ref
                 (if (< alter 0)
                   '(2 3 4 2 1 2 1) ; position of highest flat
                   '(4 5 4 2 3 2 3)); position of highest sharp
                 c-pos)))
      (- hi (modulo (- hi (+ c-pos step)) 7)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; annotations

(define-public (numbered-footnotes int)
  (markup #:tiny (number->string (+ 1 int))))

(define-public (symbol-footnotes int)
  (define (helper symbols out idx n)
    (if (< n 1)
        out
        (helper symbols
                (string-append out (list-ref symbols idx))
                idx
                (- n 1))))
  (markup #:tiny (helper '("*" "†" "‡" "§" "¶")
                         ""
                         (remainder int 5)
                         (+ 1 (quotient int 5)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; accidentals

(define-public (accidental-interface::calc-alteration grob)
  (ly:pitch-alteration (ly:event-property (event-cause grob) 'pitch)))

(define-public (accidental-interface::glyph-name grob)
  (assoc-get (ly:grob-property grob 'alteration)
             standard-alteration-glyph-name-alist))

(define-public accidental-interface::height
  (ly:make-unpure-pure-container
   ly:accidental-interface::height
   ly:accidental-interface::pure-height))

(define-public cancellation-glyph-name-alist
  '((0 . "accidentals.natural")))

(define-public standard-alteration-glyph-name-alist
  '(
    ;; ordered for optimal performance.
    (0 . "accidentals.natural")
    (-1/2 . "accidentals.flat")
    (1/2 . "accidentals.sharp")

    (1 . "accidentals.doublesharp")
    (-1 . "accidentals.flatflat")

    (3/4 . "accidentals.sharp.slashslash.stemstemstem")
    (1/4 . "accidentals.sharp.slashslash.stem")
    (-1/4 . "accidentals.mirroredflat")
    (-3/4 . "accidentals.mirroredflat.flat")))

;; FIXME: standard vs default, alteration-FOO vs FOO-alteration
(define-public alteration-default-glyph-name-alist
  standard-alteration-glyph-name-alist)

(define-public makam-alteration-glyph-name-alist
  '((1 . "accidentals.doublesharp")
    (8/9 . "accidentals.sharp.slashslashslash.stemstem")
    (5/9 . "accidentals.sharp.slashslashslash.stem")
    (4/9 . "accidentals.sharp")
    (1/9 . "accidentals.sharp.slashslash.stem")
    (0 . "accidentals.natural")
    (-1/9 . "accidentals.mirroredflat")
    (-4/9 . "accidentals.flat.slash")
    (-5/9 . "accidentals.flat")
    (-8/9 . "accidentals.flat.slashslash")
    (-1 . "accidentals.flatflat")))

(define-public alteration-hufnagel-glyph-name-alist
  '((-1/2 . "accidentals.hufnagelM1")
    (0 . "accidentals.vaticana0")
    (1/2 . "accidentals.mensural1")))

(define-public alteration-medicaea-glyph-name-alist
  '((-1/2 . "accidentals.medicaeaM1")
    (0 . "accidentals.vaticana0")
    (1/2 . "accidentals.mensural1")))

(define-public alteration-vaticana-glyph-name-alist
  '((-1/2 . "accidentals.vaticanaM1")
    (0 . "accidentals.vaticana0")
    (1/2 . "accidentals.mensural1")))

(define-public alteration-mensural-glyph-name-alist
  '((-1/2 . "accidentals.mensuralM1")
    (0 . "accidentals.vaticana0")
    (1/2 . "accidentals.mensural1")))

(define-public alteration-kievan-glyph-name-alist
  '((-1/2 . "accidentals.kievanM1")
    (1/2 . "accidentals.kievan1")))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; * Pitch Trill Heads
;; * Parentheses

(define-public (parentheses-item::calc-parenthesis-stencils grob)
  (let* ((font (ly:grob-default-font grob))
         (lp (ly:font-get-glyph font "accidentals.leftparen"))
         (rp (ly:font-get-glyph font "accidentals.rightparen")))

    (list lp rp)))

(define-public (parentheses-item::calc-angled-bracket-stencils grob)
  (let* ((parent (ly:grob-parent grob Y))
         (y-extent (ly:grob-extent parent parent Y))
         (half-thickness 0.05) ; should it be a property?
         (width 0.5) ; should it be a property?
         (angularity 1.5)  ; makes angle brackets
         (white-padding 0.1) ; should it be a property?
         (lp (ly:stencil-aligned-to
              (ly:stencil-aligned-to
               (make-parenthesis-stencil y-extent
                                         half-thickness
                                         (- width)
                                         angularity)
               Y CENTER)
              X RIGHT))
         (lp-x-extent
          (interval-widen (ly:stencil-extent lp X) white-padding))
         (rp (ly:stencil-aligned-to
              (ly:stencil-aligned-to
               (make-parenthesis-stencil y-extent
                                         half-thickness
                                         width
                                         angularity)
               Y CENTER)
              X LEFT))
         (rp-x-extent
          (interval-widen (ly:stencil-extent rp X) white-padding)))
    (set! lp (ly:make-stencil (ly:stencil-expr lp)
                              lp-x-extent
                              (ly:stencil-extent lp Y)))
    (set! rp (ly:make-stencil (ly:stencil-expr rp)
                              rp-x-extent
                              (ly:stencil-extent rp Y)))
    (list (stencil-whiteout lp)
          (stencil-whiteout rp))))

(define (parenthesize-elements grob . rest)
  (let* ((refp (if (null? rest)
                   grob
                   (car rest)))
         (elts (ly:grob-object grob 'elements))
         (x-ext (ly:relative-group-extent elts refp X))
         (stencils (ly:grob-property grob 'stencils))
         (lp (car stencils))
         (rp (cadr stencils))
         (padding (ly:grob-property grob 'padding 0.1)))

    (ly:stencil-add
     (ly:stencil-translate-axis lp (- (car x-ext) padding) X)
     (ly:stencil-translate-axis rp (+ (cdr x-ext) padding) X))))


(define-public (parentheses-item::print me)
  (let* ((elts (ly:grob-object me 'elements))
         (y-ref (ly:grob-common-refpoint-of-array me elts Y))
         (x-ref (ly:grob-common-refpoint-of-array me elts X))
         (stencil (parenthesize-elements me x-ref))
         (elt-y-ext (ly:relative-group-extent elts y-ref Y))
         (y-center (interval-center elt-y-ext)))

    (ly:stencil-translate
     stencil
     (cons
      (- (ly:grob-relative-coordinate me x-ref X))
      (- y-center (ly:grob-relative-coordinate me y-ref Y))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; offset callbacks

(define-public (pure-chain-offset-callback grob start end prev-offset)
  "Sometimes, a chained offset callback is unpure and there is
   no way to write a pure function that estimates its behavior.
   In this case, we use a pure equivalent that will simply pass
   the previous calculated offset value."
  prev-offset)

(define-public (scale-by-font-size x)
  (ly:make-unpure-pure-container
    (lambda (grob)
      (* x (magstep (ly:grob-property grob 'font-size 0))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;

(define-public (chain-grob-member-functions grob value . funcs)
  (for-each
   (lambda (func)
     (set! value (func grob value)))
   funcs)

  value)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; falls/doits

(define-public (bend::print spanner)
  (define (close  a b)
    (< (abs (- a b)) 0.01))

  (let* ((delta-y (* 0.5 (ly:grob-property spanner 'delta-position)))
         (left-span (ly:spanner-bound spanner LEFT))
         (dots (if (and (grob::has-interface left-span 'note-head-interface)
                        (ly:grob? (ly:grob-object left-span 'dot)))
                   (ly:grob-object left-span 'dot) #f))

         (right-span (ly:spanner-bound spanner RIGHT))
         (thickness (* (ly:grob-property spanner 'thickness)
                       (ly:output-def-lookup (ly:grob-layout spanner)
                                             'line-thickness)))
         (padding (ly:grob-property spanner 'padding 0.5))
         (common (ly:grob-common-refpoint right-span
                                          (ly:grob-common-refpoint spanner
                                                                   left-span X)
                                          X))
         (common-y (ly:grob-common-refpoint spanner left-span Y))
         (minimum-length (ly:grob-property spanner 'minimum-length 0.5))

         (left-x (+ padding
                    (max
                     (interval-end (ly:grob-robust-relative-extent
                                    left-span common X))
                     (if
                      (and dots
                           (close
                            (ly:grob-relative-coordinate dots common-y Y)
                            (ly:grob-relative-coordinate spanner common-y Y)))
                      (interval-end
                       (ly:grob-robust-relative-extent dots common X))
                      (- INFINITY-INT)))))
         (right-x (max (- (interval-start
                           (ly:grob-robust-relative-extent right-span common X))
                          padding)
                       (+ left-x minimum-length)))
         (self-x (ly:grob-relative-coordinate spanner common X))
         (dx (- right-x left-x))
         (exp (list 'path thickness
                    `(quote
                      (rmoveto
                       ,(- left-x self-x) 0

                       rcurveto
                       ,(/ dx 3)
                       0
                       ,dx ,(* 0.66 delta-y)
                       ,dx ,delta-y)))))

    (ly:make-stencil
     exp
     (cons (- left-x self-x) (- right-x self-x))
     (cons (min 0 delta-y)
           (max 0 delta-y)))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; grace spacing

(define-public (grace-spacing::calc-shortest-duration grob)
  (let* ((cols (ly:grob-object grob 'columns))
         (get-difference
          (lambda (idx)
            (ly:moment-sub (ly:grob-property
                            (ly:grob-array-ref cols (1+ idx)) 'when)
                           (ly:grob-property
                            (ly:grob-array-ref cols idx) 'when))))

         (moment-min (lambda (x y)
                       (cond
                        ((and x y)
                         (if (ly:moment<? x y)
                             x
                             y))
                        (x x)
                        (y y)))))

    (fold moment-min #f (map get-difference
                             (iota (1- (ly:grob-array-length cols)))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; fingering

(define-public (fingering::calc-text grob)
  (let ((event (event-cause grob)))
    (or (ly:event-property event 'text #f)
        (number->string (ly:event-property event 'digit) 10))))

(define-public (string-number::calc-text grob)
  (let ((event (event-cause grob)))
    (or (ly:event-property event 'text #f)
        (number->string (ly:event-property event 'string-number) 10))))

(define-public (stroke-finger::calc-text grob)
  (let ((event (event-cause grob)))
    (or (ly:event-property event 'text #f)
        (vector-ref (ly:grob-property grob 'digit-names)
                    (1- (max 1
                             (min 5 (ly:event-property event 'digit))))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; dynamics

(define-public (hairpin::calc-grow-direction grob)
  (if (ly:in-event-class? (event-cause grob) 'decrescendo-event)
      START
      STOP))

(define-public (dynamic-text-spanner::before-line-breaking grob)
  "Monitor left bound of @code{DynamicTextSpanner} for absolute dynamics.
If found, ensure @code{DynamicText} does not collide with spanner text by
changing @code{'attach-dir} and @code{'padding}.  Reads the
@code{'right-padding} property of @code{DynamicText} to fine tune space
between the two text elements."
  (let ((left-bound (ly:spanner-bound grob LEFT)))
    (if (grob::has-interface left-bound 'dynamic-text-interface)
        (let* ((details (ly:grob-property grob 'bound-details))
               (left-details (ly:assoc-get 'left details))
               (my-padding (ly:assoc-get 'padding left-details))
               (script-padding (ly:grob-property left-bound 'right-padding 0)))

          (and (number? my-padding)
               (ly:grob-set-nested-property! grob
                                             '(bound-details left attach-dir)
                                             RIGHT)
               (ly:grob-set-nested-property! grob
                                             '(bound-details left padding)
                                             (+ my-padding script-padding)))))))

(define-public ((elbowed-hairpin coords mirrored?) grob)
  "Create hairpin based on a list of @var{coords} in @code{(cons x y)}
form.  @code{x} is the portion of the width consumed for a given line
and @code{y} is the portion of the height.  For example,
@code{'((0.3 . 0.7) (0.8 . 0.9) (1.0 . 1.0))} means that at the point
where the hairpin has consumed 30% of its width, it must
be at 70% of its height.  Once it is to 80% width, it
must be at 90% height.  It finishes at
100% width and 100% height.  @var{mirrored?} indicates if the hairpin
is mirrored over the Y-axis or if just the upper part is drawn.
Returns a function that accepts a hairpin grob as an argument
and draws the stencil based on its coordinates.
@lilypond[verbatim,quote]
#(define simple-hairpin
  (elbowed-hairpin '((1.0 . 1.0)) #t))

\\relative c' {
  \\override Hairpin #'stencil = #simple-hairpin
  a\\p\\< a a a\\f
}
@end lilypond
"
  (define (pair-to-list pair)
    (list (car pair) (cdr pair)))
  (define (normalize-coords goods x y)
    (map
     (lambda (coord)
       (cons (* x (car coord)) (* y (cdr coord))))
     goods))
  (define (my-c-p-s points thick decresc?)
    (make-connected-path-stencil
     points
     thick
     (if decresc? -1.0 1.0)
     1.0
     #f
     #f))
  ;; outer let to trigger suicide
  (let ((sten (ly:hairpin::print grob)))
    (if (grob::is-live? grob)
        (let* ((decresc? (eq? (ly:grob-property grob 'grow-direction) LEFT))
               (thick (ly:grob-property grob 'thickness 0.1))
               (thick (* thick (layout-line-thickness grob)))
               (xex (ly:stencil-extent sten X))
               (lenx (interval-length xex))
               (yex (ly:stencil-extent sten Y))
               (leny (interval-length yex))
               (xtrans (+ (car xex) (if decresc? lenx 0)))
               (ytrans (car yex))
               (uplist (map pair-to-list
                            (normalize-coords coords lenx (/ leny 2))))
               (downlist (map pair-to-list
                              (normalize-coords coords lenx (/ leny -2)))))
          (ly:stencil-translate
           (ly:stencil-add
            (my-c-p-s uplist thick decresc?)
            (if mirrored? (my-c-p-s downlist thick decresc?) empty-stencil))
           (cons xtrans ytrans)))
        '())))

(define-public flared-hairpin
  (elbowed-hairpin '((0.95 . 0.4) (1.0 . 1.0)) #t))

(define-public constante-hairpin
  (elbowed-hairpin '((1.0 . 0.0) (1.0 . 1.0)) #f))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; lyrics

(define-public (lyric-text::print grob)
  "Allow interpretation of tildes as lyric tieing marks."

  (let ((text (ly:grob-property grob 'text)))

    (grob-interpret-markup grob (if (string? text)
                                    (make-tied-lyric-markup text)
                                    text))))

(define-public ((grob::calc-property-by-copy prop) grob)
  (ly:event-property (event-cause grob) prop))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; general inheritance

(define-public ((grob::inherit-parent-property axis property . default) grob)
  "@var{grob} callback generator for inheriting a @var{property} from
an @var{axis} parent, defaulting to @var{default} if there is no
parent or the parent has no setting."
  (let ((parent (ly:grob-parent grob axis)))
    (cond
     ((ly:grob? parent)
      (apply ly:grob-property parent property default))
     ((pair? default) (car default))
     (else '()))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; fret boards

(define-public (fret-board::calc-stencil grob)
  (grob-interpret-markup
   grob
   (make-fret-diagram-verbose-markup
    (ly:grob-property grob 'dot-placement-list))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; slurs

(define-public slur::height
  (ly:make-unpure-pure-container
   ly:slur::height
   ly:slur::pure-height))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; scripts

(define-public (script-interface::calc-x-offset grob)
  (ly:grob-property grob 'positioning-done)
  (let* ((shift (ly:grob-property grob 'toward-stem-shift 0.0))
         (note-head-location
          (ly:self-alignment-interface::centered-on-x-parent grob))
         (note-head-grob (ly:grob-parent grob X))
         (stem-grob (ly:grob-object note-head-grob 'stem)))

    (+ note-head-location
       ;; If the property 'toward-stem-shift is defined and the script
       ;; has the same direction as the stem, move the script accordingly.
       ;; Since scripts can also be over skips, we need to check whether
       ;; the grob has a stem at all.
       (if (ly:grob? stem-grob)
           (let ((dir1 (ly:grob-property grob 'direction))
                 (dir2 (ly:grob-property stem-grob 'direction)))
             (if (equal? dir1 dir2)
                 (let* ((common-refp (ly:grob-common-refpoint grob stem-grob X))
                        (stem-location
                         (ly:grob-relative-coordinate stem-grob common-refp X)))
                   (* shift (- stem-location note-head-location)))
                 0.0))
           0.0))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; instrument names

(define-public (system-start-text::print grob)
  (let* ((left-bound (ly:spanner-bound grob LEFT))
         (left-mom (ly:grob-property left-bound 'when))
         (name (if (moment<=? left-mom ZERO-MOMENT)
                   (ly:grob-property grob 'long-text)
                   (ly:grob-property grob 'text))))

    (if (and (markup? name)
             (!= (ly:item-break-dir left-bound) CENTER))

        (grob-interpret-markup grob name)
        (ly:grob-suicide! grob))))

(define-public (system-start-text::calc-x-offset grob)
  (let* ((left-bound (ly:spanner-bound grob LEFT))
         (left-mom (ly:grob-property left-bound 'when))
         (layout (ly:grob-layout grob))
         (indent (ly:output-def-lookup layout
                                       (if (moment<=? left-mom ZERO-MOMENT)
                                           'indent
                                           'short-indent)
                                       0.0))
         (system (ly:grob-system grob))
         (my-extent (ly:grob-extent grob system X))
         (elements (ly:grob-object system 'elements))
         (common (ly:grob-common-refpoint-of-array system elements X))
         (total-ext empty-interval)
         (align-x (ly:grob-property grob 'self-alignment-X 0))
         (padding (min 0 (- (interval-length my-extent) indent)))
         (right-padding (- padding
                           (/ (* padding (1+ align-x)) 2))))

    ;; compensate for the variation in delimiter extents by
    ;; calculating an X-offset correction based on united extents
    ;; of all delimiters in this system
    (let unite-delims ((l (ly:grob-array-length elements)))
      (if (> l 0)
          (let ((elt (ly:grob-array-ref elements (1- l))))

            (if (grob::has-interface elt 'system-start-delimiter-interface)
                (let ((dims (ly:grob-extent elt common X)))
                  (if (interval-sane? dims)
                      (set! total-ext (interval-union total-ext dims)))))
            (unite-delims (1- l)))))

    (+
     (ly:side-position-interface::x-aligned-side grob)
     right-padding
     (- (interval-length total-ext)))))

(define-public (system-start-text::calc-y-offset grob)

  (define (live-elements-list me)
    (let ((elements (ly:grob-object me 'elements)))

      (filter! grob::is-live?
               (ly:grob-array->list elements))))

  (let* ((left-bound (ly:spanner-bound grob LEFT))
         (live-elts (live-elements-list grob))
         (system (ly:grob-system grob))
         (extent empty-interval))

    (if (and (pair? live-elts)
             (interval-sane? (ly:grob-extent grob system Y)))
        (let get-extent ((lst live-elts))
          (if (pair? lst)
              (let ((axis-group (car lst)))

                (if (and (ly:spanner? axis-group)
                         (equal? (ly:spanner-bound axis-group LEFT)
                                 left-bound))
                    (set! extent (add-point extent
                                            (ly:grob-relative-coordinate
                                             axis-group system Y))))
                (get-extent (cdr lst)))))
        ;; no live axis group(s) for this instrument name -> remove from system
        (ly:grob-suicide! grob))

    (+
     (ly:self-alignment-interface::y-aligned-on-self grob)
     (interval-center extent))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; axis group interface

(define-public axis-group-interface::height
  (ly:make-unpure-pure-container
   ly:axis-group-interface::height
   ly:axis-group-interface::pure-height))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ambitus

;; Calculate the gaps between ambitus heads and ends of ambitus line.
;; Start by determining desired length of the ambitus line (based on
;; length-fraction property), calc gap from that and make sure that
;; it doesn't exceed maximum allowed value.

(define-public (ambitus-line::calc-gap grob)
  (let ((heads (ly:grob-object grob 'note-heads)))

  (if (and (ly:grob-array? heads)
             (= (ly:grob-array-length heads) 2))
      (let* ((common (ly:grob-common-refpoint-of-array grob heads Y))
              (head-down (ly:grob-array-ref heads 0))
              (head-up (ly:grob-array-ref heads 1))
              (fraction (ly:grob-property grob 'length-fraction 0.7))
              (max-gap (ly:grob-property grob 'maximum-gap 0.45))
              ;; distance between noteheads:
              (distance (- (interval-start (ly:grob-extent head-up common Y))
                          (interval-end (ly:grob-extent head-down common Y))))
              (gap (* 0.5 distance (- 1 fraction))))

         (min gap max-gap))
      0)))

;; Print a line connecting ambitus heads:

(define-public (ambitus::print grob)
  (let ((heads (ly:grob-object grob 'note-heads)))

    (if (and (ly:grob-array? heads)
             (= (ly:grob-array-length heads) 2))
        (let* ((common (ly:grob-common-refpoint-of-array grob heads Y))
               (head-down (ly:grob-array-ref heads 0))
               (head-up (ly:grob-array-ref heads 1))
               ;; The value used when 'gap' property cannot be read is small
               ;; to make sure that ambitus of a fifth will have a visible line.
               (gap (ly:grob-property grob 'gap 0.25))
               (point-min (+ (interval-end (ly:grob-extent head-down common Y))
                             gap))
               (point-max (- (interval-start (ly:grob-extent head-up common Y))
                             gap)))

          (if (< (+ point-min 0.1) point-max) ; don't print lines shorter than 0.1ss
              (let* ((layout (ly:grob-layout grob))
                     (line-thick (ly:output-def-lookup layout 'line-thickness))
                     (blot (ly:output-def-lookup layout 'blot-diameter))
                     (grob-thick (ly:grob-property grob 'thickness 2))
                     (width (* line-thick grob-thick))
                     (x-ext (symmetric-interval (/ width 2)))
                     (y-ext (cons point-min point-max))
                     (line (ly:round-filled-box x-ext y-ext blot))
                     (y-coord (ly:grob-relative-coordinate grob common Y)))

                (ly:stencil-translate-axis line (- y-coord) Y))
              empty-stencil))
        (begin
          (ly:grob-suicide! grob)
          (list)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  laissez-vibrer tie
;;
;;  needed so we can make laissez-vibrer a pure print
;;
(define-public (laissez-vibrer::print grob)
  (ly:tie::print grob))

(define-public (semi-tie::calc-cross-staff grob)
  (let* ((note-head (ly:grob-object grob 'note-head))
         (stem (ly:grob-object note-head 'stem)))
    (and (ly:grob? stem)
         (ly:grob-property stem 'cross-staff #f))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; volta-bracket

(define-public (volta-bracket-interface::pure-height grob start end)
  (let ((edge-height (ly:grob-property grob 'edge-height)))
    (if (number-pair? edge-height)
        (let ((smaller (min (car edge-height) (cdr edge-height)))
              (larger (max (car edge-height) (cdr edge-height))))
          (interval-union '(0 . 0) (cons smaller larger)))
        '(0 . 0))))
