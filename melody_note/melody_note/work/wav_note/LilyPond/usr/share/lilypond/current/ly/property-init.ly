% property-init.ly

\version "2.17.24"

%% for dashed slurs, phrasing slurs, and ties
#(define (make-simple-dash-definition dash-fraction dash-period)
    (list (list 0 1 dash-fraction dash-period)))

%% common definition for all note head styles reverting
%% (palm mute, harmonics, dead notes, ...)
defaultNoteHeads =
#(define-music-function (parser location) ()
   (_i "Revert to the default note head style.")
   (revert-head-style '(NoteHead TabNoteHead)))

accidentalStyle =
#(define-music-function
   (parser location style) (symbol-list?)
   (_i "Set accidental style to symbol list @var{style} in the form
@samp{piano-cautionary}.  If @var{style} has a form like
@samp{Staff.piano-cautionary}, the settings are applied to that
context.  Otherwise, the context defaults to @samp{Staff}, except for
piano styles, which use @samp{GrandStaff} as a context." )
   (case (length style)
    ((1) (set-accidental-style (car style)))
    ((2) (set-accidental-style (cadr style) (car style)))
    (else
     (ly:parser-error parser (_ "not an accidental style")
      location)
     (make-music 'Music))))

%% arpeggios

% For drawing vertical chord brackets with \arpeggio
% This is a shorthand for the value of the print-function property
% of either Staff.Arpeggio or PianoStaff.Arpeggio, depending whether
% cross-staff brackets are desired.

arpeggio = #(make-music 'ArpeggioEvent)
arpeggioArrowUp = {
  \revert Arpeggio.stencil
  \revert Arpeggio.X-extent
  \override Arpeggio.arpeggio-direction = #UP
}
arpeggioArrowDown = {
  \revert Arpeggio.stencil
  \revert Arpeggio.X-extent
  \override Arpeggio.arpeggio-direction = #DOWN
}
arpeggioNormal = {
  \revert Arpeggio.stencil
  \revert Arpeggio.X-extent
  \revert Arpeggio.arpeggio-direction
  \revert Arpeggio.dash-definition
}
arpeggioBracket = {
  \revert Arpeggio.X-extent
  \override Arpeggio.stencil = #ly:arpeggio::brew-chord-bracket
}
arpeggioParenthesis = {
  \override Arpeggio.stencil = #ly:arpeggio::brew-chord-slur
  \override Arpeggio.X-extent = #ly:grob::stencil-width
  \revert Arpeggio.dash-definition
}
arpeggioParenthesisDashed = {
  \override Arpeggio.stencil = #ly:arpeggio::brew-chord-slur
  \override Arpeggio.X-extent = #ly:grob::stencil-width
  \override Arpeggio.dash-definition = #'((0 1 0.4 0.75))
}


%% auto beaming

autoBeamOn  = \set autoBeaming = ##t
autoBeamOff = \set autoBeaming = ##f


%% balloon length

balloonLengthOn = {
  \override BalloonTextItem.extra-spacing-width = #'(0 . 0)
  \override BalloonTextItem.extra-spacing-height = #'(-inf.0 . +inf.0)
}
balloonLengthOff = {
  \override BalloonTextItem.extra-spacing-width = #'(+inf.0 . -inf.0)
  \override BalloonTextItem.extra-spacing-height = #'(0 . 0)
}


%% bar lines

defineBarLine =
#(define-void-function
   (parser location bar glyph-list) (string? list?)
   (_i "Define bar line settings for bar line @var{bar}.
     The list @var{glyph-list} must have three entries which define
     the appearance at the end of line, at the beginning of the next line,
     and the span bar, respectively." )
  (if (not (= (length glyph-list) 3))
      (ly:error (_ "Argument list for bar '~a' must have three components.") bar)
      (define-bar-line bar
                       (car glyph-list)
                       (cadr glyph-list)
                       (caddr glyph-list))))


%% bass figures

bassFigureExtendersOn = {
  \set useBassFigureExtenders = ##t
  \set Staff.useBassFigureExtenders = ##t
}
bassFigureExtendersOff = {
  \set useBassFigureExtenders = ##f
  \set Staff.useBassFigureExtenders = ##f
}
bassFigureStaffAlignmentDown =
  \override Staff.BassFigureAlignmentPositioning.direction = #DOWN
bassFigureStaffAlignmentUp =
  \override Staff.BassFigureAlignmentPositioning.direction = #UP
bassFigureStaffAlignmentNeutral =
  \revert Staff.BassFigureAlignmentPositioning.direction


%% cadenzas

cadenzaOn  = \set Timing.timing = ##f

cadenzaOff = \set Timing.timing = ##t

%% chord names

frenchChords = {
  \set chordRootNamer = #(chord-name->italian-markup #t)
  \set chordPrefixSpacer = #0.4
}
germanChords = {
  \set chordRootNamer = #(chord-name->german-markup #t)
  \set chordNoteNamer = #note-name->german-markup
}
semiGermanChords = {
  \set chordRootNamer = #(chord-name->german-markup #f)
  \set chordNoteNamer = #note-name->german-markup
}
italianChords = {
  \set chordRootNamer = #(chord-name->italian-markup #f)
  \set chordPrefixSpacer = #0.4
}
powerChords = {
  \set chordNameExceptions = #powerChordExceptions
}


%% compressFullBarRests

compressFullBarRests = \set Score.skipBars = ##t
expandFullBarRests   = \set Score.skipBars = ##f


%% dots

dotsUp      = \override Dots.direction = #UP
dotsDown    = \override Dots.direction = #DOWN
dotsNeutral = \revert Dots.direction


%% dynamics

dynamicUp = {
  \override DynamicText.direction = #UP
  \override DynamicLineSpanner.direction = #UP
}
dynamicDown = {
  \override DynamicText.direction = #DOWN
  \override DynamicLineSpanner.direction = #DOWN
}
dynamicNeutral = {
  \revert DynamicText.direction
  \revert DynamicLineSpanner.direction
}


%% easy heads

easyHeadsOn = {
  \override NoteHead.stencil = #note-head::brew-ez-stencil
  \override NoteHead.font-size = #-8
  \override NoteHead.font-family = #'sans
  \override NoteHead.font-series = #'bold
}
easyHeadsOff = {
  \revert NoteHead.stencil
  \revert NoteHead.font-size
  \revert NoteHead.font-family
  \revert NoteHead.font-series
}


%% endincipit

%% End the incipit and print a ``normal line start''.
endincipit = \context Staff {
  \partial 16 s16  % Hack to handle e.g. \bar ".|" \endincipit
  \once \override Staff.Clef.full-size-change = ##t
  \once \override Staff.Clef.non-default = ##t
  \bar ""
}


%% fermata markup

fermataMarkup =
#(make-music 'MultiMeasureTextEvent
	     ;; Set the 'text based on the 'direction
	     'text (make-fermata-markup)
             'tweaks '((outside-staff-priority . 40)
		       (outside-staff-padding . 0)))

%% font sizes

teeny      = \set fontSize = #-3
tiny       = \set fontSize = #-2
small      = \set fontSize = #-1
normalsize = \set fontSize = #0
large      = \set fontSize = #1
huge       = \set fontSize = #2


%% glissando

glissando = #(make-music 'GlissandoEvent)


%% harmonics

harmonicsOn =
#(define-music-function (parser location) ()
   (_i "Set the default note head style to a diamond-shaped style.")
   (override-head-style '(NoteHead TabNoteHead) 'harmonic))
harmonicsOff = \defaultNoteHeads
harmonicNote =
#(define-music-function (parser location note) (ly:music?)
   (_i "Print @var{note} with a diamond-shaped note head.")
   (style-note-heads 'NoteHead 'harmonic note))


%% hideNotes

hideNotes = {
  % hide notes, accidentals, etc.
  \override Dots.transparent = ##t
  \override NoteHead.transparent = ##t
  \override NoteHead.no-ledgers = ##t
  % assume that any Beam inherits transparency from its parent Stem
  \override Stem.transparent = ##t
  \override Accidental.transparent = ##t
  \override Rest.transparent = ##t
  \override TabNoteHead.transparent = ##t
}
unHideNotes = {
  \revert Accidental.transparent
  \revert Stem.transparent
  \revert NoteHead.transparent
  \revert NoteHead.no-ledgers
  \revert Dots.transparent
  \revert Rest.transparent
  \revert TabNoteHead.transparent
}


%% improvisation

improvisationOn = {
  \set squashedPosition = #0
  \override NoteHead.style = #'slash
  \override Accidental.stencil = ##f
  \override AccidentalCautionary.stencil = ##f
}
improvisationOff = {
  \unset squashedPosition
  \revert NoteHead.style
  \revert Accidental.stencil
  \revert AccidentalCautionary.stencil
}

%% kievan
kievanOn = {
 \override NoteHead.style = #'kievan
 \override Stem.X-offset = #stem::kievan-offset-callback
 \override Stem.stencil = ##f
 \override Flag.stencil = ##f
 \override Rest.style = #'mensural
 \override Accidental.glyph-name-alist = #alteration-kievan-glyph-name-alist
 \override Dots.style = #'kievan
 \override Slur.stencil = ##f
 \override Stem.length = #0.0
 \override Beam.positions = #beam::get-kievan-positions
 \override Beam.quantized-positions = #beam::get-kievan-quantized-positions
 \override NoteHead.duration-log = #note-head::calc-kievan-duration-log
}
kievanOff = {
 \revert NoteHead.style
 \revert Stem.X-offset
 \revert Stem.stencil
 \revert Rest.style
 \revert Accidental.glyph-name-alist
 \revert Dots.style
 \revert Slur.stencil
 \revert Flag.stencil
 \revert Stem.length
 \revert Beam.positions
 \revert Beam.quantized-positions
 \revert NoteHead.duration-log
}

%% merging

mergeDifferentlyDottedOn =
  \override Staff.NoteCollision.merge-differently-dotted = ##t
mergeDifferentlyDottedOff =
  \revert Staff.NoteCollision.merge-differently-dotted
mergeDifferentlyHeadedOn =
  \override Staff.NoteCollision.merge-differently-headed = ##t
mergeDifferentlyHeadedOff =
  \revert Staff.NoteCollision.merge-differently-headed


%% numeric time signature

numericTimeSignature = \override Staff.TimeSignature.style = #'numbered
defaultTimeSignature = \revert Staff.TimeSignature.style


%% palm mutes

palmMuteOn =
#(define-music-function (parser location) ()
   (_i "Set the default note head style to a triangle-shaped style.")
   (override-head-style 'NoteHead 'do))
palmMuteOff = \defaultNoteHeads
palmMute =
#(define-music-function (parser location note) (ly:music?)
   (_i "Print @var{note} with a triangle-shaped note head.")
   (style-note-heads 'NoteHead 'do note))


