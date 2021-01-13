%
% Copyright (C) 2008, 2009, 2010, 2011 NICTA
% Author: Peter Chubb <peter.chubb AT nicta.com.au>
% $Id: articulate.ly,v 1.7 2011-03-24 00:40:00 peterc Exp $
%
%
%  This program is free software; you can redistribute it and/or modify
%  it under the terms of the GNU General Public License, version 3,
%  as published by the Free Software Foundation.
%
%  WARNING: this file under GPLv3 only, not GPLv3+
%
%  This program is distributed in the hope that it will be useful,
%  but WITHOUT ANY WARRANTY; without even the implied warranty of
%  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
%  See the GNU General Public License for more details.  It is
%  available in the Lilypond source tree, or at
%  http://www.gnu.org/licenses/gpl-3.0.html
%
% This script tries to make MIDI output from LilyPond a little more realistic.
% It tries to take articulations (slurs, staccato, etc) into account, by
% replacing notes  with sequential music of suitably time-scaled note plus
% skip.
%
% It also tries to unfold trills turns etc., and take rallentendo
% and accelerando into account.
%
% As my scheme knowledge is poor (I was teaching myself as I went), there
% is much scope for improvement.

%
%%%USAGE
% In the \score section do:
% \articulate <<
%	all the rest of the score
% >>
% or use the lilywrap script.
%
% TO DO (prioritised, the ones that'll make the most difference first)
%
% * Dynamics.
%   * Fix quantisation for dynamics on single note (replace note
%     with tied 128th notes?) -- started, needs work.
%   * Make \fp do the right thing (loud start, then quiet).
%
% * Inegalite.  Notes on-beat steal time from notes off-beat.
%   Degree of stealing is a parameter: from 1.0 (straight)
%   to 1.5 (extreme swing).  Also fix tenuto to use this.
%
% * add accel (to match rall), and molto rall. I've never seen
%   molto accel but some composer somewhere has probably used it.
%
% * Fermata, and Fermata Lunga
% * Add more synonyms for accel and rall: rit ritard stringendo
%
% * Phrasing.
%   * Rall at end of piece
%   * Very slight accel into a phrase, rall out of it.
%   * Dynamics during a phrase????  unclear how these should be in
%     the general case
%
% * Trill algorithm needs work.
%
% * Cope with more ornaments/articulations.
%    inverted-turns, etc.
%   -- accent needs better control of dynamics.
%   -- Articulations: mezzo-staccato, portato.
%   -- Handling of generic ornaments (in lily, `\stopped'; in
%		most early music:  ornament this note (trill, turn
%		or mordent as the player wishes))
% * Automatic gruppetto at end of trill; better handling of
%      initial/final grace notes on trill
% * Automatic ornaments.
%   * Spot cadences and ornament
%   * Look for quaver-dotted note for trills, for example.
%   * Fill in steps. (Needs lookahead/lookbehind.)
% * `afterturn' -- a turn after the start of a note.
% * accidentals for trills and turns

% CHANGELOG
%  * David Kastrup: basic 2.15.28 compatibility by using event-chord-wrap!
%    This should really be done by rewriting the code more thoroughly.
%  * From Iain Nicol: appoggiatura timings were out; add staccatissimo; fix
%    trillSpanner endpoints.
%  * Also handle Breathing events (by throwing them away).  This isn't ideal;
%    one should really shorten the note before a little.  But I don't know
%    how to do lookahead in scheme.
%  * Also ignore explicit line breaks.
%  * Add Mordents (reported by Patrick Karl)
%

\version "2.17.11"

#(use-modules (srfi srfi-1))
#(use-modules (srfi srfi-11))
#(use-modules (ice-9 debug))
#(use-modules (scm display-lily))

% PARAMETERS
% How much to compress notes marked Staccato.  CPE Bach says `as short as
% may conveniently be played, as if the keys were too hot to touch'.
% Most modern sources say 1/2 the notated length of a note.
#(define ac:staccatoFactor '(1 . 2))

% How much to compress notes marked staccatissimo.
#(define ac:staccatissimoFactor '(1 . 4))

% And tenuto (if we ever implement time stealing, this should be >1.0)
#(define ac:tenutoFactor '(1 . 1))

% How much to articulate normal notes.  CPE Bach says 1/2 (and
% staccato should be `as short as may conveniently be played') but this
% sounds too short for modern music.  7/8 sounds about right.
#(define ac:normalFactor '(7 . 8))

% How much to slow down for a rall. or a poco rall.
% (or speed up for accel or poco accel)
#(define ac:rallFactor (ly:make-moment 60/100)) % 40% slowdown
#(define ac:pocoRallFactor (ly:make-moment 90/100)) % 10% slowdown

% The absolute time for a twiddle in a trill, in minutes.
% Start with 1/4 seconds == 1/240 minutes
#(define ac:maxTwiddleTime (ly:make-moment 1/240))

% How long ordinary grace notes should be relative to their notated
% duration.  9/40 is LilyPond's built-in behaviour for MIDI output
% (though the notation reference says 1/4).
#(define ac:defaultGraceFactor 9/40)

% What proportion of an ordinary grace note's time should be stolen
% from preceding notes (as opposed to stealing from the principal note).
% Composers' intentions for this vary.  Taking all from the preceding
% notes is LilyPond's built-in behaviour for MIDI output.
#(define ac:defaultGraceBackwardness 1)


% Internal variables, don't touch.
% (should probably be part of a context somehow)

% Whether to slur, or not
#(define ac:inSlur #f)
#(define ac:inPhrasingSlur #f)

% Whether the current noteevent is in a trill spanner
#(define ac:inTrill #f)

% assume start in C major.  Key change events override this.
% Could get from context, but don't know how.
#(define ac:current-key (make-music
          'KeyChangeEvent
          'tonic
          (ly:make-pitch -1 0 0)
          'pitch-alist
          (list (cons 0 0)
                (cons 1 0)
                (cons 2 0)
                (cons 3 0)
                (cons 4 0)
                (cons 5 0)
                (cons 6 0))))


