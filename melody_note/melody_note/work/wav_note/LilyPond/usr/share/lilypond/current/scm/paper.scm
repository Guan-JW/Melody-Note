;;;; This file is part of LilyPond, the GNU music typesetter.
;;;;
;;;; Copyright (C) 2004--2012 Han-Wen Nienhuys <hanwen@xs4all.nl>
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

;; for define-safe-public when byte-compiling using Guile V2
(use-modules (scm safe-utility-defs))

(define-public (set-paper-dimension-variables mod)
  (module-define! mod 'dimension-variables
                  '(blot-diameter
                    bottom-margin
                    cm
                    footnote-footer-padding
                    footnote-padding
                    horizontal-shift
                    in
                    indent
                    inner-margin
                    inner-margin-default-scaled
                    ledger-line-thickness
                    left-margin
                    left-margin-default-scaled
                    line-thickness
                    line-width
                    mm
                    outer-margin
                    outer-margin-default-scaled
                    paper-height
                    paper-width
                    pt
                    right-margin
                    right-margin-default-scaled
                    short-indent
                    staff-height
                    staff-space
                    top-margin)))

(define (calc-line-thickness staff-space pt)
  ;; linear interpolation.

  ;; !! synchronize with feta-params.mf
  (let*
      ((x1 (* 4.125 pt))
       (x0 (* 5 pt))
       (f1 (* 0.47 pt))
       (f0 (* 0.50 pt)))

    (/
     (+
      (* f1 (- staff-space x0))
      (* f0 (- x1 staff-space)))
     (- x1 x0))))

