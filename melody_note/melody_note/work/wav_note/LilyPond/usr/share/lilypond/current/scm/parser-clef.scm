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


;; (name . (glyph clef-position transposition))
;;
;; -- the name clefTransposition is a bit misleading. Value 7 means
;; a transposition of an octave, not a seventh.
(define-public supported-clefs
  '(("treble" . ("clefs.G" -2 0))
    ("violin" . ("clefs.G" -2 0))
    ("G" . ("clefs.G" -2 0))
    ("G2" . ("clefs.G" -2 0))
    ("french" . ("clefs.G" -4 0))
    ("soprano" . ("clefs.C" -4 0))
    ("mezzosoprano" . ("clefs.C" -2 0))
    ("alto" . ("clefs.C" 0 0))
    ("C" . ("clefs.C" 0 0))
    ("tenor" . ("clefs.C" 2 0))
    ("baritone" . ("clefs.C" 4 0))
    ("varbaritone" . ("clefs.F" 0 0))
    ("bass" . ("clefs.F" 2 0))
    ("F" . ("clefs.F" 2 0))
    ("subbass" . ("clefs.F" 4 0))
    ("percussion" . ("clefs.percussion" 0 0))
    ("tab" . ("clefs.tab" 0 0))

    ;; should move mensural stuff to separate file?
    ("vaticana-do1" . ("clefs.vaticana.do" -1 0))
    ("vaticana-do2" . ("clefs.vaticana.do" 1 0))
    ("vaticana-do3" . ("clefs.vaticana.do" 3 0))
    ("vaticana-fa1" . ("clefs.vaticana.fa" -1 0))

    ("vaticana-fa2" . ("clefs.vaticana.fa" 1 0))
    ("medicaea-do1" . ("clefs.medicaea.do" -1 0))
    ("medicaea-do2" . ("clefs.medicaea.do" 1 0))
    ("medicaea-do3" . ("clefs.medicaea.do" 3 0))
    ("medicaea-fa1" . ("clefs.medicaea.fa" -1 0))
    ("medicaea-fa2" . ("clefs.medicaea.fa" 1 0))
    ("hufnagel-do1" . ("clefs.hufnagel.do" -1 0))
    ("hufnagel-do2" . ("clefs.hufnagel.do" 1 0))
    ("hufnagel-do3" . ("clefs.hufnagel.do" 3 0))
    ("hufnagel-fa1" . ("clefs.hufnagel.fa" -1 0))
    ("hufnagel-fa2" . ("clefs.hufnagel.fa" 1 0))
    ("hufnagel-do-fa" . ("clefs.hufnagel.do.fa" 4 0))
    ("mensural-c1" . ("clefs.mensural.c" -4 0))
    ("mensural-c2" . ("clefs.mensural.c" -2 0))
    ("mensural-c3" . ("clefs.mensural.c" 0 0))
    ("mensural-c4" . ("clefs.mensural.c" 2 0))
    ("mensural-c5" . ("clefs.mensural.c" 4 0))
    ("blackmensural-c1" . ("clefs.blackmensural.c" -4 0))
    ("blackmensural-c2" . ("clefs.blackmensural.c" -2 0))
    ("blackmensural-c3" . ("clefs.blackmensural.c" 0 0))
    ("blackmensural-c4" . ("clefs.blackmensural.c" 2 0))
    ("blackmensural-c5" . ("clefs.blackmensural.c" 4 0))
    ("mensural-f" . ("clefs.mensural.f" 2 0))
    ("mensural-g" . ("clefs.mensural.g" -2 0))
    ("neomensural-c1" . ("clefs.neomensural.c" -4 0))
    ("neomensural-c2" . ("clefs.neomensural.c" -2 0))
    ("neomensural-c3" . ("clefs.neomensural.c" 0 0))
    ("neomensural-c4" . ("clefs.neomensural.c" 2 0))
    ("neomensural-c5" . ("clefs.neomensural.c" 4 0))
    ("petrucci-c1" . ("clefs.petrucci.c1" -4 0))
    ("petrucci-c2" . ("clefs.petrucci.c2" -2 0))
    ("petrucci-c3" . ("clefs.petrucci.c3" 0 0))
    ("petrucci-c4" . ("clefs.petrucci.c4" 2 0))
    ("petrucci-c5" . ("clefs.petrucci.c5" 4 0))
    ("petrucci-f3" . ("clefs.petrucci.f" 0 0))
    ("petrucci-f4" . ("clefs.petrucci.f" 2 0))
    ("petrucci-f5" . ("clefs.petrucci.f" 4 0))
    ("petrucci-f" . ("clefs.petrucci.f" 2 0))
    ("petrucci-g" . ("clefs.petrucci.g" -2 0))
    ("kievan-do" . ("clefs.kievan.do" 0 0))))