%% phrasing slurs

% directions
phrasingSlurUp      = \override PhrasingSlur.direction = #UP
phrasingSlurDown    = \override PhrasingSlur.direction = #DOWN
phrasingSlurNeutral = \revert PhrasingSlur.direction

% dash-patterns (make-simple-dash-definition defined at top of file)
phrasingSlurDashPattern =
#(define-music-function (parser location dash-fraction dash-period)
   (number? number?)
   (_i "Set up a custom style of dash pattern for @var{dash-fraction} ratio of
line to space repeated at @var{dash-period} interval for phrasing slurs.")
  #{
     \override PhrasingSlur.dash-definition =
       $(make-simple-dash-definition dash-fraction dash-period)
  #})
phrasingSlurDashed =
  \override PhrasingSlur.dash-definition = #'((0 1 0.4 0.75))
phrasingSlurDotted =
  \override PhrasingSlur.dash-definition = #'((0 1 0.1 0.75))
phrasingSlurHalfDashed =
  \override PhrasingSlur.dash-definition = #'((0 0.5 0.4 0.75)
						(0.5 1 1 1))
phrasingSlurHalfSolid =
  \override PhrasingSlur.dash-definition = #'((0 0.5 1 1)
						(0.5 1 0.4 0.75))
phrasingSlurSolid =
  \revert PhrasingSlur.dash-definition