(define-public (layout-set-absolute-staff-size-in-module module staff-height)
  (let*
      ((pt (eval 'pt module))
       (ss (/ staff-height 4))
       (factor (/ staff-height (* 20 pt)))
       (setm! (lambda (sym val)
                (module-define! module sym val))))

    ;; Synchronized with the `text-font-size'
    ;; binding in add-pango-fonts (see font.scm).
    (setm! 'text-font-size (* 11 factor))

    (setm! 'output-scale ss)
    (setm! 'fonts (make-century-schoolbook-tree factor))
    (setm! 'staff-height staff-height)
    (setm! 'staff-space ss)

    (setm! 'line-thickness (calc-line-thickness ss pt))

    ;;  sync with feta
    (setm! 'ledger-line-thickness (+ (* 0.5 pt) (/ ss 10)))

    ;;  sync with feta
    (setm! 'blot-diameter (* 0.4 pt))
    ))

(define-public (layout-set-absolute-staff-size sz)
  "Set the absolute staff size inside of a @code{\\layout@{@}} block.
@var{sz} is in points."
  (layout-set-absolute-staff-size-in-module (current-module) sz))

(define-public (layout-set-staff-size sz)
  "Set the staff size inside of a @code{\\layout@{@}} block.
@var{sz} is in points."

  (layout-set-absolute-staff-size (* (eval 'pt (current-module)) sz)))

(define-safe-public (set-global-staff-size sz)
  "Set the default staff size, where SZ is thought to be in PT."
  (let* ((current-mod (current-module))
         (parser (eval 'parser current-mod))
         (pap (ly:parser-lookup parser '$defaultpaper))
         (in-layout? (or (module-defined? current-mod 'is-paper)
                         (module-defined? current-mod 'is-layout)))

         ;; maybe not necessary.
         ;; but let's be paranoid. Maybe someone still refers to the
         ;; old one.
         (new-paper (ly:output-def-clone pap))

         (new-scope (ly:output-def-scope new-paper)))

    (if in-layout?
        (ly:warning (_ "set-global-staff-size: not in toplevel scope")))

    (layout-set-absolute-staff-size-in-module new-scope
                                              (* sz (eval 'pt new-scope)))
    (module-define! current-mod '$defaultpaper new-paper)))

(define-public paper-alist

  ;; don't use decimals.
  ;; ISO 216 has a tolerance of +- 2mm

  ;; TODO Autogenerate the following list so it appears under the
  ;; 'Predefined paper sizes' node in notation-appendices.itely
  ;; currently the list below has been copied and formatted manually.
  ;; Therefore, please add any new entries to the *itely file as well.

  '(("a10" . (cons (* 26 mm) (* 37 mm)))
    ("a9" . (cons (* 37 mm) (* 52 mm)))
    ("a8" . (cons (* 52 mm) (* 74 mm)))
    ("a7" . (cons (* 74 mm) (* 105 mm)))
    ("a6" . (cons (* 105 mm) (* 148 mm)))
    ("a5" . (cons (* 148 mm) (* 210 mm)))
    ("a4" . (cons (* 210 mm) (* 297 mm)))
    ("a3" . (cons (* 297 mm) (* 420 mm)))
    ("a2" . (cons (* 420 mm) (* 594 mm)))
    ("a1" . (cons (* 594 mm) (* 841 mm)))
    ("a0" . (cons (* 841 mm) (* 1189 mm)))
    ("b10" . (cons (* 31 mm) (* 44 mm)))
    ("b9" . (cons (* 44 mm) (* 62 mm)))
    ("b8" . (cons (* 62 mm) (* 88 mm)))
    ("b7" . (cons (* 88 mm) (* 125 mm)))
    ("b6" . (cons (* 125 mm) (* 176 mm)))
    ("b5" . (cons (* 176 mm) (* 250 mm)))
    ("b4" . (cons (* 250 mm) (* 353 mm)))
    ("b3" . (cons (* 353 mm) (* 500 mm)))
    ("b2" . (cons (* 500 mm) (* 707 mm)))
    ("b1" . (cons (* 707 mm) (* 1000 mm)))
    ("b0" . (cons (* 1000 mm) (* 1414 mm)))
    ;; Below are two extended sizes defined in DIn 476
    ("4a0" . (cons (* 1682 mm) (* 2378 mm)))
    ("2a0" . (cons (* 1189 mm) (* 1682 mm)))
    ;; Below are ISO 269 standard C series
    ("c10" . (cons (* 28 mm) (* 40 mm)))
    ("c9" . (cons (* 40 mm) (* 57 mm)))
    ("c8" . (cons (* 57 mm) (* 81 mm)))
    ("c7" . (cons (* 81 mm) (* 114 mm)))
    ("c6" . (cons (* 114 mm) (* 162 mm)))
    ("c5" . (cons (* 162 mm) (* 229 mm)))
    ("c4" . (cons (* 229 mm) (* 324 mm)))
    ("c3" . (cons (* 324 mm) (* 458 mm)))
    ("c2" . (cons (* 458 mm) (* 648 mm)))
    ("c1" . (cons (* 648 mm) (* 917 mm)))
    ("c0" . (cons (* 917 mm) (* 1297 mm)))
    ;; Below are North American paper sizes
    ("junior-legal" . (cons (* 8.0 in) (* 5.0 in)))
    ("legal" . (cons (* 8.5 in) (* 14.0 in)))
    ("letter" . (cons (* 8.5 in) (* 11.0 in)))
    ;; Ledger (17x11) is a 90 degree rotation of Tabloid
    ("17x11" . (cons (* 17.0 in) (* 11.0 in)))
    ("ledger" . (cons (* 17.0 in) (* 11.0 in)))
    ;; Tabloid (11x17)
    ("11x17" . (cons (* 11.0 in) (* 17.0 in)))
    ("tabloid" . (cons (* 11.0 in) (* 17.0 in)))
    ;; government-letter by IEEE Printer Working Group, for children's writing
    ("government-letter" . (cons (* 8 in) (* 10.5 in)))
    ("government-legal" . (cons (* 8.5 in) (* 13.0 in)))
    ("philippine-legal" . (cons (* 8.5 in) (* 13.0 in)))
    ;; ANSI sizes
    ("ansi a" . (cons (* 8.5 in) (* 11.0 in)))
    ("ansi b" . (cons (* 17.0 in) (* 11.0 in)))
    ("ansi c" . (cons (* 17.0 in) (* 22.0 in)))
    ("ansi d" . (cons (* 22.0 in) (* 34.0 in)))
    ("ansi e" . (cons (* 34.0 in) (* 44.0 in)))
    ("engineering f" . (cons (* 28.0 in) (* 40.0 in)))
    ;; G and H are very rare, and the lengths are variable up to 90 inches
    ;; North American Architectural sizes
    ("arch a" . (cons (* 9.0 in) (* 12.0 in)))
    ("arch b" . (cons (* 12.0 in) (* 18.0 in)))
    ("arch c" . (cons (* 18.0 in) (* 24.0 in)))
    ("arch d" . (cons (* 24.0 in) (* 36.0 in)))
    ("arch e" . (cons (* 36.0 in) (* 48.0 in)))
    ("arch e1" . (cons (* 30.0 in) (* 42.0 in)))
    ;; Other sizes
    ;; Some are antique sizes which are still using in UK
    ("statement" . (cons (* 5.5 in) (* 8.5 in)))
    ("half letter" . (cons (* 5.5 in) (* 8.5 in)))
    ("quarto" . (cons (* 8.0 in) (* 10.0 in)))
    ("octavo" . (cons (* 6.75 in) (* 10.5 in)))
    ("executive" . (cons (* 7.25 in) (* 10.5 in)))
    ("monarch" . (cons (* 7.25 in) (* 10.5 in)))
    ("foolscap" . (cons (* 8.27 in) (* 13.0 in)))
    ("folio" . (cons (* 8.27 in) (* 13.0 in)))
    ("super-b" . (cons (* 13.0 in) (* 19.0 in)))
    ("post" . (cons (* 15.5 in) (* 19.5 in)))
    ("crown" . (cons (* 15.0 in) (* 20.0 in)))
    ("large post" . (cons (* 16.5 in) (* 21.0 in)))
    ("demy" . (cons (* 17.5 in) (* 22.5 in)))
    ("medium" . (cons (* 18.0 in) (* 23.0 in)))
    ("broadsheet" . (cons (* 18.0 in) (* 24.0 in)))
    ("royal" . (cons (* 20.0 in) (* 25.0 in)))
    ("elephant" . (cons (* 23.0 in) (* 28.0 in)))
    ("double demy" . (cons (* 22.5 in) (* 35.0 in)))
    ("quad demy" . (cons (* 35.0 in) (* 45.0 in)))
    ("atlas" . (cons (* 26.0 in) (* 34.0 in)))
    ("imperial" . (cons (* 22.0 in) (* 30.0 in)))
    ("antiquarian" . (cons (* 31.0 in) (* 53.0 in)))
    ;; PA4 based sizes
    ("pa0" . (cons (* 840 mm) (* 1120 mm)))
    ("pa1" . (cons (* 560 mm) (* 840 mm)))
    ("pa2" . (cons (* 420 mm) (* 560 mm)))
    ("pa3" . (cons (* 280 mm) (* 420 mm)))
    ("pa4" . (cons (* 210 mm) (* 280 mm)))
    ("pa5" . (cons (* 140 mm) (* 210 mm)))
    ("pa6" . (cons (* 105 mm) (* 140 mm)))
    ("pa7" . (cons (* 70 mm) (* 105 mm)))
    ("pa8" . (cons (* 52 mm) (* 70 mm)))
    ("pa9" . (cons (* 35 mm) (* 52 mm)))
    ("pa10" . (cons (* 26 mm) (* 35 mm)))
    ;; F4 used in southeast Asia and Australia
    ("f4" . (cons (* 210 mm) (* 330 mm)))
    ))

;; todo: take dimension arguments.
(define (lookup-paper-name module name landscape?)
  "Look up @var{name} and return a number pair of width and height,
where @var{landscape?} specifies whether the dimensions should be swapped
unless explicitly overriden in the name."
  (let* ((swapped?
          (cond ((string-suffix? "landscape" name)
                 (set! name
                       (string-trim-right (string-drop-right name 9)))
                 #t)
                ((string-suffix? "portrait" name)
                 (set! name
                       (string-trim-right (string-drop-right name 8)))
                 #f)
                (else landscape?)))
         (is-paper? (module-defined? module 'is-paper))
         (entry (and is-paper?
                     (eval-carefully (assoc-get name paper-alist)
                                     module
                                     #f))))
    (and entry is-paper?
         (if swapped? (cons (cdr entry) (car entry)) entry))))

(define (set-paper-dimensions m w h landscape?)
  "M is a module (i.e. layout->scope_ )"
  (let*
      ;; page layout - what to do with (printer specific!) margin settings?
      ((paper-default (or (lookup-paper-name
                           m (ly:get-option 'paper-size) landscape?)
                          (cons w h)))
       ;; Horizontal margins, marked with #t in the cddr, are stored
       ;; in renamed variables because they must not be overwritten.
       ;; The cadr indicates whether a value is a vertical dimension.
       ;; Output_def::normalize () needs to know
       ;; whether the user set the value or not.
       (scaleable-values '(("left-margin" #f . #t)
                           ("right-margin" #f . #t)
                           ("inner-margin" #f . #t)
                           ("outer-margin" #f . #t)
                           ("binding-offset" #f . #f)
                           ("top-margin" #t . #f)
                           ("bottom-margin" #t . #f)
                           ("indent" #f . #f)
                           ("short-indent" #f . #f)))
       (scaled-values
        (map
         (lambda (entry)
           (let ((entry-symbol
                  (string->symbol
                   (string-append (car entry) "-default")))
                 (vertical? (cadr entry)))
             (cons (if (cddr entry)
                       (string-append (car entry) "-default-scaled")
                       (car entry))
                   (round (* (if vertical? h w)
                             (/ (eval-carefully entry-symbol m 0)
                                ((if vertical? cdr car)
                                 paper-default)))))))
         scaleable-values)))

    (module-define! m 'paper-width w)
    (module-define! m 'paper-height h)
    ;; Sometimes, lilypond-book doesn't estimate a correct line-width.
    ;; Therefore, we need to unset line-width.
    (module-remove! m 'line-width)

    (for-each
     (lambda (value)
       (let ((value-symbol (string->symbol (car value)))
             (number (cdr value)))
         (module-define! m value-symbol number)))
     scaled-values)))

(define (internal-set-paper-size module name landscape?)
  (let* ((entry (lookup-paper-name module name landscape?))
         (is-paper? (module-defined? module 'is-paper)))
    (cond
     ((not is-paper?)
      (ly:warning (_ "This is not a \\layout {} object, ~S") module))
     (entry
      (set-paper-dimensions module (car entry) (cdr entry) landscape?)

      (module-define! module 'papersizename name)
      (module-define! module 'landscape
                      (if landscape? #t #f)))
     (else
      (ly:warning (_ "Unknown paper size: ~a") name)))))

(define-safe-public (set-default-paper-size name . rest)
  (let* ((pap (module-ref (current-module) '$defaultpaper))
         (new-paper (ly:output-def-clone pap))
         (new-scope (ly:output-def-scope new-paper)))
    (internal-set-paper-size
     new-scope
     name
     (memq 'landscape rest))
    (module-set! (current-module) '$defaultpaper new-paper)))

(define-public (set-paper-size name . rest)
  (if (module-defined? (current-module) 'is-paper)
      (internal-set-paper-size (current-module) name
                               (memq 'landscape rest))

      ;;; TODO: should raise (generic) exception with throw, and catch
      ;;; that in parse-scm.cc
      (ly:warning (_ "Must use #(set-paper-size .. ) within \\paper { ... }"))))

(define-public (scale-layout paper scale)
  "Return a clone of the paper, scaled by the given scale factor."
  (let* ((new-paper (ly:output-def-clone paper))
         (dim-vars (ly:output-def-lookup paper 'dimension-variables))
         (old-scope (ly:output-def-scope paper))
         (scope (ly:output-def-scope new-paper)))

    (for-each
     (lambda (v)
       (let* ((var (module-variable old-scope v))
              (val (if (variable? var) (variable-ref var) #f)))

         (if (number? val)
             (module-define! scope v (/ val scale))
             ;; Cannot warn for non-numbers, eg. for paper-width, paper-height.
             )))
     dim-vars)
    ;; Mark the clone.
    (ly:output-def-set-variable! new-paper 'cloned #t)
    new-paper))