;; "an alist mapping GLYPHNAME to the position of the middle C for
;; that symbol"
(define c0-pitch-alist
  '(("clefs.G" . -4)
    ("clefs.C" . 0)
    ("clefs.F" . 4)
    ("clefs.percussion" . 0)
    ("clefs.tab" . 0 )
    ("clefs.vaticana.do" . 0)
    ("clefs.vaticana.fa" . 4)
    ("clefs.medicaea.do" . 0)
    ("clefs.medicaea.fa" . 4)
    ("clefs.hufnagel.do" . 0)
    ("clefs.hufnagel.fa" . 4)
    ("clefs.hufnagel.do.fa" . 0)
    ("clefs.mensural.c" . 0)
    ("clefs.mensural.f" . 4)
    ("clefs.mensural.g" . -4)
    ("clefs.blackmensural.c" . 0)
    ("clefs.neomensural.c" . 0)
    ("clefs.petrucci.c1" . 0)
    ("clefs.petrucci.c2" . 0)
    ("clefs.petrucci.c3" . 0)
    ("clefs.petrucci.c4" . 0)
    ("clefs.petrucci.c5" . 0)
    ("clefs.petrucci.f" . 4)
    ("clefs.petrucci.g" . -4)
    ("clefs.kievan.do" . 0)))

(define-public (make-clef-set clef-name)
  "Generate the clef setting commands for a clef with name @var{clef-name}."
  (define (make-prop-set props)
    (let ((m (make-music 'PropertySet)))
      (for-each (lambda (x) (set! (ly:music-property m (car x)) (cdr x))) props)
      m))
  (let ((e '())
        (c0 0)
        (oct 0)
        (style 'default)
        (match (string-match "^(.*)([_^])([^0-9a-zA-Z]*)([1-9][0-9]*)([^0-9a-zA-Z]*)$" clef-name)))
    (if match
        (begin
          (set! clef-name (match:substring match 1))
          (set! oct
                (* (if (equal? (match:substring match 2) "^") -1 1)
                   (- (string->number (match:substring match 4)) 1)))
          (set! style
                (cond ((equal? (match:substring match 3) "(") 'parenthesized)
                      ((equal? (match:substring match 3) "[") 'bracketed)
                      (else style)))))
    (set! e (assoc-get clef-name supported-clefs))
    (if e
        (let* ((prop-list `(((symbol . clefGlyph) (value . ,(car e)))
                            ((symbol . middleCClefPosition)
                             (value . ,(+ oct
                                          (cadr e)
                                          (assoc-get (car e) c0-pitch-alist))))
                            ((symbol . clefPosition) (value . ,(cadr e)))
                            ((symbol . clefTransposition) (value . ,(- oct)))))
               ;; the clefTranspositionStyle property is set only when
               ;; not 'default to calm display-lily-tests.scm
               (prop-list (if (eq? style 'default)
                              prop-list
                              (append
                               prop-list
                               `(((symbol . clefTranspositionStyle)
                                  (value . ,style))))))
               (musics (map make-prop-set prop-list))
               (recalc-mid-C (make-music 'ApplyContext))
               (seq (make-music 'SequentialMusic
                                'elements (append musics (list recalc-mid-C))))
               (csp (make-music 'ContextSpeccedMusic)))
          (set! (ly:music-property recalc-mid-C 'procedure) ly:set-middle-C!)
          (context-spec-music seq 'Staff))
        (begin
          (ly:warning (_ "unknown clef type `~a'") clef-name)
          (ly:warning (_ "supported clefs: ~a")
                      (string-join
                       (sort (map car supported-clefs) string<?)))
          (make-music 'Music)))))

(define-public (make-cue-clef-set clef-name)
  "Generate the clef setting commands for a cue clef with name
@var{clef-name}."
  (define cue-clef-map
    '((clefGlyph . cueClefGlyph)
      (middleCClefPosition . middleCCuePosition)
      (clefPosition . cueClefPosition)
      (clefTransposition . cueClefTransposition)
      (clefTranspositionStyle . cueClefTranspositionStyle)))
  (let ((clef (make-clef-set clef-name)))
    (for-each
     (lambda (m)
       (let ((mapped (assq-ref cue-clef-map
                               (ly:music-property m 'symbol))))
         (if mapped
             (set! (ly:music-property m 'symbol) mapped))))
     (extract-named-music clef 'PropertySet))
    clef))

(define-public (make-cue-clef-unset)
  "Reset the clef settings for a cue clef."
  (map-some-music
   (lambda (m)
     (and (eq? (ly:music-property m 'name) 'PropertySet)
          (make-music 'PropertyUnset
                      'symbol (ly:music-property m 'symbol))))
   (make-cue-clef-set "treble_(8)")))

;; a function to add new clefs at runtime
(define-public (add-new-clef clef-name clef-glyph clef-position transposition c0-position)
  "Append the entries for a clef symbol to supported clefs and
@code{c0-pitch-alist}."
  (set! supported-clefs
        (acons clef-name (list clef-glyph clef-position transposition) supported-clefs))
  (set! c0-pitch-alist
        (acons clef-glyph c0-position c0-pitch-alist)))
