\version "2.16.0"

startGroup = #(make-span-event 'NoteGroupingEvent START)
stopGroup = #(make-span-event 'NoteGroupingEvent STOP)


cr = #(make-span-event 'CrescendoEvent START)
decr = #(make-span-event 'DecrescendoEvent START)
enddecr = #(make-span-event 'DecrescendoEvent STOP)
endcr = #(make-span-event 'CrescendoEvent STOP) 


startMeasureCount = #(make-span-event 'MeasureCounterEvent START)
stopMeasureCount = #(make-span-event 'MeasureCounterEvent STOP)


startTextSpan = #(make-span-event 'TextSpanEvent START)
stopTextSpan = #(make-span-event 'TextSpanEvent STOP)


startTrillSpan = #(make-span-event 'TrillSpanEvent START)
stopTrillSpan = #(make-span-event 'TrillSpanEvent STOP)


episemInitium = #(make-span-event 'EpisemaEvent START)
episemFinis = #(make-span-event 'EpisemaEvent STOP)


cresc = #(make-music 'CrescendoEvent 'span-direction START 'span-type 'text 'span-text "cresc.")
endcresc =  #(make-span-event 'CrescendoEvent STOP)
dim = #(make-music 'DecrescendoEvent 'span-direction START 'span-type 'text 'span-text "dim.")
enddim =  #(make-span-event 'DecrescendoEvent STOP)
decresc = #(make-music 'DecrescendoEvent 'span-direction START 'span-type 'text 'span-text "decresc.")
enddecresc =  #(make-span-event 'DecrescendoEvent STOP)

% Deprecated functions:
% TODO: DEPRECATED_2_13_19
deprecatedcresc =  {
  $(make-event-chord (list cr))
  \once \set crescendoText = \markup { \italic "cresc." }
  \once \set crescendoSpanner = #'text
}


deprecateddim =  {
  $(make-event-chord (list decr))
  \once \set decrescendoText = \markup { \italic "dim." }
  \once \set decrescendoSpanner = #'text
}

deprecatedenddim =  {
  $(make-event-chord (list enddecr))
%  \unset decrescendoText 
%  \unset decrescendoSpanner 
}

deprecatedendcresc =  {
  $(make-event-chord (list endcr))
%  \unset crescendoText 
%  \unset crescendoSpanner 
}


%%%%%%%%%%%%%%%%

crescTextCresc = {
    \set crescendoText = \markup { \italic "cresc." }
    \set crescendoSpanner = #'text
}

dimTextDecresc = {
    \set decrescendoText = \markup { \italic "decresc." }
    \set decrescendoSpanner = #'text
}

dimTextDecr = {
    \set decrescendoText = \markup { \italic "decr." }
    \set decrescendoSpanner = #'text
}

dimTextDim = {
    \set decrescendoText = \markup { \italic "dim." }
    \set decrescendoSpanner = #'text
}

crescHairpin = {
    \unset crescendoText 
    \unset crescendoSpanner 
}

dimHairpin = {
    \unset decrescendoText 
    \unset decrescendoSpanner 
}


sustainOff = #(make-span-event 'SustainEvent STOP)
sustainOn = #(make-span-event 'SustainEvent START)

unaCorda = #(make-span-event 'UnaCordaEvent START)
treCorde = #(make-span-event 'UnaCordaEvent STOP)

sostenutoOn = #(make-span-event 'SostenutoEvent START)
sostenutoOff = #(make-span-event 'SostenutoEvent STOP)

%crescpoco = \set crescendoText = "cresc. poco a poco"
%decresc = \set crescendoText = "decr."
%dim = \set crescendoText = "dim."

newSpacingSection = #(make-event-chord (list (make-music 'SpacingSectionEvent)))

breakDynamicSpan = #(make-music 'BreakDynamicSpanEvent)
