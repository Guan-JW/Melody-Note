\version "2.16.0"

chordmodifiers = #default-chord-modifier-list


whiteTriangleMarkup = \markup {
  \triangle ##f
  %%  394 capital delta
  %#(ly:wide-char->utf-8 #x0394)

  %% 2206 : delta from the symbol font.
  %   #(ly:wide-char->utf-8 #x2206)
  
  %% up pointing triangle
  % #(ly:wide-char->utf-8 #x25B3)
} 

blackTriangleMarkup = \markup {
  \triangle ##t

  %% black up pointing triangle
%  #(ly:wide-char->utf-8 #x25B2)
}

ignatzekExceptionMusic = {
  <c e gis>1-\markup { "+" }
  <c es ges>-\markup { \super "o" } % should be $\circ$ ?
  <c es ges bes>-\markup {
    %%  f8 is o with slash.
    \normal-size-super #(ly:wide-char->utf-8 #x00f8)
  }
  <c es ges beses>-\markup { \super  "o7" }
  <c e g b fis'>-\markup { \super "lyd" } % Lydian
  <c e g bes des' ees' fis' aes'>-\markup { \super "alt" } % altered chord (super-Locrian)
}

partialJazzMusic = {
  <c d>1-\markup { \normal-size-super "2" }
  <c es>-\markup { "m" }
  <c f>-\markup { \normal-size-super "sus4" }
  <c g>-\markup { \normal-size-super "5" }

  %% TODO, partial exceptions
  <c es f>-\markup { "m" }-\markup { \normal-size-super "sus4" }
  <c d es>-\markup { "m" }-\markup { \normal-size-super "sus2" }
}

powerChordSymbol = {
  <c g>-\markup { \normal-size-super "5" }
  <c g c'>1-\markup { \normal-size-super "5" }
}


%% TODO: compatibility ignatzek code
fullJazzExceptions=
#(sequential-music-to-chord-exceptions ignatzekExceptionMusic #f)

partialJazzExceptions=
#(sequential-music-to-chord-exceptions partialJazzMusic #f)

powerChordExceptions =
#(sequential-music-to-chord-exceptions powerChordSymbol #t)

ignatzekExceptions  =
#(sequential-music-to-chord-exceptions ignatzekExceptionMusic #t)