#(define ac:currentTempo (ly:make-moment 15/1)) % 4 = 60, measured wholes per minute
#(define ac:lastTempo ac:currentTempo) % for 'a tempo' or 'tempo I'

% The duration of the current note.  Start at a crotchet
% for no good reason.
#(define ac:currentDuration (ly:make-duration 2 0 1/1))

% Amount of musical time (in whole notes) that we need to steal from the
% next events seen.
#(define ac:stealForward 0)

% List of events in the output so far, in reverse order, from which we can
% steal time.
#(define ac:eventsBackward '())

% Log events for the backward chain.
#(define (ac:logEventsBackward music)
  (music-map
   (lambda (m)
    (case (ly:music-property m 'name)
     ((EventChord)
      (set! ac:eventsBackward (cons m ac:eventsBackward))
      m)
     ((BarCheck SkipMusic)
      (let ((wm (make-sequential-music (list m))))
       (set! ac:eventsBackward (cons wm ac:eventsBackward))
       wm))
     (else
      m)))
   music))

% Steal time from the backward chain.  Adds to ac:stealForward (with a
% warning) if it couldn't backward-steal all that was desired.
#(define (ac:stealTimeBackward tosteal)
  (if (<= tosteal 0)
   #t
   (if (null? ac:eventsBackward)
    (begin
     (ly:warning (_ "articulation failed to steal ~a note backward at beginning of music; stealing forward instead") tosteal)
     (set! ac:stealForward (+ ac:stealForward tosteal)))
    (let*
     ((lastev (car ac:eventsBackward))
      (levlen (ly:moment-main (ly:music-length lastev))))
     (if (< tosteal levlen)
      (begin
       (ly:music-compress lastev (ly:make-moment (/ (- levlen tosteal) levlen)))
       #t)
      (begin
       (if (any (lambda (z) (eq? 'NoteEvent (ly:music-property z 'name)))
		(ly:music-property lastev 'elements))
	(ly:warning (_ "stealing the entirety of a note's time")))
       (set! (ly:music-property lastev 'elements) '())
       (set! ac:eventsBackward (cdr ac:eventsBackward))
       (ac:stealTimeBackward (- tosteal levlen))))))))

% Debugging: display a moment plus some text.
% Returns its moment argument so can be used in-line.
#(define (display-moment  text m)
  (display text)
  (display (list (ly:moment-main-numerator m) "/" (ly:moment-main-denominator m)))
  m
)

% Track tempo (and maybe later, other context properties)
% as they change.  Needs to better cope with saving only Tempo I,
% otherwise "a tempo" goes back to the tempo before the last change.
#(define (ac:adjust-props sym music)
  (case sym
   ((tempoWholesPerMinute)
    (set! ac:currentTempo (ly:music-property music 'value))
    (set! ac:lastTempo ac:currentTempo)
  )))

% Raise note one step in the current diatonic scale.
#(define (ac:up note)
  (let* ((pitch (ly:music-property note 'pitch))
	 (notename (ly:pitch-notename pitch))
	 (new-notename (if (eq? notename 6) 0 (+ 1 notename)))
	 (alterations (ly:music-property ac:current-key 'pitch-alist))
	 (new-alteration (cdr (assq new-notename alterations)))
	 (new-octave (if (eq? new-notename 0) (+ 1 (ly:pitch-octave pitch))
		      (ly:pitch-octave pitch)))
       )
   (set! (ly:music-property note 'pitch)(ly:make-pitch new-octave new-notename new-alteration))))


% Lower note one step in the current diatonic scale.
#(define (ac:down note)
  (begin  (let* ((pitch (ly:music-property note 'pitch))
	 (notename (ly:pitch-notename pitch))
	 (new-notename (if (eq? notename 0) 6 (- notename 1)))
	 (alterations (ly:music-property ac:current-key 'pitch-alist))
	 (new-alteration (cdr (assq new-notename alterations)))
	 (new-octave (if (eq? new-notename 6) (- (ly:pitch-octave pitch) 1)
		      (ly:pitch-octave pitch)))
       )
   (set! (ly:music-property note 'pitch)(ly:make-pitch new-octave new-notename new-alteration))))
)

% Shorten a note, and save the note's original duration in ac:currentDuration
#(define (ac:articulate-one-note m fraction)
  "Replace m with m*fraction"
  (if  (eq? 'NoteEvent (ly:music-property m 'name))
   (let*
    ((dur (ly:music-property m 'duration))
     (l (ly:duration-log dur))
     (d (ly:duration-dot-count dur))
     (factor (ly:duration-factor dur))
     (num (car fraction))
     (denom (cdr fraction)))
    (begin
     (set! ac:currentDuration dur)
     (set! (ly:music-property m 'duration)
      (ly:make-duration l d
       (* num (car factor))
       (* denom (cdr factor))))))
   m))

% helper routine to set duration.
#(define (ac:setduration music duration)
  "Set a note's duration."
  (let ((eventtype (ly:music-property music 'name)))
   (if
    (or
     (eq? eventtype 'NoteEvent)
     (eq? eventtype 'RestEvent)
     (eq? eventtype 'SkipEvent))
    (set! (ly:music-property music 'duration) duration))))

% Add an articulation event to a note.
% Used in afterGrace to mark all notes as tenuto, so they're not shortened
#(define (ac:add-articulation type music)
    (music-map (lambda (m)
		(if (eq? 'EventChord (ly:music-property m 'name))
		 (set! (ly:music-property m 'elements)
		  (append (ly:music-property m 'elements)
		   (list (make-music 'ArticulationEvent 'articulation-type type)))))
		m)
     music))

% Convert a long note to an equivalent set of short notes, tied together.
% This is needed to get smooth dynamics changes.
% Need to deal properly with stuff other than the notes (dynamics, markup etc)
% Still experimental, so disabled for now.
#(define (ac:to128 music) music)

#(define (ac:to128_disabled music)
  (if (or (eq? 'SkipEvent (ly:music-property music 'name))
	(eq? 'NoteEvent (ly:music-property music 'name)))
   (let* ((dur (ly:music-property music 'duration))
	  (log2 (ly:duration-log dur))
	 (shiftcount (- 6 log2))
	 (lastm (ly:music-deep-copy (shift-duration-log music shiftcount 0))))
   (set! (ly:music-property music 'elements)
    (cons (make-music 'TieEvent) (ly:music-property music 'elements)))
   (make-sequential-music (list
			   (make-repeat "unfold" (1- (expt 2 shiftcount))
			    (make-sequential-music (list music)) '())
			   lastm)))
 music))


% absolute time in minutes of a length of music, as a rational number (moment)
#(define (ac:abstime music)
  (ly:moment-div (ly:music-length music) ac:currentTempo))

% convert absolute time (in minutes) to a moment in the current tempo
#(define (ac:abs->mom m)
  (ly:moment-mul m ac:currentTempo))


% a moment that is ac:maxTwiddletime seconds at the current tempo.
#(define (ac:targetTwiddleTime)
  (ac:abs->mom ac:maxTwiddleTime))


% Nearest twiddletime (in minutes) achievable with power-of-2 divisions of
% the original music.  (twiddletime is the time for one pair of notes
% in a trill)
% If the music has a precomputed twiddletime (e.g., from \afterGrace) use that.
#(define (ac:twiddletime music)
  (let* ((tr (filter (lambda (x)
		     (and (eq? 'ArticulationEvent (ly:music-property x 'name))
		      (string= "trill" (ly:music-property x 'articulation-type))))
	      (ly:music-property music 'elements)))
	 (pre-t (if (pair? tr) (ly:music-property (car tr) 'twiddle)
		 '()))
	 (t (ac:targetTwiddleTime)))
   (if (ly:moment? pre-t)
    pre-t
    (let loop ((len (ly:music-length music)))
     (if (ly:moment<? t len)
      (loop (ly:moment-mul len (ly:make-moment 1/2)))
      len)))))



% Note: I'm assuming early music practice of starting on the auxiliary note.
% Needs to add gruppetto if it's a long trill (TODO)
#(define (ac:trill music)
  " Replace music with time-compressed repeats of the music,
    maybe accelerating if the length is longer than a crotchet "
  (let* ((hemisemidur (ly:make-duration 5 0 1/1))
	 (orig-len  (ly:music-length music))
	 (t (ac:twiddletime music))
	 (uppernote '())
	 (note_moment (ly:moment-mul t (ly:make-moment 1/2)))
	 (c1 (ly:moment-div orig-len note_moment))
	 (c2 (inexact->exact
	      (round (/ (ly:moment-main-numerator c1)
		      (* 2 (ly:moment-main-denominator c1))))))
	 (count (if (< c2 2) 2 c2)))

   (set! (ly:music-property music 'elements)
    (filter (lambda (y) (eq? 'NoteEvent (ly:music-property y 'name)))
     (ly:music-property music 'elements)))
   (map (lambda (y) (ac:setduration y hemisemidur))
    (ly:music-property music 'elements))
   (set! uppernote (ly:music-deep-copy music))
   (map (lambda (y) (ac:up y))
    (filter
     (lambda (z) (eq? 'NoteEvent (ly:music-property z 'name)))
     (ly:music-property uppernote 'elements)))

   (let* ((trillMusicElements
	  (let loop ((so_far (list uppernote music))
		     (c count))
	   (if (> c 1)
	    (loop (append (list (ly:music-deep-copy uppernote) (ly:music-deep-copy music)) so_far) (1- c))
	    so_far)))
	  (trillMusic (make-sequential-music trillMusicElements))
	  (newlen (ly:music-length trillMusic))
	  (factor (ly:moment-div  orig-len newlen)))
    (ly:music-compress trillMusic factor)
; accelerating the music seems to put lily into an infinite loop in
; its layout and midi engines.
;    (let* ((realfactor (exp (* (/ 1.0 count) (log 0.75))))
;	   (factor (ly:make-moment (inexact->exact (round (* 1024 realfactor)))
;		    1024)))
;     (ac:accel trillMusic factor))
 )))

%
% Generate a tempoChangeEvent and its associated property setting.
%
#(define (ac:tempoChange tempo)
  (make-sequential-music
   (list (make-music 'TempoChangeEvent
	  'metronome-count
	  tempo
	  'tempo-unit
	  (ly:make-duration 0 0 1/1))
    (context-spec-music
    (make-property-set 'tempoWholesPerMinute  tempo) 'Score))))

%
% Totally unfold repeats, so that the non-obvious sequencing doesn't
% confuse us.  This is necessary for time stealing to work, because
% that relies on the sequence in which we see events matching their
% audible sequence.  Also unfold multi-measure rests to equivalent
% skips, with preceding and following bar checks, so that time stealing
% can change the length of the pause without falling foul of the
% implicit bar checks.
%
#(define (ac:unfoldMusic music)
  (music-map
   (lambda (m)
    (case (ly:music-property m 'name)
     ((UnfoldedRepeatedMusic)
      (let
       ((body (ly:music-property m 'element))
	(altl (ly:music-property m 'elements))
	(rc (ly:music-property m 'repeat-count)))
       (if (null? altl)
	(make-sequential-music
	 (list-tabulate rc (lambda (i) (ly:music-deep-copy body))))
	(let ((ealtl (if (> (length altl) rc) (take altl rc) altl)))
	 (make-sequential-music
	  (apply append!
	   (append!
	    (list-tabulate
	     (- rc (length ealtl))
	     (lambda (i) (list (ly:music-deep-copy body) (ly:music-deep-copy (car ealtl)))))
	    (map (lambda (alt) (list (ly:music-deep-copy body) alt)) ealtl))))))))
     ((EventChord)
      (let-values
       (((trem evl)
	 (partition (lambda (v) (eq? (ly:music-property v 'name) 'TremoloEvent))
	  (ly:music-property m 'elements))))
       (if (null? trem)
	m
	(let*
	 ((tremtype (ly:music-property (car trem) 'tremolo-type))
	  (tremtype-log (1- (integer-length tremtype)))
	  (durev (find (lambda (v) (not (null? (ly:music-property v 'duration)))) evl))
	  (totaldur (if durev (ly:music-property durev 'duration) (ly:make-duration tremtype-log 0 1)))
	  (tgt-nrep (/ (duration-visual-length totaldur) (duration-log-factor tremtype-log)))
	  (eff-nrep (max (truncate tgt-nrep) 1))
	  (tremdur (ly:make-duration tremtype-log 0
		    (* (/ tgt-nrep eff-nrep) (ly:duration-scale totaldur)))))
	 (or (and (= eff-nrep tgt-nrep) (= (ash 1 tremtype-log) tremtype))
	  (ly:warning (_ "non-integer tremolo ~a:~a")
	   (duration->lily-string (duration-visual totaldur) #:force-duration #t #:time-scale 1)
	   tremtype))
	 (for-each
	  (lambda (v)
	   (or (null? (ly:music-property v 'duration))
	    (set! (ly:music-property v 'duration) tremdur)))
	  evl)
	 (set! (ly:music-property m 'elements) evl)
	 (make-sequential-music
	  (list-tabulate eff-nrep (lambda (i) (ly:music-deep-copy m))))))))
     ((MultiMeasureRestMusic)
      (make-sequential-music
       (list
	(make-music 'BarCheck)
	(make-music 'SkipMusic 'duration (ly:music-property m 'duration))
	(make-music 'BarCheck))))
     (else
      m)))
   (unfold-repeats music)))

% If there's an articulation, use it.
% If in a slur, use (1 . 1) instead.
% Treat phrasing slurs as slurs, but allow explicit articulation.
% (Maybe should treat staccato under a phrasing slur as mezzo-staccato?)
%
% Expect an EventChord.
%
% trills, turns, ornaments etc.  are also treated as Articulations.
% Split into two functions:
%  ac:getactions traverses the elements in the EventChord
%		and calculates the parameters.
%  ac:articulate-chord applies the actions to each NoteEvent in
%		the EventChord.
#(define (ac:getactions music)
  (let  loop ((factor ac:normalFactor)
	      (newelements '())
	      (es (ly:music-property music 'elements))
	      (actions '()))
   (if (null? es)
    (begin
     (set! (ly:music-property music 'elements) (reverse newelements))
     (if
      (not (any (lambda (m) (music-is-of-type? m 'rhythmic-event))
		newelements))
      actions
      (append
       (let ((st ac:stealForward))
	(if (= st 0)
	 '()
	 (begin
	  (set! ac:stealForward 0)
	  (list 'steal st))))
       actions
       (cond
	(ac:inTrill '(trill))
	((and (eq? factor ac:normalFactor) (or ac:inSlur ac:inPhrasingSlur))
	 (list 'articulation  '(1 . 1)))
	(else (list 'articulation  factor))))))
    ; else part
    (let ((e (car es))
	  (tail (cdr es)))
     (case (ly:music-property e 'name)

      ((BeamEvent) ; throw away beam events, or they'll be duplicated by turn or trill
       (loop factor newelements tail actions))

      ((LineBreakEvent FingeringEvent MarkEvent BreathingEvent TieEvent SkipEvent RestEvent) ; pass through some events.
       (loop (cons 1 1) (cons e newelements) tail actions))

      ((ArticulationEvent)
       (let ((articname (ly:music-property e 'articulation-type)))
	; TODO: add more here
	(cond
	 ((string= articname "staccato")
	  (loop ac:staccatoFactor newelements tail actions))
	 ((string= articname "staccatissimo")
	  (loop ac:staccatissimoFactor newelements tail actions))
	 ((string= articname "tenuto")
	  (loop ac:tenutoFactor newelements tail actions))
	 ((string= articname "mordent")
	  (loop (cons 1 1) newelements tail (cons 'mordent actions)))
	 ((string= articname "prall")
	  (loop (cons 1 1) newelements tail (cons 'prall actions)))
	 ((string= articname "trill")
	  (loop (cons 1 1) newelements tail (cons 'trill actions)))
	 ((string= articname "turn")
	  (loop (cons 1 1) newelements tail (cons 'turn actions)))
	 (else (loop factor (cons e newelements) tail actions)))))

      ((TextScriptEvent)
       (let ((t (ly:music-property e 'text)))
	(if (not (string? t))
	 (loop factor (cons e newelements) tail actions)
	 (begin
	  (cond
	   ((or
	     (string= t "rall")
	     (string= t "Rall")
	     (string= t "rit.")
	     (string= t "rall."))
	    (loop factor (cons e newelements) tail (cons 'rall actions)))
	   ((or
	     (string= t "accelerando")
	     (string= t "accel")
	     (string= t "accel."))
	    (loop factor (cons e newelements) tail (cons 'accel actions)))
	   ((or
	     (string= t "poco accel."))
	    (loop factor (cons e newelements) tail (cons 'pocoAccel actions)))
	   ((or
	     (string= t "poco rall.")
	     (string= t "poco rit."))
	    (loop factor (cons e newelements) tail (cons 'pocoRall actions)))
	   ((or (string= t "a tempo")
	     (string= t "tempo I"))
	  (loop factor (cons e newelements) tail (cons 'aTempo actions)))
	   (else (loop factor (cons e newelements) tail actions)))))))

      ((SlurEvent)
       (let ((direction (ly:music-property e 'span-direction)))
	(set! ac:inSlur (eq? direction -1))
	(loop factor newelements tail actions)))

      ((TrillSpanEvent)
       (let ((direction (ly:music-property e 'span-direction)))
	(set! ac:inTrill (eq? direction -1))
	(if ac:inTrill
	 (loop factor newelements tail (cons 'trill actions))
	 (loop factor (cons e newelements) tail actions))))

      ((PhrasingSlurEvent)
       (let ((direction (ly:music-property e 'span-direction)))
	(set! ac:inPhrasingSlur (eq? direction -1))
	(loop factor newelements tail actions)))

      (else (loop factor (cons e newelements) tail actions)))))))



#(define (ac:articulate-chord music)
  (cond
   ((eq? 'EventChord (ly:music-property music 'name))
    (ac:logEventsBackward
     (let loop ((actions (ac:getactions music)))
      (if (null? actions)
	(if (ly:moment<? (ly:make-moment 1/4) (ly:music-length music))
	 (ac:to128  music)
	 music)

      (case (car actions)

       ((articulation)
	(map
	 (lambda (x) (ac:articulate-one-note x (cadr actions)))
	 (ly:music-property music 'elements))
	(let*
	 ((num (caadr actions))
	  (denom (cdadr actions))
	  (mult (ly:duration-factor ac:currentDuration))
	  (newnum (* (- denom num) (car mult)))
	  (newdenom (* (cdr mult) denom))
	  (len (ly:duration-log ac:currentDuration))
	  (dots (ly:duration-dot-count ac:currentDuration)))

	 (if (not (eq? num denom))
	  (make-sequential-music
	   (list (ac:to128 music)
	   (make-music 'EventChord 'elements
	    (list
	     (make-music 'RestEvent 'duration (ly:make-duration len dots newnum newdenom))))))
	  music)))

       ((accel)
	(set! ac:lastTempo ac:currentTempo)
	(set! ac:currentTempo (ly:moment-div ac:currentTempo ac:rallFactor))
	(let ((pset (ac:tempoChange ac:currentTempo)))
	 (if (null? (cdr actions))
	  (make-sequential-music (list pset music))
	  (make-sequential-music
	   (list pset (loop (cdr actions)))))))

       ((pocoAccel)
	(set! ac:lastTempo ac:currentTempo)
	(set! ac:currentTempo (ly:moment-div ac:currentTempo ac:pocoRallFactor))
	(let ((pset (ac:tempoChange ac:currentTempo)))
	 (if (null? (cdr actions))
	  (make-sequential-music (list pset music))
	  (make-sequential-music
	   (list pset (loop (cdr actions)))))))

       ((rall)
	(set! ac:lastTempo ac:currentTempo)
	(set! ac:currentTempo (ly:moment-mul ac:currentTempo ac:rallFactor))
	(let ((pset (ac:tempoChange ac:currentTempo)))
	 (if (null? (cdr actions))
	  (make-sequential-music (list pset music))
	  (make-sequential-music
	   (list pset (loop (cdr actions)))))))

       ((pocoRall)
	(set! ac:lastTempo ac:currentTempo)
	(set! ac:currentTempo (ly:moment-mul ac:currentTempo ac:pocoRallFactor))
	(let ((pset (ac:tempoChange ac:currentTempo)))
	 (if (null? (cdr actions))
	  (make-sequential-music (list pset music))
	  (make-sequential-music
	   (list pset (loop (cdr actions)))))))

       ((aTempo)
	(set! ac:currentTempo ac:lastTempo)

	(let ((pset (ac:tempoChange ac:currentTempo)))
	 (if (null? (cdr actions))
	  (make-sequential-music (list pset music))
	  (make-sequential-music
	   (list pset (loop (cdr actions)))))))

       ((trill)
	 (ac:trill music))

       ((prall)
	; A pralltriller symbol can either mean an inverted mordent
	; or a half-shake -- a short, two twiddle trill.
	; We implement as a half-shake.
	(let*
	 ((totallength (ly:music-length music))
	  (newlen (ly:moment-sub totallength (ly:make-moment 3/32)))
	  (newdur (ly:make-duration
		   0 0
		   (ly:moment-main-numerator newlen)
		   (ly:moment-main-denominator newlen)))
	  (gracedur (ly:make-duration 5 0 1/1))
	  (gracenote (ly:music-deep-copy music))
	  (abovenote (ly:music-deep-copy music))
	  (mainnote (ly:music-deep-copy music))
	  (prall (make-sequential-music (list gracenote abovenote)))
	)
	  (music-map (lambda (n)
	   (if (eq? 'NoteEvent (ly:music-property n 'name))
            (set! (ly:music-property n 'duration) gracedur))
		      n)
	   abovenote)
	  (music-map (lambda (n)
	   (if (eq? 'NoteEvent (ly:music-property n 'name))
            (set! (ly:music-property n 'duration) gracedur))
		      n)
	   gracenote)
	  (music-map (lambda (n)
	   (if (eq? 'NoteEvent (ly:music-property n 'name))
            (set! (ly:music-property n 'duration) newdur))
		      n)
	   mainnote)

	  (map (lambda (y) (ac:up y))
	   (filter
	    (lambda (z) (eq? 'NoteEvent (ly:music-property z 'name)))
	    (ly:music-property abovenote 'elements)))
	  (make-sequential-music (list abovenote gracenote abovenote mainnote))))

       ((mordent)
	(let*
	 ((totaldur (ly:music-property
		(car (ly:music-property music 'elements)) 'duration))
	  (dur (ly:duration-length totaldur))
	  (newlen (ly:moment-sub dur (ly:make-moment 2/32)))
	  (newdur (ly:make-duration
		0 0
		   (ly:moment-main-numerator newlen)
		   (ly:moment-main-denominator newlen)))
	  (gracenote (ly:music-deep-copy music))
	  (belownote (ly:music-deep-copy music))
	  (mainnote (ly:music-deep-copy music))
	  (mordent (make-sequential-music (list gracenote belownote)))
	)
	 (begin
	  (music-map (lambda (n)
	   (if (eq? 'NoteEvent (ly:music-property n 'name))
	    (set! (ly:music-property n 'duration)
	     (ly:make-duration 5 0 1/1)))
		      n)
	   mordent)
	  (music-map (lambda (n)
	   (if (eq? 'NoteEvent (ly:music-property n 'name))
            (set! (ly:music-property n 'duration) newdur))
		      n)
	   mainnote)
	  (map (lambda (y) (ac:down y))
	   (filter
	    (lambda (z) (eq? 'NoteEvent (ly:music-property z 'name)))
	    (ly:music-property belownote 'elements)))
	  (make-sequential-music (list mordent mainnote)))))
       ((turn)
	(let*
	 ((dur (ly:music-property
		(car (ly:music-property music 'elements)) 'duration))
	  (factor (ly:duration-factor dur))
	  (newdur (ly:make-duration (+ (ly:duration-log dur) 2)
		   (ly:duration-dot-count dur) (car factor)(cdr factor))))
	 (begin
	  (map (lambda (y) (ac:setduration y newdur))
	   (ly:music-property music 'elements))
	  (let* ((above (ly:music-deep-copy music))
		 (below (ly:music-deep-copy music))
		 (newmusic (make-sequential-music (list above music below music))))
	   (begin
	    (map (lambda (y) (ac:down y))
	     (filter
	      (lambda (z) (eq? 'NoteEvent (ly:music-property z 'name)))
	      (ly:music-property below 'elements)))
	    (map (lambda (y) (ac:up y))
	     (filter
	      (lambda (z) (eq? 'NoteEvent (ly:music-property z 'name)))
	      (ly:music-property above 'elements)))
	    newmusic)))))
       ((steal)
	(let
	 ((totallen (ly:moment-main (ly:music-length music)))
	  (steallen (cadr actions)))
	 (if (>= steallen totallen)
	  (begin
	   (if (any (lambda (z) (eq? 'NoteEvent (ly:music-property z 'name)))
		    (ly:music-property music 'elements))
	    (ly:warning (_ "stealing the entirety of a note's time")))
	   (set! ac:stealForward (- steallen totallen))
	   (make-sequential-music '()))
	  (begin
	   (ly:music-compress music (ly:make-moment (/ (- totallen steallen) totallen)))
	   (loop (cddr actions))))))
     )))))

   ((eq? 'GraceMusic (ly:music-property music 'name))
    (let
     ((first-ev
       (call-with-current-continuation
	(lambda (yield-fev)
	 (music-map
	  (lambda (m)
	   (if (eq? 'EventChord (ly:music-property m 'name))
	    (yield-fev m)
	    m))
	  music)
	 #f))))
     (if first-ev
      (let ((fev-pos (find-tail (lambda (m) (eq? m first-ev)) ac:eventsBackward)))
       (if fev-pos
	(set! ac:eventsBackward (cdr fev-pos))
	(ly:warning (_ "articulation of grace notes has gone awry"))))))
    (let*
     ((gmus (ly:music-compress (ly:music-property music 'element)
			       (ly:make-moment ac:defaultGraceFactor)))
      (glen (ly:moment-main (ly:music-length gmus))))
     (ac:stealTimeBackward (* glen ac:defaultGraceBackwardness))
     (set! ac:stealForward (+ ac:stealForward (* glen (- 1 ac:defaultGraceBackwardness))))
     gmus))

   ((memq (ly:music-property music 'name) '(BarCheck SkipMusic))
    (let ((totallen (ly:moment-main (ly:music-length music)))
	  (steallen ac:stealForward))
     (cond
      ((= steallen 0)
       (ac:logEventsBackward music))
      ((< steallen totallen)
       (set! ac:stealForward 0)
       (ac:logEventsBackward
	(ly:music-compress music (ly:make-moment (/ (- totallen steallen) totallen)))))
      (else
       (set! ac:stealForward (- steallen totallen))
       (make-sequential-music '())))))

   ((eq? 'KeyChangeEvent (ly:music-property music 'name))
    (set! ac:current-key music)
    music)

   ((eq? 'PropertySet (ly:music-property music 'name))
    (ac:adjust-props (ly:music-property music 'symbol) music)
    music)

   (else music)))



% At last ... here's the music function that applies all the above to a
% score.
articulate = #(define-music-function (parser location music)
	       (ly:music?)
	       "Adjust times of note to add tenuto, staccato and
                normal articulations.
		"
	       (dynamic-wind
		(lambda ()
		 (set! ac:stealForward 0)
		 (set! ac:eventsBackward '()))
		(lambda ()
		 (music-map
		  ac:articulate-chord
		  (ac:unfoldMusic (event-chord-wrap! music parser))))
		(lambda ()
		 (or (= ac:stealForward 0)
		  (begin
		   (ly:warning (_ "articulation failed to steal ~a note at end of music") ac:stealForward)
		   (set! ac:stealForward 0)))
		 (set! ac:eventsBackward '()))))


% Override \afterGrace to be in terms of audio, not spacing.
% Special handling for a gruppetto after a trill.
afterGrace =
#(define-music-function
  (parser location main grace)
  (ly:music? ly:music?)

  (set! main (event-chord-wrap! main parser))
  (set! grace (event-chord-wrap! grace parser))
  (let*
   ((main-length (ly:music-length main))
    (grace-orig-length (ly:music-length grace))
    (gracelen (ac:twiddletime main))
    (grace-factor (ly:moment-div gracelen grace-orig-length))
    (new-main-length (ly:moment-sub main-length gracelen))
    (factor (ly:moment-div new-main-length main-length))
  )
   (map (lambda (y) (set! (ly:music-property y 'twiddle) gracelen))
	 (filter (lambda (z)
		  (and
		   (eq? 'ArticulationEvent (ly:music-property z 'name))
		   (string= "trill" (ly:music-property z 'articulation-type))))
	  (ly:music-property main 'elements)))
   (ac:add-articulation "tenuto" grace)
   (make-sequential-music  (list (ly:music-compress main factor) (ly:music-compress grace grace-factor)))))

% An appoggiatura takes half the duration of the main note,
% or 1/3 if the note is dotted (i.e., half the undotted equivalent time)
% Somewhere around the end of the 19th, start of 20th century the rules
% changed, but my main interest is early music.
appoggiatura =
#(define-music-function (parser location grace main)
  (ly:music? ly:music?)
  (set! grace (event-chord-wrap! grace parser))
  (set! main (event-chord-wrap! main parser))
  (let* ((maindur (ly:music-length main))
	 (grace-orig-len (ly:music-length grace))
	 (main-orig-len (ly:music-length main))
	 (numerator (ly:moment-main-numerator maindur))
	 (factor (if (eq? (remainder numerator 3) 0)
		  (ly:make-moment 1/3) (ly:make-moment 1/2))))
   (ly:music-compress grace
    (ly:moment-mul factor (ly:moment-div main-orig-len grace-orig-len)))
   (ly:music-compress main (ly:moment-sub (ly:make-moment 1/1) factor))

    (set! (ly:music-property grace 'elements)
     (append (ly:music-property grace 'elements)
      (list (make-music 'SlurEvent 'span-direction -1))))
    (set! (ly:music-property main 'elements)
     (append (ly:music-property main 'elements)
      (list (make-music 'SlurEvent 'span-direction 1))))
     (make-sequential-music (list grace main))))