%% point and click

pointAndClickOn  =
#(define-void-function (parser location) ()
   (_i "Enable generation of code in final-format (e.g. pdf) files to reference the
originating lilypond source statement;
this is helpful when developing a score but generates bigger final-format files.")
   (ly:set-option 'point-and-click #t))

pointAndClickOff =
#(define-void-function (parser location) ()
   (_i "Suppress generating extra code in final-format (e.g. pdf) files to point
back to the lilypond source statement.")
   (ly:set-option 'point-and-click #f))

pointAndClickTypes =
#(define-void-function (parser location types) (symbol-list-or-symbol?)
  (_i "Set a type or list of types (such as @code{#'note-event}) for which point-and-click info is generated.")
  (ly:set-option 'point-and-click types))

%% predefined fretboards

predefinedFretboardsOff =
  \set predefinedDiagramTable = ##f
predefinedFretboardsOn =
  \set predefinedDiagramTable = #default-fret-table


%% shape note heads

aikenHeads      = \set shapeNoteStyles = ##(do re miMirror fa sol la ti)
aikenHeadsMinor = \set shapeNoteStyles = ##(la ti do re miMirror fa sol)
funkHeads =
  \set shapeNoteStyles = ##(doFunk reFunk miFunk faFunk solFunk laFunk tiFunk)
funkHeadsMinor =
  \set shapeNoteStyles = ##(laFunk tiFunk doFunk reFunk miFunk faFunk solFunk)
sacredHarpHeads = \set shapeNoteStyles = ##(fa sol la fa sol la mi)
sacredHarpHeadsMinor = \set shapeNoteStyles = ##(la mi fa sol la fa sol)
southernHarmonyHeads =
  \set shapeNoteStyles = ##(faThin sol laThin faThin sol laThin miThin)
southernHarmonyHeadsMinor =
  \set shapeNoteStyles = ##(laThin miThin faThin sol laThin faThin sol)
walkerHeads =
  \set shapeNoteStyles = ##(doWalker reWalker miWalker faWalker solFunk laWalker tiWalker)
walkerHeadsMinor =
  \set shapeNoteStyles = ##(laWalker tiWalker doWalker reWalker miWalker faWalker solFunk)


%% shifts

shiftOn   = \override NoteColumn.horizontal-shift = #1
shiftOnn  = \override NoteColumn.horizontal-shift = #2
shiftOnnn = \override NoteColumn.horizontal-shift = #3
shiftOff  = \revert NoteColumn.horizontal-shift


%% slurs

% directions
slurUp         = \override Slur.direction = #UP
slurDown       = \override Slur.direction = #DOWN
slurNeutral    = \revert Slur.direction

% dash-patterns (make-simple-dash-definition defined at top of file)
slurDashPattern =
#(define-music-function (parser location dash-fraction dash-period)
  (number? number?)
  (_i "Set up a custom style of dash pattern for @var{dash-fraction}
ratio of line to space repeated at @var{dash-period} interval for slurs.")
  #{
     \override Slur.dash-definition =
       $(make-simple-dash-definition dash-fraction dash-period)
  #})
slurDashed     = \override Slur.dash-definition = #'((0 1 0.4 0.75))
slurDotted     = \override Slur.dash-definition = #'((0 1 0.1 0.75))
slurHalfDashed = \override Slur.dash-definition = #'((0 0.5 0.4 0.75)
						       (0.5 1 1 1))
slurHalfSolid  = \override Slur.dash-definition = #'((0 0.5 1 1)
						       (0.5 1 0.4 0.75))
slurSolid      = \revert Slur.dash-definition


%% staff switches

showStaffSwitch = \set followVoice = ##t
hideStaffSwitch = \set followVoice = ##f


%% stems

stemUp      = \override Stem.direction = #UP
stemDown    = \override Stem.direction = #DOWN
stemNeutral = \revert Stem.direction


%% tablature

% switch to full notation
tabFullNotation = {
  % time signature
  \revert TabStaff.TimeSignature.stencil
  % stems (the half note gets a double stem)
  \revert TabStaff.Stem.length
  \revert TabStaff.Stem.no-stem-extend
  \revert TabStaff.Flag.style
  \revert TabStaff.Stem.details
  \revert TabStaff.Stem.stencil
  \revert TabStaff.Flag.stencil
  \override TabStaff.Stem.stencil = #tabvoice::draw-double-stem-for-half-notes
  \override TabStaff.Stem.X-extent = #tabvoice::make-double-stem-width-for-half-notes
  \set TabStaff.autoBeaming = ##t
  \revert TabStaff.NoteColumn.ignore-collision
  % beams, dots
  \revert TabStaff.Beam.stencil
  \revert TabStaff.StemTremolo.stencil
  \revert TabStaff.Dots.stencil
  \revert TabStaff.Tie.stencil
  \revert TabStaff.Tie.after-line-breaking
  \revert TabStaff.RepeatTie.stencil
  \revert TabStaff.RepeatTie.after-line-breaking
  \revert TabStaff.LaissezVibrerTie.stencil
  \revert TabStaff.Slur.stencil
  \revert TabStaff.PhrasingSlur.stencil
  % tuplet stuff
  \revert TabStaff.TupletBracket.stencil
  \revert TabStaff.TupletNumber.stencil
  % dynamic signs
  \revert TabStaff.DynamicText.stencil
  \revert TabStaff.DynamicTextSpanner.stencil
  \revert TabStaff.DynamicTextSpanner.stencil
  \revert TabStaff.Hairpin.stencil
  % rests
  \revert TabStaff.Rest.stencil
  \revert TabStaff.MultiMeasureRest.stencil
  \revert TabStaff.MultiMeasureRestNumber.stencil
  \revert TabStaff.MultiMeasureRestText.stencil
  % markups etc.
  \revert TabStaff.Glissando.stencil
  \revert TabStaff.Script.stencil
  \revert TabStaff.TextScript.stencil
  \revert TabStaff.TextSpanner.stencil
  \revert TabStaff.Arpeggio.stencil
  \revert TabStaff.NoteColumn.ignore-collision
}

%tie/repeat tie behaviour
hideSplitTiedTabNotes = {
  \override TabVoice.TabNoteHead.details.tied-properties.break-visibility = #all-invisible
  \override TabVoice.TabNoteHead.details.tied-properties.parenthesize = ##f
  \override TabVoice.TabNoteHead.details.repeat-tied-properties.note-head-visible = ##f
  \override TabVoice.TabNoteHead.details.repeat-tied-properties.parenthesize = ##f
}

showSplitTiedTabNotes = {
  \override TabVoice.TabNoteHead.details.tied-properties.break-visibility = #begin-of-line-visible
  \override TabVoice.TabNoteHead.details.tied-properties.parenthesize = ##t
  \override TabVoice.TabNoteHead.details.repeat-tied-properties.note-head-visible = ##t
  \override TabVoice.TabNoteHead.details.repeat-tied-properties.parenthesize = ##t
}

%% text length

textLengthOn = {
  % 0.4 staff-space between adjacent texts
  \override TextScript.extra-spacing-width = #'(-0.0 . 0.4)
  \override TextScript.extra-spacing-height = #'(-inf.0 . +inf.0)
}

textLengthOff = {
  \override TextScript.extra-spacing-width = #'(+inf.0 . -inf.0)
  \override TextScript.extra-spacing-height = #'(0 . 0)
}

markLengthOn = {
  \override Score.MetronomeMark.extra-spacing-width = #'(0 . 1.0)
  \override Score.RehearsalMark.extra-spacing-width = #'(-0.5 . 0.5)
  % Raise as much as four staff-spaces before pushing notecolumns right
  \override Score.MetronomeMark.extra-spacing-height = #'(4 . 4)
  \override Score.RehearsalMark.extra-spacing-height = #'(4 . 4)
}

markLengthOff = {
  \override Score.MetronomeMark.extra-spacing-width = #'(+inf.0 . -inf.0)
  \override Score.RehearsalMark.extra-spacing-width = #'(+inf.0 . -inf.0)
  \revert Score.MetronomeMark.extra-spacing-height
  \revert Score.RehearsalMark.extra-spacing-height
}

%% text spanners

textSpannerUp      = \override TextSpanner.direction = #UP
textSpannerDown    = \override TextSpanner.direction = #DOWN
textSpannerNeutral = \revert TextSpanner.direction


%% ties

% directions
tieUp      = \override Tie.direction = #UP
tieDown    = \override Tie.direction = #DOWN
tieNeutral = \revert Tie.direction

% dash-patterns (make-simple-dash-definition defined at top of file)
tieDashPattern =
#(define-music-function (parser location dash-fraction dash-period)
  (number? number?)
  (_i "Set up a custom style of dash pattern for @var{dash-fraction}
ratio of line to space repeated at @var{dash-period} interval for ties.")
  #{
     \override Tie.dash-definition =
       $(make-simple-dash-definition dash-fraction dash-period)
  #})
tieDashed     = \override Tie.dash-definition = #'((0 1 0.4 0.75))
tieDotted     = \override Tie.dash-definition = #'((0 1 0.1 0.75))
tieHalfDashed = \override Tie.dash-definition = #'((0 0.5 0.4 0.75)
						     (0.5 1 1 1))
tieHalfSolid  = \override Tie.dash-definition = #'((0 0.5 1 1)
						     (0.5 1 0.4 0.75))
tieSolid      = \revert Tie.dash-definition


%% tuplets

tupletUp      = \override TupletBracket.direction = #UP
tupletDown    = \override TupletBracket.direction = #DOWN
tupletNeutral = \revert TupletBracket.direction


%% voice properties

% dynamic ly:dir?  text script, articulation script ly:dir?
voiceOne   = #(context-spec-music (make-voice-props-set 0)  'Voice)
voiceTwo   = #(context-spec-music (make-voice-props-set 1)  'Voice)
voiceThree = #(context-spec-music (make-voice-props-set 2)  'Voice)
voiceFour  = #(context-spec-music (make-voice-props-set 3)  'Voice)
oneVoice   = #(context-spec-music (make-voice-props-revert) 'Voice)


%% voice styles

voiceOneStyle = {
  \override NoteHead.style = #'diamond
  \override NoteHead.color = #red
  \override Stem.color = #red
  \override Beam.color = #red
}
voiceTwoStyle = {
  \override NoteHead.style = #'triangle
  \override NoteHead.color = #blue
  \override Stem.color = #blue
  \override Beam.color = #blue
}
voiceThreeStyle = {
  \override NoteHead.style = #'xcircle
  \override NoteHead.color = #green
  \override Stem.color = #green
  \override Beam.color = #green
}
voiceFourStyle = {
  \override NoteHead.style = #'cross
  \override NoteHead.color = #magenta
  \override Stem.color = #magenta
  \override Beam.color = #magenta
}
voiceNeutralStyle = {
  \revert NoteHead.style
  \revert NoteHead.color
  \revert Stem.color
  \revert Beam.color
}


%% volta brackets

allowVoltaHook =
#(define-void-function (parser location bar) (string?)
                       (allow-volta-hook bar))

%% x notes

xNotesOn =
#(define-music-function (parser location) ()
   (_i "Set the default note head style to a cross-shaped style.")
   (override-head-style '(TabNoteHead NoteHead) 'cross))
xNotesOff = \defaultNoteHeads
xNote =
#(define-music-function (parser location note) (ly:music?)
   (_i "Print @var{note} with a cross-shaped note head.")
   (style-note-heads '(TabNoteHead NoteHead) 'cross note))


%% dead notes (these need to come after "x notes")

% Define aliases of cross-head notes for specific purposes
deadNotesOn  = \xNotesOn
deadNotesOff = \xNotesOff
deadNote     = #xNote
