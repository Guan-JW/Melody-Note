;;;; This file is part of LilyPond, the GNU music typesetter.
;;;;
;;;; Copyright (C) 2003--2012 Han-Wen Nienhuys <hanwen@xs4all.nl>
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

(define (make-bezier-sandwich-stencil coords thick xext yext)
  (let* ((command-list `(moveto
                         ,(car (list-ref coords 3))
                         ,(cdr (list-ref coords 3))
                         curveto
                         ,(car (list-ref coords 0))
                         ,(cdr (list-ref coords 0))
                         ,(car (list-ref coords 1))
                         ,(cdr (list-ref coords 1))
                         ,(car (list-ref coords 2))
                         ,(cdr (list-ref coords 2))
                         curveto
                         ,(car (list-ref coords 4))
                         ,(cdr (list-ref coords 4))
                         ,(car (list-ref coords 5))
                         ,(cdr (list-ref coords 5))
                         ,(car (list-ref coords 6))
                         ,(cdr (list-ref coords 6))
                         closepath)))
    (ly:make-stencil
     `(path ,thick `(,@' ,command-list) 'round 'round #t)
     xext
     yext)))

(define-public (stack-stencils axis dir padding stils)
  "Stack stencils @var{stils} in direction @var{axis}, @var{dir}, using
@var{padding}."
  (reduce
   (lambda (next front)
     (ly:stencil-stack front axis dir next padding))
   empty-stencil
   stils))

(define-public (stack-stencils-padding-list axis dir paddings stils)
  "Stack stencils @var{stils} in direction @var{axis}, @var{dir}, using
a list of @var{paddings}."
  (if (null? stils)
      empty-stencil
      (fold
       (lambda (next padding front)
         (let ((offset (+ (- (interval-end (ly:stencil-extent front axis))
                             (interval-start (ly:stencil-extent next axis)))
                          padding)))
           (ly:stencil-add
             front
             (ly:stencil-translate-axis next offset axis))))
       (car stils)
       (cdr stils)
       paddings)))

(define-public (centered-stencil stencil)
  "Center stencil @var{stencil} in both the X and Y directions."
  (ly:stencil-aligned-to (ly:stencil-aligned-to stencil X CENTER) Y CENTER))

(define-public (stack-lines dir padding baseline stils)
  "Stack vertically with a baseline skip."
  (reduce-right
   (lambda (next back) (ly:stencil-stack next Y dir back padding baseline))
   empty-stencil
   (map
    (lambda (s)
      ;; X-empty stencils may add vertical space.  A stencil that is
      ;; merely Y-empty counts as horizontal spacing.  Since we want
      ;; those to register as lines of their own (is this a good
      ;; idea?), we make them a separately visible line.
      (if (and (ly:stencil-empty? s Y)
               (not (ly:stencil-empty? s X)))
          (ly:make-stencil (ly:stencil-expr s) (ly:stencil-extent s X) '(0 . 0))
          s))
    stils)))

(define-public (bracketify-stencil stil axis thick protrusion padding)
  "Add brackets around @var{stil}, producing a new stencil."

  (let* ((ext (ly:stencil-extent stil axis))
         (lb (ly:bracket axis ext thick protrusion))
         (rb (ly:bracket axis ext thick (- protrusion))))
    (set! stil
          (ly:stencil-combine-at-edge stil (other-axis axis) 1 rb padding))
    (set! stil
          (ly:stencil-combine-at-edge stil (other-axis axis) -1 lb padding))
    stil))

(define (make-parenthesis-stencil
         y-extent half-thickness width angularity)
  "Create a parenthesis stencil.
@var{y-extent} is the Y extent of the markup inside the parenthesis.
@var{half-thickness} is the half thickness of the parenthesis.
@var{width} is the width of a parenthesis.
The higher the value of number @var{angularity},
the more angular the shape of the parenthesis."
  (let* ((line-width 0.1)
         ;; Horizontal position of baseline that end points run through.
         (base-x
          (if (< width 0)
              (- width)
              0))
         ;; X value farthest from baseline on outside  of curve
         (outer-x (+ base-x width))
         ;; X extent of bezier sandwich centerline curves
         (x-extent (ordered-cons base-x outer-x))
         (bottom-y (interval-start y-extent))
         (top-y (interval-end y-extent))

         (lower-end-point (cons base-x bottom-y))
         (upper-end-point (cons base-x top-y))

         (outer-control-x (+ base-x (* 4/3 width)))
         (inner-control-x (+ outer-control-x
                             (if (< width 0)
                                 half-thickness
                                 (- half-thickness))))

         ;; Vertical distance between a control point
         ;; and the end point it connects to.
         (offset-index (- (* 0.6 angularity) 0.8))
         (lower-control-y (interval-index y-extent offset-index))
         (upper-control-y (interval-index y-extent (- offset-index)))

         (lower-outer-control-point
          (cons outer-control-x lower-control-y))
         (upper-outer-control-point
          (cons outer-control-x upper-control-y))
         (upper-inner-control-point
          (cons inner-control-x upper-control-y))
         (lower-inner-control-point
          (cons inner-control-x lower-control-y)))

    (make-bezier-sandwich-stencil
     (list
      ;; Step 4: curve through inner control points
      ;; to lower end point.
      upper-inner-control-point
      lower-inner-control-point
      lower-end-point
      ;; Step 3: move to upper end point.
      upper-end-point
      ;; Step 2: curve through outer control points
      ;; to upper end point.
      lower-outer-control-point
      upper-outer-control-point
      upper-end-point
      ;; Step 1: move to lower end point.
      lower-end-point)
     line-width
     (interval-widen x-extent (/ line-width 2))
     (interval-widen y-extent (/ line-width 2)))))

(define-public (parenthesize-stencil
                stencil half-thickness width angularity padding)
  "Add parentheses around @var{stencil}, returning a new stencil."
  (let* ((y-extent (ly:stencil-extent stencil Y))
         (lp (make-parenthesis-stencil
              y-extent half-thickness (- width) angularity))
         (rp (make-parenthesis-stencil
              y-extent half-thickness width angularity)))
    (set! stencil (ly:stencil-combine-at-edge stencil X LEFT lp padding))
    (set! stencil (ly:stencil-combine-at-edge stencil X RIGHT rp padding))
    stencil))

(define-public (make-line-stencil width startx starty endx endy)
  "Make a line stencil of given linewidth and set its extents accordingly."
  (let ((xext (cons (min startx endx) (max startx endx)))
        (yext (cons (min starty endy) (max starty endy))))
    (ly:make-stencil
     (list 'draw-line width startx starty endx endy)
     ;; Since the line has rounded edges, we have to / can safely add half the
     ;; width to all coordinates!
     (interval-widen xext (/ width 2))
     (interval-widen yext (/ width 2)))))

(define-public (make-transparent-box-stencil xext yext)
  "Make a transparent box."
  (ly:make-stencil
   (list 'transparent-stencil
         (ly:stencil-expr (make-filled-box-stencil xext yext)))
   xext yext))

(define-public (make-filled-box-stencil xext yext)
  "Make a filled box."

  (ly:make-stencil
   (list 'round-filled-box (- (car xext)) (cdr xext)
         (- (car yext)) (cdr yext) 0.0)
   xext yext))

(define-public (make-circle-stencil radius thickness fill)
  "Make a circle of radius @var{radius} and thickness @var{thickness}."
  (let*
      ((out-radius (+ radius (/ thickness 2.0))))

    (ly:make-stencil
     (list 'circle radius thickness fill)
     (cons (- out-radius) out-radius)
     (cons (- out-radius) out-radius))))

(define-public (make-oval-stencil x-radius y-radius thickness fill)
  "Make an oval from two Bezier curves, of x@tie{}radius @var{x-radius},
y@tie{}radius @code{y-radius}, and thickness @var{thickness} with fill
defined by @code{fill}."
  (let*
      ((x-out-radius (+ x-radius (/ thickness 2.0)))
       (y-out-radius (+ y-radius (/ thickness 2.0)))
       (x-max x-radius)
       (x-min (- x-radius))
       (y-max y-radius)
       (y-min (- y-radius))
       (commands `(,(list 'moveto x-max 0)
                   ,(list 'curveto x-max y-max x-min y-max x-min 0)
                   ,(list 'curveto x-min y-min x-max y-min x-max 0)
                   ,(list 'closepath)))
       (command-list (fold-right append '() commands)))
    (ly:make-stencil
     `(path ,thickness `(,@',command-list) 'round 'round ,fill)
     (cons (- x-out-radius) x-out-radius)
     (cons (- y-out-radius) y-out-radius))))

(define-public
  (make-partial-ellipse-stencil
   x-radius y-radius start-angle end-angle thick connect fill)
  "Create an elliptical arc
@var{x-radius} is the X radius of the arc.
@var{y-radius} is the Y radius of the arc.
@var{start-angle} is the starting angle of the arc in degrees.
@var{end-angle} is the ending angle of the arc in degrees.
@var{thick} is the thickness of the line.
@var{connect} is a boolean flag indicating if the end should
be connected to the start by a line.
@var{fill} is a boolean flag indicating if the shape should be filled."
  (define (make-radius-list x-radius y-radius)
    "Makes a list of angle/radius pairs at intervals of PI/2 for
the partial ellipse until 7*PI/2.  For example, in pseudo-code:
> (make-radius-list 2 3)\
\n((0.0 . 2) (PI/2 . 3) (PI . -2) (3*PI/2 . -3)\
\n(2*PI . 2) (5*PI/2 . 3) (3*PI . -2) (7*PI/2 . -3))
"
    (append-map
     (lambda (adder)
       (map (lambda (quadrant)
              (cons (+ adder (car quadrant))
                    (cdr quadrant)))
            `((0.0 . (,x-radius . 0.0))
              (,PI-OVER-TWO . (0.0 . ,y-radius))
              (,PI . (,(- x-radius) . 0.0))
              (,THREE-PI-OVER-TWO . (0.0 . ,(- y-radius))))))
     `(0.0 ,TWO-PI)))

  (define
    (insert-in-ordered-list ordering-function value inlist cutl? cutr?)
    "Insert @var{value} in ordered list @var{inlist}. If @var{cutl?}, we
cut away any parts of @var{inlist} before @var{value}. @var{cutr?} works
the same way but for the right side. For example:
> (insert-in-ordered-list < 4 '(1 2 3 6 7) #f #f)
'(1 2 3 4 6 7)
> (insert-in-ordered-list < 4 '(1 2 3 6 7) #t #f)
'(4 6 7)
> (insert-in-ordered-list < 4 '(1 2 3 6 7) #f #t)
'(1 2 3 4)
"
    (define
      (helper ordering-function value left-list right-list cutl? cutr?)
      (if (null? right-list)
          (append
           (if cutl? '() left-list)
           (list value)
           (if cutr? '() right-list))
          (if (ordering-function value (car right-list))
              (append
               (if cutl? '() left-list)
               (list value)
               (if cutr? '() right-list))
              (helper
               ordering-function
               value
               (append left-list (list (car right-list)))
               (cdr right-list)
               cutl?
               cutr?))))
    (helper ordering-function value '() inlist cutl? cutr?))

  (define (ordering-function-1 a b) (car< a b))

  (define (ordering-function-2 a b) (car<= a b))

  (define (min-max-crawler min-max side l)
    "Apply function @var{side} to each member of list and
then reduce using @var{min-max}:
> (min-max-crawler min car '((0 . 3) (-1 . 4) (1 . 2)))
-1
> (min-max-crawler min cdr '((0 . 3) (-1 . 4) (1 . 2)))
2
"
    (reduce min-max
            (if (eq? min-max min) 100000 -100000)
            (map side l)))

  (let*
      (;; the outside limit of the x-radius
       (x-out-radius (+ x-radius (/ thick 2.0)))
       ;; the outside limit of the y-radius
       (y-out-radius (+ y-radius (/ thick 2.0)))
       ;; end angle to radians
       (new-end-angle (angle-0-2pi (degrees->radians end-angle)))
       ;; length of the radius at the end angle
       (end-radius (ellipse-radius x-out-radius y-out-radius new-end-angle))
       ;; start angle to radians
       (new-start-angle (angle-0-2pi (degrees->radians start-angle)))
       ;; length of the radius at the start angle
       (start-radius (ellipse-radius x-out-radius y-out-radius new-start-angle))
       ;; points that the arc passes through at 90 degree intervals
       (radius-list (make-radius-list x-out-radius y-out-radius))
       ;; rectangular coordinates of arc endpoint
       (rectangular-end-radius (polar->rectangular end-radius end-angle))
       ;; rectangular coordinates of arc begin point
       (rectangular-start-radius (polar->rectangular start-radius start-angle))
       ;; we want the end angle to always be bigger than the start angle
       ;; so we redefine it here just in case it is less
       (new-end-angle
        (if (<= new-end-angle new-start-angle)
            (+ TWO-PI new-end-angle)
            new-end-angle))
       ;; all the points that may be extrema of the arc
       ;; this is the 90 degree points plus the beginning and end points
       ;; we use this to calculate extents
       (possible-extrema
        (insert-in-ordered-list
         ordering-function-2
         (cons new-end-angle rectangular-end-radius)
         (insert-in-ordered-list
          ordering-function-1
          (cons new-start-angle rectangular-start-radius)
          radius-list
          #t
          #f)
         #f
         #t)))
    (ly:make-stencil
     (list
      'partial-ellipse
      x-radius
      y-radius
      start-angle
      end-angle
      thick
      connect
      fill)
     ;; we know the extrema points by crawling through the
     ;; list of possible extrema and finding the min and max
     ;; for x and y
     (cons (min-max-crawler min cadr possible-extrema)
           (min-max-crawler max cadr possible-extrema))
     (cons (min-max-crawler min cddr possible-extrema)
           (min-max-crawler max cddr possible-extrema)))))

(define (line-part-min-max x1 x2)
  (list (min x1 x2) (max x1 x2)))

(define (bezier-part-min-max x1 x2 x3 x4)
  ((lambda (x) (list (reduce min 10000 x) (reduce max -10000 x)))
   (map
    (lambda (x)
      (+ (* x1 (expt (- 1 x) 3))
         (+ (* 3 (* x2 (* (expt (- 1 x) 2) x)))
            (+ (* 3 (* x3 (* (- 1 x) (expt x 2))))
               (* x4 (expt x 3))))))
    (if (< (+ (expt x2 2) (+ (expt x3 2) (* x1 x4)))
           (+ (* x1 x3) (+ (* x2 x4) (* x2 x3))))
        (list 0.0 1.0)
        (filter
         (lambda (x) (and (>= x 0) (<= x 1)))
         (append
          (list 0.0 1.0)
          (map (lambda (op)
                 (if (not (eqv? 0.0
                                (exact->inexact (- (+ x1 (* 3 x3)) (+ x4 (* 3 x2))))))
                     ;; Zeros of the bezier curve
                     (/ (+ (- x1 (* 2 x2))
                           (op x3
                               (sqrt (- (+ (expt x2 2)
                                           (+ (expt x3 2) (* x1 x4)))
                                        (+ (* x1 x3)
                                           (+ (* x2 x4) (* x2 x3)))))))
                        (- (+ x1 (* 3 x3)) (+ x4 (* 3 x2))))
                     ;; Apply L'hopital's rule to get the zeros if 0/0
                     (* (op 0 1)
                        (/ (/ (- x4 x3) 2)
                           (sqrt (- (+ (* x2 x2)
                                       (+ (* x3 x3) (* x1 x4)))
                                    (+ (* x1 x3)
                                       (+ (* x2 x4) (* x2 x3)))))))))
               (list + -))))))))

(define (bezier-min-max x1 y1 x2 y2 x3 y3 x4 y4)
  (map (lambda (x)
         (apply bezier-part-min-max x))
       `((,x1 ,x2 ,x3 ,x4) (,y1 ,y2 ,y3 ,y4))))

(define (line-min-max x1 y1 x2 y2)
  (map (lambda (x)
         (apply line-part-min-max x))
       `((,x1 ,x2) (,y1 ,y2))))

(define (path-min-max origin pointlist)

  ((lambda (x)
     (list
      (reduce min +inf.0 (map caar x))
      (reduce max -inf.0 (map cadar x))
      (reduce min +inf.0 (map caadr x))
      (reduce max -inf.0 (map cadadr x))))
   (map (lambda (x)
          (if (= (length x) 8)
              (apply bezier-min-max x)
              (apply line-min-max x)))
        (map (lambda (x y)
               (append (list (cadr (reverse x)) (car (reverse x))) y))
             (append (list origin)
                     (reverse (cdr (reverse pointlist)))) pointlist))))

(define-public (make-connected-path-stencil pointlist thickness
                                            x-scale y-scale connect fill)
  "Make a connected path described by the list @var{pointlist}, with
thickness @var{thickness}, and scaled by @var{x-scale} in the X direction
and @var{y-scale} in the Y direction.  @var{connect} and @var{fill} are
boolean arguments that specify if the path should be connected or filled,
respectively."

  ;; paths using this routine are designed to begin at point '(0 . 0)
  (let* ((origin (list 0 0))
         (boundlist (path-min-max origin pointlist))
         ;; modify pointlist to scale the coordinates
         (path (map (lambda (x)
                      (apply
                       (if (= 6 (length x))
                           (lambda (x1 x2 x3 x4 x5 x6)
                             (list 'curveto
                                   (* x1 x-scale)
                                   (* x2 y-scale)
                                   (* x3 x-scale)
                                   (* x4 y-scale)
                                   (* x5 x-scale)
                                   (* x6 y-scale)))
                           (lambda (x1 x2)
                             (list 'lineto
                                   (* x1 x-scale)
                                   (* x2 y-scale))))
                       x))
                    pointlist))
         ;; a path must begin with a `moveto'
         (prepend-origin (cons (cons 'moveto origin) path))
         ;; if this path is connected, add closepath to the end
         (final-path (if connect
                         (append prepend-origin (list '(closepath)))
                         prepend-origin))
         (command-list (concatenate final-path)))
    (ly:make-stencil
     `(path ,thickness
            `(,@',command-list)
            'round
            'round
            ,(if fill #t #f))
     (coord-translate
      ((if (< x-scale 0) reverse-interval identity)
       (cons (* x-scale (list-ref boundlist 0))
             (* x-scale (list-ref boundlist 1))))
      `(,(/ thickness -2) . ,(/ thickness 2)))
     (coord-translate
      ((if (< y-scale 0) reverse-interval identity)
       (cons (* y-scale (list-ref boundlist 2))
             (* y-scale (list-ref boundlist 3))))
      `(,(/ thickness -2) . ,(/ thickness 2))))))

(define-public (make-ellipse-stencil x-radius y-radius thickness fill)
  "Make an ellipse of x@tie{}radius @var{x-radius}, y@tie{}radius
@code{y-radius}, and thickness @var{thickness} with fill defined by
@code{fill}."
  (let*
      ((x-out-radius (+ x-radius (/ thickness 2.0)))
       (y-out-radius (+ y-radius (/ thickness 2.0))) )

    (ly:make-stencil
     (list 'ellipse x-radius y-radius thickness fill)
     (cons (- x-out-radius) x-out-radius)
     (cons (- y-out-radius) y-out-radius))))

(define-public (box-grob-stencil grob)
  "Make a box of exactly the extents of the grob.  The box precisely
encloses the contents."
  (let* ((xext (ly:grob-extent grob grob 0))
         (yext (ly:grob-extent grob grob 1))
         (thick 0.01))

    (ly:stencil-add
     (make-filled-box-stencil xext (cons (- (car yext) thick) (car yext)))
     (make-filled-box-stencil xext (cons (cdr yext) (+ (cdr yext) thick)))
     (make-filled-box-stencil (cons (cdr xext) (+ (cdr xext) thick)) yext)
     (make-filled-box-stencil (cons (- (car xext) thick) (car xext)) yext))))

;; TODO merge this and prev function.
(define-public (box-stencil stencil thickness padding)
  "Add a box around @var{stencil}, producing a new stencil."
  (let* ((x-ext (interval-widen (ly:stencil-extent stencil 0) padding))
         (y-ext (interval-widen (ly:stencil-extent stencil 1) padding))
         (y-rule (make-filled-box-stencil (cons 0 thickness) y-ext))
         (x-rule (make-filled-box-stencil
                  (interval-widen x-ext thickness) (cons 0 thickness))))
    (set! stencil (ly:stencil-combine-at-edge stencil X 1 y-rule padding))
    (set! stencil (ly:stencil-combine-at-edge stencil X -1 y-rule padding))
    (set! stencil (ly:stencil-combine-at-edge stencil Y 1 x-rule 0.0))
    (set! stencil (ly:stencil-combine-at-edge stencil Y -1 x-rule 0.0))
    stencil))

(define-public (circle-stencil stencil thickness padding)
  "Add a circle around @var{stencil}, producing a new stencil."
  (let* ((x-ext (ly:stencil-extent stencil X))
         (y-ext (ly:stencil-extent stencil Y))
         (diameter (max (interval-length x-ext)
                        (interval-length y-ext)))
         (radius (+ (/ diameter 2) padding thickness))
         (circle (make-circle-stencil radius thickness #f)))

    (ly:stencil-add
     stencil
     (ly:stencil-translate circle
                           (cons
                            (interval-center x-ext)
                            (interval-center y-ext))))))

(define-public (oval-stencil stencil thickness x-padding y-padding)
  "Add an oval around @code{stencil}, padded by the padding pair,
producing a new stencil."
  (let* ((x-ext (ly:stencil-extent stencil X))
         (y-ext (ly:stencil-extent stencil Y))
         (x-length (+ (interval-length x-ext) x-padding thickness))
         (y-length (+ (interval-length y-ext) y-padding thickness))
         (x-radius (* 0.707 x-length) )
         (y-radius (* 0.707 y-length) )
         (oval (make-oval-stencil x-radius y-radius thickness #f)))

    (ly:stencil-add
     stencil
     (ly:stencil-translate oval
                           (cons
                            (interval-center x-ext)
                            (interval-center y-ext))))))

(define-public (ellipse-stencil stencil thickness x-padding y-padding)
  "Add an ellipse around @var{stencil}, padded by the padding pair,
producing a new stencil."
  (let* ((x-ext (ly:stencil-extent stencil X))
         (y-ext (ly:stencil-extent stencil Y))
         (x-length (+ (interval-length x-ext) x-padding thickness))
         (y-length (+ (interval-length y-ext) y-padding thickness))
         ;; (aspect-ratio (/ x-length y-length))
         (x-radius (* 0.707 x-length) )
         (y-radius (* 0.707 y-length) )
         ;; (diameter (max (- (cdr x-ext) (car x-ext))
         ;;             (- (cdr y-ext) (car y-ext))))
         ;; radius (+ (/ diameter 2) padding thickness))
         (ellipse (make-ellipse-stencil x-radius y-radius thickness #f)))

    (ly:stencil-add
     stencil
     (ly:stencil-translate ellipse
                           (cons
                            (interval-center x-ext)
                            (interval-center y-ext))))))

(define-public (rounded-box-stencil stencil thickness padding blot)
  "Add a rounded box around @var{stencil}, producing a new stencil."

  (let* ((xext (interval-widen (ly:stencil-extent stencil 0) padding))
         (yext (interval-widen (ly:stencil-extent stencil 1) padding))
         (min-ext (min (-(cdr xext) (car xext)) (-(cdr yext) (car yext))))
         (ideal-blot (min blot (/ min-ext 2)))
         (ideal-thickness (min thickness (/ min-ext 2)))
         (outer (ly:round-filled-box
                 (interval-widen xext ideal-thickness)
                 (interval-widen yext ideal-thickness)
                 ideal-blot))
         (inner (ly:make-stencil (list 'color (x11-color 'white)
                                       (ly:stencil-expr (ly:round-filled-box
                                                         xext yext (- ideal-blot ideal-thickness)))))))
    (set! stencil (ly:stencil-add outer inner))
    stencil))

(define-public (stencil-with-color stencil color)
  (ly:make-stencil
   (list 'color color (ly:stencil-expr stencil))
   (ly:stencil-extent stencil X)
   (ly:stencil-extent stencil Y)))

(define-public (stencil-whiteout stencil)
  (let*
      ((x-ext (ly:stencil-extent stencil X))
       (y-ext (ly:stencil-extent stencil Y))

       )

    (ly:stencil-add
     (stencil-with-color (ly:round-filled-box x-ext y-ext 0.0)
                         white)
     stencil)
    ))

(define-public (arrow-stencil-maker start? end?)
  "Return a function drawing a line from current point to @code{destination},
with optional arrows of @code{max-size} on start and end controlled by
@var{start?} and @var{end?}."
  (lambda (destination max-size)
    (let*
        ((e_x 1+0i)
         (e_y 0+1i)
         (distance (sqrt (+ (* (car destination) (car destination))
                            (* (cdr destination) (cdr destination)))))
         (size (min max-size (/ distance 3)))
         (rotate (lambda (z ang)
                   (* (make-polar 1 ang)
                      z)))
         (complex-to-offset (lambda (z)
                              (list (real-part z) (imag-part z))))

         (z-dest (+ (* e_x (car destination)) (* e_y (cdr destination))))
         (e_z (/ z-dest (magnitude z-dest)))
         (triangle-points (list
                           (* size -1+0.25i)
                           0
                           (* size -1-0.25i)))
         (p1s (map (lambda (z)
                     (+ z-dest (rotate z (angle z-dest))))
                   triangle-points))
         (p2s (map (lambda (z)
                     (rotate z (angle (- z-dest))))
                   triangle-points))
         (null (cons 0 0))
         (arrow-1
          (ly:make-stencil
           `(polygon (quote ,(append-map complex-to-offset p1s))
                     0.0
                     #t) null null))
         (arrow-2
          (ly:make-stencil
           `(polygon (quote ,(append-map complex-to-offset p2s))
                     0.0
                     #t) null null ) )
         (thickness (min (/ distance 12) 0.1))
         (shorten-line (min (/ distance 3) 0.5))
         (start (complex-to-offset (/ (* e_z shorten-line) 2)))
         (end (complex-to-offset (- z-dest (/ (* e_z shorten-line) 2))))

         (line (ly:make-stencil
                `(draw-line ,thickness
                            ,(car start) ,(cadr start)
                            ,(car end) ,(cadr end)
                            )
                (cons (min 0 (car destination))
                      (min 0 (cdr destination)))
                (cons (max 0 (car destination))
                      (max 0 (cdr destination)))))

         (result
          (ly:stencil-add
           (if start? arrow-2 empty-stencil)
           (if end? arrow-1 empty-stencil)
           line)))

      result)))

(define-public dimension-arrows (arrow-stencil-maker #t #t))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ANNOTATIONS
;;
;; annotations are arrows indicating the numerical value of
;; spacing variables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define*-public (annotate-y-interval layout name extent is-length
                                     #:key (color darkblue))
  (let ((text-props (cons '((font-size . -3)
                            (font-family . typewriter))
                          (layout-extract-page-properties layout)))
        (annotation #f))
    (define (center-stencil-on-extent stil)
      (ly:stencil-translate (ly:stencil-aligned-to stil Y CENTER)
                            (cons 0 (interval-center extent))))
    ;; do something sensible for 0,0 intervals.
    (set! extent (interval-widen extent 0.001))
    (if (not (interval-sane? extent))
        (set! annotation (interpret-markup
                          layout text-props
                          (make-simple-markup (simple-format #f "~a: NaN/inf" name))))
        (let ((text-stencil (interpret-markup
                             layout text-props
                             (markup #:whiteout #:simple name)))
              (dim-stencil (interpret-markup
                            layout text-props
                            (markup #:whiteout
                                    #:simple (cond
                                              ((interval-empty? extent)
                                               "empty")
                                              (is-length
                                               (ly:format "~$" (interval-length extent)))
                                              (else
                                               (ly:format "(~$,~$)"
                                                          (car extent) (cdr extent)))))))
              (arrows (ly:stencil-translate-axis
                       (dimension-arrows (cons 0 (interval-length extent)) 1.0)
                       (interval-start extent) Y)))
          (set! annotation
                (center-stencil-on-extent text-stencil))
          (set! annotation
                (ly:stencil-combine-at-edge arrows X RIGHT annotation 0.5))
          (set! annotation
                (ly:stencil-combine-at-edge annotation X LEFT
                                            (center-stencil-on-extent dim-stencil)
                                            0.5))
          (set! annotation
                (stencil-with-color annotation color))))
    annotation))


;; TODO: figure out how to annotate padding nicely
;; TODO: emphasize either padding or min-dist depending on which constraint was active
(define*-public (annotate-spacing-spec layout spacing-spec start-Y-offset next-staff-Y
                                       #:key (base-color blue))
  (let* ((get-spacing-var (lambda (sym) (assoc-get sym spacing-spec 0.0)))
         (space (get-spacing-var 'basic-distance))
         (padding (get-spacing-var 'padding))
         (min-dist (get-spacing-var 'minimum-distance))
         (contrast-color (append (cdr base-color) (list (car base-color))))
         (min-dist-blocks (<= (- start-Y-offset min-dist) next-staff-Y))
         (min-dist-color (if min-dist-blocks contrast-color base-color))
         (basic-annotation (annotate-y-interval layout
                                                "basic-dist"
                                                (cons (- start-Y-offset space) start-Y-offset)
                                                #t
                                                #:color (map (lambda (x) (* x 0.25)) base-color)))
         (min-annotation (annotate-y-interval layout
                                              "min-dist"
                                              (cons (- start-Y-offset min-dist) start-Y-offset)
                                              #t
                                              #:color min-dist-color))
         (extra-annotation (annotate-y-interval layout
                                                "extra dist"
                                                (cons next-staff-Y (- start-Y-offset min-dist))
                                                #t
                                                #:color (map (lambda (x) (* x 0.5)) min-dist-color))))

    (stack-stencils X RIGHT 0.0
                    (list
                     basic-annotation
                     (if min-dist-blocks
                         min-annotation
                         (ly:stencil-add min-annotation extra-annotation))))))

(define-public (eps-file->stencil axis size file-name)
  (let*
      ((contents (ly:gulp-file file-name))
       (bbox (get-postscript-bbox (car (string-split contents #\nul))))
       (bbox-size (if (= axis X)
                      (- (list-ref bbox 2) (list-ref bbox 0))
                      (- (list-ref bbox 3) (list-ref bbox 1))
                      ))
       (factor (if (< 0 bbox-size)
                   (exact->inexact (/ size bbox-size))
                   0))
       (scaled-bbox
        (map (lambda (x) (* factor x)) bbox))
       ;; We need to shift the whole eps to (0,0), otherwise it will appear
       ;; displaced in lilypond (displacement will depend on the scaling!)
       (translate-string (ly:format "~a ~a translate" (- (list-ref bbox 0)) (- (list-ref bbox 1))))
       (clip-rect-string (ly:format
                          "~a ~a ~a ~a rectclip"
                          (list-ref bbox 0)
                          (list-ref bbox 1)
                          (- (list-ref bbox 2) (list-ref bbox 0))
                          (- (list-ref bbox 3) (list-ref bbox 1)))))


    (if bbox
        (ly:make-stencil
         (list
          'embedded-ps
          (string-append
           (ly:format
            "
gsave
currentpoint translate
BeginEPSF
~a dup scale
~a
~a
%%BeginDocument: ~a
"         factor translate-string  clip-rect-string

file-name
)
           contents
           "%%EndDocument
EndEPSF
grestore
"))
         ;; Stencil starts at (0,0), since we have shifted the eps, and its
         ;; size is exactly the size of the scaled bounding box
         (cons 0 (- (list-ref scaled-bbox 2) (list-ref scaled-bbox 0)))
         (cons 0 (- (list-ref scaled-bbox 3) (list-ref scaled-bbox 1))))

        (ly:make-stencil "" '(0 . 0) '(0 . 0)))
    ))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; output signatures.

(define-public (write-system-signatures basename paper-systems count)
  (if (pair? paper-systems)
      (begin
        (let*
            ((outname (simple-format #f "~a-~a.signature" basename count)) )

          (ly:message "Writing ~a" outname)
          (write-system-signature outname (car paper-systems))
          (write-system-signatures basename (cdr paper-systems) (1+ count))))))

(use-modules (scm paper-system))
(define-public (write-system-signature filename paper-system)
  (define (float? x)
    (and (number? x) (inexact? x)))

  (define system-grob
    (paper-system-system-grob paper-system))

  (define output (open-output-file filename))

  ;; todo: optionally use a command line flag? Or just junk this?
  (define compare-expressions #f)
  (define (strip-floats expr)
    "Replace floats by #f"
    (cond
     ((float? expr) #f)
     ((ly:font-metric? expr) (ly:font-name expr))
     ((pair? expr) (cons (strip-floats (car expr))
                         (strip-floats (cdr expr))))
     (else expr)))

  (define (fold-false-pairs expr)
    "Try to remove lists of #f as much as possible."
    (if (pair? expr)
        (let*
            ((first (car expr))
             (rest (fold-false-pairs (cdr expr))))

          (if first
              (cons (fold-false-pairs first) rest)
              rest))
        expr))

  (define (raw-string expr)
    "escape quotes and slashes for python consumption"
    (regexp-substitute/global #f "[@\n]" (simple-format #f "~a" expr) 'pre " " 'post))

  (define (raw-pair expr)
    (simple-format #f "~a ~a"
                   (car expr) (cdr expr)))

  (define (found-grob expr)
    (let*
        ((grob (car expr))
         (rest (cdr expr))
         (collected '())
         (cause (event-cause grob))
         (input (if (ly:stream-event? cause) (ly:event-property cause 'origin) #f))
         (location (if (ly:input-location? input) (ly:input-file-line-char-column input) '()))

         ;; todo: use stencil extent if available.
         (x-ext (ly:grob-extent grob system-grob X))
         (y-ext (ly:grob-extent grob system-grob Y))
         (expression-skeleton
          (if compare-expressions
              (interpret-for-signature
               #f (lambda (e)
                    (set! collected (cons e collected)))
               rest)
              "")))

      (simple-format output
                     "~a@~a@~a@~a@~a\n"
                     (cdr (assq 'name (ly:grob-property grob 'meta) ))
                     (raw-string location)
                     (raw-pair (if (interval-empty? x-ext) '(1 . -1) x-ext))
                     (raw-pair (if (interval-empty? y-ext) '(1 . -1) y-ext))
                     (raw-string collected))
      ))

  (define (interpret-for-signature escape collect expr)
    (define (interpret expr)
      (let*
          ((head (if (pair? expr)
                     (car expr)
                     #f)))

        (cond
         ((eq? head 'grob-cause) (escape (cdr expr)))
         ((eq? head 'color) (interpret (caddr expr)))
         ((eq? head 'rotate-stencil) (interpret (caddr expr)))
         ((eq? head 'translate-stencil) (interpret (caddr expr)))
         ((eq? head 'combine-stencil)
          (for-each (lambda (e) (interpret e))  (cdr expr)))
         (else
          (collect (fold-false-pairs (strip-floats expr))))

         )))

    (interpret expr))

  (if (ly:grob? system-grob)
      (begin
        (display (simple-format #f "# Output signature\n# Generated by LilyPond ~a\n" (lilypond-version))
                 output)
        (interpret-for-signature found-grob (lambda (x) #f)
                                 (ly:stencil-expr
                                  (paper-system-stencil paper-system)))))

  ;; should be superfluous, but leaking "too many open files"?
  (close-port output))
