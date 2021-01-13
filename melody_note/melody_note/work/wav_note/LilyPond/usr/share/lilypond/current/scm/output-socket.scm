;;;; output-socket.scm
;;;;
;;;; implement network-based output (socket) in Scheme

(define-module (scm output-socket)
  #:re-export (quote))

(use-modules (guile)
             (srfi srfi-1)
             (srfi srfi-13)
             (lily))


(define format ergonomic-simple-format)

(define (event-cause grob)
  (let*
      ((cause (ly:grob-property grob 'cause)))

    (if (ly:stream-event? cause)
        cause
        #f)))

(define (grob-bbox grob offset)
  (let*
      ((x-ext (ly:grob-extent grob grob X))
       (y-ext (ly:grob-extent grob grob Y))
       (x (car offset))
       (y (cdr offset)))

    (if (interval-empty? x-ext)
        (set! x-ext '(0 . 0)))

    (if (interval-empty? y-ext)
        (set! y-ext '(0 . 0)))

    (list (+ x (car x-ext))
          (+ y (car y-ext))
          (+ x (cdr x-ext))
          (+ y (cdr y-ext)))))

(define (escape-string str)
  (string-regexp-substitute
   " " "\\040"
   (string-regexp-substitute "\"" "\\\"" str)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; stencil commands
;;;

(define (draw-line thick x1 y1 x2 y2)
  (format #f "drawline ~a ~a ~a ~a ~a"
          thick x1 y2 x2 y2))

(define (grob-cause offset grob)
  (let*
      ((cause (event-cause grob))
       (tag (if (and cause (integer? (ly:event-property cause 'input-tag)))
                (ly:event-property cause 'input-tag)
                -1))
       (name (assoc-get 'name (ly:grob-property grob 'meta))))

    (apply format #f
           "cause ~a \"~a\" ~a ~a ~a ~a\n" tag name
           (grob-bbox grob offset))))

(define (named-glyph font glyph)
  (format #f "glyphshow ~a \"~a\" ~a \"~a\""
          (ly:font-glyph-name-to-charcode font glyph)
          (ly:font-name font)
          (modified-font-metric-font-scaling font)
          glyph))

(define (no-origin)
  "nocause\n")

(define (placebox x y s)
  (if (not (string-null? s))
      (format #f "at ~a ~a ~a\n" x y s)
      ""))

(define (polygon xy-coords blot do-fill)
  (format #f "polygon ~a ~a ~a"
          blot
          (if do-fill "True" "False")
          (string-join (map number->string xy-coords))))

(define (round-filled-box breapth width depth height blot-diameter)
  (format #f "draw_round_box ~a ~a ~a ~a ~a"
          breapth width depth height blot-diameter))

(define (utf-8-string descr string)
  (format #f "utf-8 \"~a\" \"~a\""
          (escape-string descr)
          ;; don't want unescaped spaces.
          (escape-string string)))
