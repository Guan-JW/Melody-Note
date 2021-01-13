#!/usr/bin/python
# -*- coding: utf-8 -*-
import optparse
import sys
import re
import os
import string
import codecs
import zipfile
import tempfile
import StringIO

"""

This generic code used for all python scripts.

The quotes are to ensure that the source .py file can still be
run as a python script, but does not include any sys.path handling.
Otherwise, the lilypond-book calls inside the build
might modify installed .pyc files.

"""

for d in ['/usr/share/lilypond/2.18.2',
	  '/usr/lib/lilypond/2.18.2']:
    sys.path.insert (0, os.path.join (d, 'python'))

# dynamic relocation, for GUB binaries.
bindir = os.path.abspath (os.path.dirname (sys.argv[0]))
for p in ['share', 'lib']:
    datadir = os.path.abspath (bindir + '/../%s/lilypond/current/python/' % p)
    sys.path.insert (0, datadir)
"""
"""

import lilylib as ly
_ = ly._

import musicxml
import musicexp

from rational import Rational

# Store command-line options in a global variable, so we can access them everywhere
options = None

class Conversion_Settings:
    def __init__(self):
       self.ignore_beaming = False

conversion_settings = Conversion_Settings ()
# Use a global variable to store the setting needed inside a \layout block.
# whenever we need to change a setting or add/remove an engraver, we can access
# this layout and add the corresponding settings
layout_information = musicexp.Layout ()

needed_additional_definitions = []
additional_definitions = {

  "tuplet-note-wrapper": """      % a formatter function, which is simply a wrapper around an existing
      % tuplet formatter function. It takes the value returned by the given
      % function and appends a note of given length.
  #(define-public ((tuplet-number::append-note-wrapper function note) grob)
    (let* ((txt (if function (function grob) #f)))
      (if txt
        (markup txt #:fontsize -5 #:note note UP)
        (markup #:fontsize -5 #:note note UP)
      )
    )
  )""",

  "tuplet-non-default-denominator": """#(define ((tuplet-number::non-default-tuplet-denominator-text denominator) grob)
  (number->string (if denominator
                      denominator
                      (ly:event-property (event-cause grob) 'denominator))))
""",

  "tuplet-non-default-fraction": """#(define ((tuplet-number::non-default-tuplet-fraction-text denominator numerator) grob)
    (let* ((ev (event-cause grob))
           (den (if denominator denominator (ly:event-property ev 'denominator)))
           (num (if numerator numerator (ly:event-property ev 'numerator))))
       (format #f "~a:~a" den num)))
""",
}

def round_to_two_digits (val):
    return round (val * 100) / 100

def extract_paper_information (tree):
    paper = musicexp.Paper ()
    defaults = tree.get_maybe_exist_named_child ('defaults')
    if not defaults:
        return None
    tenths = -1
    scaling = defaults.get_maybe_exist_named_child ('scaling')
    if scaling:
        mm = scaling.get_named_child ('millimeters')
        mm = string.atof (mm.get_text ())
        tn = scaling.get_maybe_exist_named_child ('tenths')
        tn = string.atof (tn.get_text ())
        tenths = mm / tn
        paper.global_staff_size = mm * 72.27 / 25.4
    # We need the scaling (i.e. the size of staff tenths for everything!
    if tenths < 0:
        return None

    def from_tenths (txt):
        return round_to_two_digits (string.atof (txt) * tenths / 10)
    def set_paper_variable (varname, parent, element_name):
        el = parent.get_maybe_exist_named_child (element_name)
        if el: # Convert to cm from tenths
            setattr (paper, varname, from_tenths (el.get_text ()))

    pagelayout = defaults.get_maybe_exist_named_child ('page-layout')
    if pagelayout:
        # TODO: How can one have different margins for even and odd pages???
        set_paper_variable ("page_height", pagelayout, 'page-height')
        set_paper_variable ("page_width", pagelayout, 'page-width')

        pmargins = pagelayout.get_named_children ('page-margins')
        for pm in pmargins:
            set_paper_variable ("left_margin", pm, 'left-margin')
            set_paper_variable ("right_margin", pm, 'right-margin')
            set_paper_variable ("bottom_margin", pm, 'bottom-margin')
            set_paper_variable ("top_margin", pm, 'top-margin')

    systemlayout = defaults.get_maybe_exist_named_child ('system-layout')
    if systemlayout:
        sl = systemlayout.get_maybe_exist_named_child ('system-margins')
        if sl:
            set_paper_variable ("system_left_margin", sl, 'left-margin')
            set_paper_variable ("system_right_margin", sl, 'right-margin')
        set_paper_variable ("system_distance", systemlayout, 'system-distance')
        set_paper_variable ("top_system_distance", systemlayout, 'top-system-distance')

    stafflayout = defaults.get_named_children ('staff-layout')
    for sl in stafflayout:
        nr = getattr (sl, 'number', 1)
        dist = sl.get_named_child ('staff-distance')
        #TODO: the staff distance needs to be set in the Staff context!!!

    # TODO: Finish appearance?, music-font?, word-font?, lyric-font*, lyric-language*
    appearance = defaults.get_named_child ('appearance')
    if appearance:
        lws = appearance.get_named_children ('line-width')
        for lw in lws:
            # Possible types are: beam, bracket, dashes,
            #    enclosure, ending, extend, heavy barline, leger,
            #    light barline, octave shift, pedal, slur middle, slur tip,
            #    staff, stem, tie middle, tie tip, tuplet bracket, and wedge
            tp = lw.type
            w = from_tenths (lw.get_text  ())
            # TODO: Do something with these values!
        nss = appearance.get_named_children ('note-size')
        for ns in nss:
            # Possible types are: cue, grace and large
            tp = ns.type
            sz = from_tenths (ns.get_text ())
            # TODO: Do something with these values!
        # <other-appearance> elements have no specified meaning

    rawmusicfont = defaults.get_named_child ('music-font')
    if rawmusicfont:
        # TODO: Convert the font
        pass
    rawwordfont = defaults.get_named_child ('word-font')
    if rawwordfont:
        # TODO: Convert the font
        pass
    rawlyricsfonts = defaults.get_named_children ('lyric-font')
    for lyricsfont in rawlyricsfonts:
        # TODO: Convert the font
        pass

    return paper



# score information is contained in the <work>, <identification> or <movement-title> tags
# extract those into a hash, indexed by proper lilypond header attributes
def extract_score_information (tree):
    header = musicexp.Header ()
    def set_if_exists (field, value):
        if value:
            header.set_field (field, musicxml.escape_ly_output_string (value))

    work = tree.get_maybe_exist_named_child ('work')
    if work:
        set_if_exists ('worknumber', work.get_work_number ())
        set_if_exists ('opus', work.get_opus ())

    movement_title = tree.get_maybe_exist_named_child ('movement-title')

    # use either work-title or movement-title as title.
    # if both exist use movement-title as subtitle.
    # if there is only a movement-title (or work-title is empty or missing) the movement-title should be typeset as a title
    if work:
        work_title = work.get_work_title ()
        set_if_exists ('title', work_title)
        if work_title == '':
            set_if_exists ('title', movement_title.get_text ())
        elif movement_title:
            set_if_exists ('subtitle', movement_title.get_text ())
    elif movement_title:
        set_if_exists ('title', movement_title.get_text ())

    identifications = tree.get_named_children ('identification')
    for ids in identifications:
        set_if_exists ('copyright', ids.get_rights ())
        set_if_exists ('composer', ids.get_composer ())
        set_if_exists ('arranger', ids.get_arranger ())
        set_if_exists ('editor', ids.get_editor ())
        set_if_exists ('poet', ids.get_poet ())

        set_if_exists ('encodingsoftware', ids.get_encoding_software ())
        set_if_exists ('encodingdate', ids.get_encoding_date ())
        set_if_exists ('encoder', ids.get_encoding_person ())
        set_if_exists ('encodingdescription', ids.get_encoding_description ())

        set_if_exists ('source', ids.get_source ())

        # miscellaneous --> texidoc
        set_if_exists ('texidoc', ids.get_file_description ());

        # Finally, apply the required compatibility modes
        # Some applications created wrong MusicXML files, so we need to
        # apply some compatibility mode, e.g. ignoring some features/tags
        # in those files
        software = ids.get_encoding_software_list ()

        # Case 1: "Sibelius 5.1" with the "Dolet 3.4 for Sibelius" plugin
        #         is missing all beam ends => ignore all beaming information
        ignore_beaming_software = {
            "Dolet 4 for Sibelius, Beta 2": "Dolet 4 for Sibelius, Beta 2",
            "Dolet 3.5 for Sibelius": "Dolet 3.5 for Sibelius",
            "Dolet 3.4 for Sibelius": "Dolet 3.4 for Sibelius",
            "Dolet 3.3 for Sibelius": "Dolet 3.3 for Sibelius",
            "Dolet 3.2 for Sibelius": "Dolet 3.2 for Sibelius",
            "Dolet 3.1 for Sibelius": "Dolet 3.1 for Sibelius",
            "Dolet for Sibelius 1.3": "Dolet for Sibelius 1.3",
            "Noteworthy Composer": "Noteworthy Composer's nwc2xm[",
        }
        for s in software:
            app_description = ignore_beaming_software.get (s, False);
            if app_description:
                conversion_settings.ignore_beaming = True
                ly.warning (_ ("Encountered file created by %s, containing "
                               "wrong beaming information. All beaming "
                               "information in the MusicXML file will be "
                               "ignored") % app_description)

    # TODO: Check for other unsupported features
    return header

class PartGroupInfo:
    def __init__ (self):
        self.start = {}
        self.end = {}
    def is_empty (self):
        return len (self.start) + len (self.end) == 0
    def add_start (self, g):
        self.start[getattr (g, 'number', "1")] = g
    def add_end (self, g):
        self.end[getattr (g, 'number', "1")] = g
    def print_ly (self, printer):
        ly.warning (_ ("Unprocessed PartGroupInfo %s encountered") % self)
    def ly_expression (self):
        ly.warning (_ ("Unprocessed PartGroupInfo %s encountered") % self)
        return ''

def musicxml_step_to_lily (step):
    if step:
        return (ord (step) - ord ('A') + 7 - 2) % 7
    else:
        return None


def staff_attributes_to_string_tunings (mxl_attr):
    details = mxl_attr.get_maybe_exist_named_child ('staff-details')
    if not details:
        return []
    lines = 6
    staff_lines = details.get_maybe_exist_named_child ('staff-lines')
    if staff_lines:
        lines = string.atoi (staff_lines.get_text ())

    tunings = [musicexp.Pitch()] * lines
    staff_tunings = details.get_named_children ('staff-tuning')
    for i in staff_tunings:
        p = musicexp.Pitch()
        line = 0
        try:
            line = string.atoi (i.line) - 1
        except ValueError:
            pass
        tunings[line] = p

        step = i.get_named_child (u'tuning-step')
        step = step.get_text ().strip ()
        p.step = musicxml_step_to_lily (step)

        octave = i.get_named_child (u'tuning-octave')
        octave = octave.get_text ().strip ()
        p.octave = int (octave) - 4

        alter = i.get_named_child (u'tuning-alter')
        if alter:
            p.alteration = int (alter.get_text ().strip ())
    # lilypond seems to use the opposite ordering than MusicXML...
    tunings.reverse ()

    return tunings


def staff_attributes_to_lily_staff (mxl_attr):
    if not mxl_attr:
        return musicexp.Staff ()

    (staff_id, attributes) = mxl_attr.items ()[0]

    # distinguish by clef:
    # percussion (percussion and rhythmic), tab, and everything else
    clef_sign = None
    clef = attributes.get_maybe_exist_named_child ('clef')
    if clef:
        sign = clef.get_maybe_exist_named_child ('sign')
        if sign:
            clef_sign = {"percussion": "percussion", "TAB": "tab"}.get (sign.get_text (), None)

    lines = 5
    details = attributes.get_named_children ('staff-details')
    for d in details:
        staff_lines = d.get_maybe_exist_named_child ('staff-lines')
        if staff_lines:
            lines = string.atoi (staff_lines.get_text ())

    # TODO: Handle other staff attributes like staff-space, etc.

    staff = None
    if clef_sign == "percussion" and lines == 1:
        staff = musicexp.RhythmicStaff ()
    elif clef_sign == "percussion":
        staff = musicexp.DrumStaff ()
        # staff.drum_style_table = ???
    elif clef_sign == "tab":
        staff = musicexp.TabStaff ()
        staff.string_tunings = staff_attributes_to_string_tunings (attributes)
        # staff.tablature_format = ???
    else:
        staff = musicexp.Staff ()
        # TODO: Handle case with lines <> 5!
        if (lines != 5):
            staff.add_context_modification ("\\override StaffSymbol #'line-count = #%s" % lines)


    return staff


def extract_score_structure (part_list, staffinfo):
    score = musicexp.Score ()
    structure = musicexp.StaffGroup (None)
    score.set_contents (structure)

    if not part_list:
        return structure

    def read_score_part (el):
        if not isinstance (el, musicxml.Score_part):
            return
        # Depending on the attributes of the first measure, we create different
        # types of staves (Staff, RhythmicStaff, DrumStaff, TabStaff, etc.)
        staff = staff_attributes_to_lily_staff (staffinfo.get (el.id, None))
        if not staff:
            return None
        staff.id = el.id
        partname = el.get_maybe_exist_named_child ('part-name')
        # Finale gives unnamed parts the name "MusicXML Part" automatically!
        if partname and partname.get_text() != "MusicXML Part":
            staff.instrument_name = partname.get_text ()
        # part-name-display overrides part-name!
        partname = el.get_maybe_exist_named_child ("part-name-display")
        if partname:
            staff.instrument_name = extract_display_text (partname)

        partdisplay = el.get_maybe_exist_named_child ('part-abbreviation')
        if partdisplay:
            staff.short_instrument_name = partdisplay.get_text ()
        # part-abbreviation-display overrides part-abbreviation!
        partdisplay = el.get_maybe_exist_named_child ("part-abbreviation-display")
        if partdisplay:
            staff.short_instrument_name = extract_display_text (partdisplay)
        # TODO: Read in the MIDI device / instrument

        return staff

    def read_score_group (el):
        if not isinstance (el, musicxml.Part_group):
            return
        group = musicexp.StaffGroup ()
        if hasattr (el, 'number'):
            id = el.number
            group.id = id
            #currentgroups_dict[id] = group
            #currentgroups.append (id)
        if el.get_maybe_exist_named_child ('group-name'):
            group.instrument_name = el.get_maybe_exist_named_child ('group-name').get_text ()
        if el.get_maybe_exist_named_child ('group-abbreviation'):
            group.short_instrument_name = el.get_maybe_exist_named_child ('group-abbreviation').get_text ()
        if el.get_maybe_exist_named_child ('group-symbol'):
            group.symbol = el.get_maybe_exist_named_child ('group-symbol').get_text ()
        if el.get_maybe_exist_named_child ('group-barline'):
            group.spanbar = el.get_maybe_exist_named_child ('group-barline').get_text ()
        return group


    parts_groups = part_list.get_all_children ()

    # the start/end group tags are not necessarily ordered correctly and groups
    # might even overlap, so we can't go through the children sequentially!

    # 1) Replace all Score_part objects by their corresponding Staff objects,
    #    also collect all group start/stop points into one PartGroupInfo object
    staves = []
    group_info = PartGroupInfo ()
    for el in parts_groups:
        if isinstance (el, musicxml.Score_part):
            if not group_info.is_empty ():
                staves.append (group_info)
                group_info = PartGroupInfo ()
            staff = read_score_part (el)
            if staff:
                staves.append (staff)
        elif isinstance (el, musicxml.Part_group):
            if el.type == "start":
                group_info.add_start (el)
            elif el.type == "stop":
                group_info.add_end (el)
    if not group_info.is_empty ():
        staves.append (group_info)

    # 2) Now, detect the groups:
    group_starts = []
    pos = 0
    while pos < len (staves):
        el = staves[pos]
        if isinstance (el, PartGroupInfo):
            prev_start = 0
            if len (group_starts) > 0:
                prev_start = group_starts[-1]
            elif len (el.end) > 0: # no group to end here
                el.end = {}
            if len (el.end) > 0: # closes an existing group
                ends = el.end.keys ()
                prev_started = staves[prev_start].start.keys ()
                grpid = None
                intersection = filter(lambda x:x in ends, prev_started)
                if len (intersection) > 0:
                    grpid = intersection[0]
                else:
                    # Close the last started group
                    grpid = staves[prev_start].start.keys () [0]
                    # Find the corresponding closing tag and remove it!
                    j = pos + 1
                    foundclosing = False
                    while j < len (staves) and not foundclosing:
                        if isinstance (staves[j], PartGroupInfo) and staves[j].end.has_key (grpid):
                            foundclosing = True
                            del staves[j].end[grpid]
                            if staves[j].is_empty ():
                                del staves[j]
                        j += 1
                grpobj = staves[prev_start].start[grpid]
                group = read_score_group (grpobj)
                # remove the id from both the start and end
                if el.end.has_key (grpid):
                    del el.end[grpid]
                del staves[prev_start].start[grpid]
                if el.is_empty ():
                    del staves[pos]
                # replace the staves with the whole group
                for j in staves[(prev_start + 1):pos]:
                    group.append_staff (j)
                del staves[(prev_start + 1):pos]
                staves.insert (prev_start + 1, group)
                # reset pos so that we continue at the correct position
                pos = prev_start
                # remove an empty start group
                if staves[prev_start].is_empty ():
                    del staves[prev_start]
                    group_starts.remove (prev_start)
                    pos -= 1
            elif len (el.start) > 0: # starts new part groups
                group_starts.append (pos)
        pos += 1

    for i in staves:
        structure.append_staff (i)
    return score


def musicxml_duration_to_lily (mxl_note):
    # if the note has no Type child, then that method returns None. In that case,
    # use the <duration> tag instead. If that doesn't exist, either -> Error
    dur = mxl_note.get_duration_info ()
    if dur:
        d = musicexp.Duration ()
        d.duration_log = dur[0]
        d.dots = dur[1]
        # Grace notes by specification have duration 0, so no time modification
        # factor is possible. It even messes up the output with *0/1
        if not mxl_note.get_maybe_exist_typed_child (musicxml.Grace):
            d.factor = mxl_note._duration / d.get_length ()
        return d

    else:
        if mxl_note._duration > 0:
            return rational_to_lily_duration (mxl_note._duration)
        else:
            mxl_note.message (_ ("Encountered note at %s without type and duration (=%s)") % (mxl_note.start, mxl_note._duration) )
            return None


def rational_to_lily_duration (rational_len):
    d = musicexp.Duration ()

    rational_len.normalize_self ()
    d_log = {1: 0, 2: 1, 4:2, 8:3, 16:4, 32:5, 64:6, 128:7, 256:8, 512:9}.get (rational_len.denominator (), -1)

    # Duration of the form 1/2^n or 3/2^n can be converted to a simple lilypond duration
    dots = {1: 0, 3: 1, 7: 2, 15: 3, 31: 4, 63: 5, 127: 6}.get (rational_len.numerator(), -1)
    if ( d_log >= dots >= 0 ):
        # account for the dots!
        d.duration_log = d_log - dots
        d.dots = dots
    elif (d_log >= 0):
        d.duration_log = d_log
        d.factor = Rational (rational_len.numerator ())
    else:
        ly.warning (_ ("Encountered rational duration with denominator %s, "
                       "unable to convert to lilypond duration") %
                    rational_len.denominator ())
        # TODO: Test the above error message
        return None

    return d

def musicxml_partial_to_lily (partial_len):
    if partial_len > 0:
        p = musicexp.Partial ()
        p.partial = rational_to_lily_duration (partial_len)
        return p
    else:
        return None

# Detect repeats and alternative endings in the chord event list (music_list)
# and convert them to the corresponding musicexp objects, containing nested
# music
def group_repeats (music_list):
    repeat_replaced = True
    music_start = 0
    i = 0
    # Walk through the list of expressions, looking for repeat structure
    # (repeat start/end, corresponding endings). If we find one, try to find the
    # last event of the repeat, replace the whole structure and start over again.
    # For nested repeats, as soon as we encounter another starting repeat bar,
    # treat that one first, and start over for the outer repeat.
    while repeat_replaced and i < 100:
        i += 1
        repeat_start = -1  # position of repeat start / end
        repeat_end = -1 # position of repeat start / end
        repeat_times = 0
        ending_start = -1 # position of current ending start
        endings = [] # list of already finished endings
        pos = 0
        last = len (music_list) - 1
        repeat_replaced = False
        final_marker = 0
        while pos < len (music_list) and not repeat_replaced:
            e = music_list[pos]
            repeat_finished = False
            if isinstance (e, RepeatMarker):
                if not repeat_times and e.times:
                    repeat_times = e.times
                if e.direction == -1:
                    if repeat_end >= 0:
                        repeat_finished = True
                    else:
                        repeat_start = pos
                        repeat_end = -1
                        ending_start = -1
                        endings = []
                elif e.direction == 1:
                    if repeat_start < 0:
                        repeat_start = 0
                    if repeat_end < 0:
                        repeat_end = pos
                    final_marker = pos
            elif isinstance (e, EndingMarker):
                if e.direction == -1:
                    if repeat_start < 0:
                        repeat_start = 0
                    if repeat_end < 0:
                        repeat_end = pos
                    ending_start = pos
                elif e.direction == 1:
                    if ending_start < 0:
                        ending_start = 0
                    endings.append ([ending_start, pos])
                    ending_start = -1
                    final_marker = pos
            elif not isinstance (e, musicexp.BarLine):
                # As soon as we encounter an element when repeat start and end
                # is set and we are not inside an alternative ending,
                # this whole repeat structure is finished => replace it
                if repeat_start >= 0 and repeat_end > 0 and ending_start < 0:
                    repeat_finished = True

            # Finish off all repeats without explicit ending bar (e.g. when
            # we convert only one page of a multi-page score with repeats)
            if pos == last and repeat_start >= 0:
                repeat_finished = True
                final_marker = pos
                if repeat_end < 0:
                    repeat_end = pos
                if ending_start >= 0:
                    endings.append ([ending_start, pos])
                    ending_start = -1

            if repeat_finished:
                # We found the whole structure replace it!
                r = musicexp.RepeatedMusic ()
                if repeat_times <= 0:
                    repeat_times = 2
                r.repeat_count = repeat_times
                # don't erase the first element for "implicit" repeats (i.e. no
                # starting repeat bars at the very beginning)
                start = repeat_start + 1
                if repeat_start == music_start:
                    start = music_start
                r.set_music (music_list[start:repeat_end])
                for (start, end) in endings:
                    s = musicexp.SequentialMusic ()
                    s.elements = music_list[start + 1:end]
                    r.add_ending (s)
                del music_list[repeat_start:final_marker + 1]
                music_list.insert (repeat_start, r)
                repeat_replaced = True
            pos += 1
        # TODO: Implement repeats until the end without explicit ending bar
    return music_list


# Extract the settings for tuplets from the <notations><tuplet> and the
# <time-modification> elements of the note:
def musicxml_tuplet_to_lily (tuplet_elt, time_modification):
    tsm = musicexp.TimeScaledMusic ()
    fraction = (1, 1)
    if time_modification:
        fraction = time_modification.get_fraction ()
    tsm.numerator = fraction[0]
    tsm.denominator = fraction[1]


    normal_type = tuplet_elt.get_normal_type ()
    if not normal_type and time_modification:
        normal_type = time_modification.get_normal_type ()
    if not normal_type and time_modification:
        note = time_modification.get_parent ()
        if note:
            normal_type = note.get_duration_info ()
    if normal_type:
        normal_note = musicexp.Duration ()
        (normal_note.duration_log, normal_note.dots) = normal_type
        tsm.normal_type = normal_note

    actual_type = tuplet_elt.get_actual_type ()
    if actual_type:
        actual_note = musicexp.Duration ()
        (actual_note.duration_log, actual_note.dots) = actual_type
        tsm.actual_type = actual_note

    # Obtain non-default nrs of notes from the tuplet object!
    tsm.display_numerator = tuplet_elt.get_normal_nr ()
    tsm.display_denominator = tuplet_elt.get_actual_nr ()


    if hasattr (tuplet_elt, 'bracket') and tuplet_elt.bracket == "no":
        tsm.display_bracket = None
    elif hasattr (tuplet_elt, 'line-shape') and getattr (tuplet_elt, 'line-shape') == "curved":
        tsm.display_bracket = "curved"
    else:
        tsm.display_bracket = "bracket"

    display_values = {"none": None, "actual": "actual", "both": "both"}
    if hasattr (tuplet_elt, "show-number"):
        tsm.display_number = display_values.get (getattr (tuplet_elt, "show-number"), "actual")

    if hasattr (tuplet_elt, "show-type"):
        tsm.display_type = display_values.get (getattr (tuplet_elt, "show-type"), None)

    return tsm


def group_tuplets (music_list, events):


    """Collect Musics from
    MUSIC_LIST demarcated by EVENTS_LIST in TimeScaledMusic objects.
    """


    indices = []
    brackets = {}

    j = 0
    for (ev_chord, tuplet_elt, time_modification) in events:
        while (j < len (music_list)):
            if music_list[j] == ev_chord:
                break
            j += 1
        nr = 0
        if hasattr (tuplet_elt, 'number'):
            nr = getattr (tuplet_elt, 'number')
        if tuplet_elt.type == 'start':
            tuplet_object = musicxml_tuplet_to_lily (tuplet_elt, time_modification)
            tuplet_info = [j, None, tuplet_object]
            indices.append (tuplet_info)
            brackets[nr] = tuplet_info
        elif tuplet_elt.type == 'stop':
            bracket_info = brackets.get (nr, None)
            if bracket_info:
                bracket_info[1] = j # Set the ending position to j
                del brackets[nr]

    new_list = []
    last = 0
    for (i1, i2, tsm) in indices:
        if i1 > i2:
            continue

        new_list.extend (music_list[last:i1])
        seq = musicexp.SequentialMusic ()
        last = i2 + 1
        seq.elements = music_list[i1:last]

        tsm.element = seq

        new_list.append (tsm)
        #TODO: Handle nested tuplets!!!!

    new_list.extend (music_list[last:])
    return new_list


def musicxml_clef_to_lily (attributes):
    change = musicexp.ClefChange ()
    (change.type, change.position, change.octave) = attributes.get_clef_information ()
    return change

def musicxml_time_to_lily (attributes):
    sig = attributes.get_time_signature ()
    if not sig:
        return None
    change = musicexp.TimeSignatureChange()
    change.fractions = sig

    time_elm = attributes.get_maybe_exist_named_child ('time')
    if time_elm and hasattr (time_elm, 'symbol'):
        change.style = { 'single-number': "'single-digit",
                         'cut': None,
                         'common': None,
                         'normal': "'()"}.get (time_elm.symbol, "'()")
    else:
        change.style = "'()"

    # TODO: Handle senza-misura measures
    # TODO: Handle hidden time signatures (print-object="no")
    # TODO: What shall we do if the symbol clashes with the sig? e.g. "cut"
    #       with 3/8 or "single-number" with (2+3)/8 or 3/8+2/4?

    return change

def musicxml_key_to_lily (attributes):
    key_sig = attributes.get_key_signature ()
    if not key_sig or not (isinstance (key_sig, list) or isinstance (key_sig, tuple)):
        ly.warning (_ ("Unable to extract key signature!"))
        return None

    change = musicexp.KeySignatureChange()

    if len (key_sig) == 2 and not isinstance (key_sig[0], list):
        # standard key signature, (fifths, mode)
        (fifths, mode) = key_sig
        change.mode = mode

        start_pitch = musicexp.Pitch ()
        start_pitch.octave = 0
        try:
            (n, a) = {
                'major'     : (0, 0),
                'minor'     : (5, 0),
                'ionian'    : (0, 0),
                'dorian'    : (1, 0),
                'phrygian'  : (2, 0),
                'lydian'    : (3, 0),
                'mixolydian': (4, 0),
                'aeolian'   : (5, 0),
                'locrian'   : (6, 0),
                }[mode]
            start_pitch.step = n
            start_pitch.alteration = a
        except  KeyError:
            ly.warning (_ ("unknown mode %s, expecting 'major' or 'minor' "
                "or a church mode!") % mode)

        fifth = musicexp.Pitch()
        fifth.step = 4
        if fifths < 0:
            fifths *= -1
            fifth.step *= -1
            fifth.normalize ()
        for x in range (fifths):
            start_pitch = start_pitch.transposed (fifth)
        change.tonic = start_pitch

    else:
        # Non-standard key signature of the form [[step,alter<,octave>],...]
        # MusicXML contains C,D,E,F,G,A,B as steps, lily uses 0-7, so convert
        alterations = []
        for k in key_sig:
            k[0] = musicxml_step_to_lily (k[0])
            alterations.append (k)
        change.non_standard_alterations = alterations
    return change

def musicxml_transpose_to_lily (attributes):
    transpose = attributes.get_transposition ()
    if not transpose:
        return None

    shift = musicexp.Pitch ()
    octave_change = transpose.get_maybe_exist_named_child ('octave-change')
    if octave_change:
        shift.octave = string.atoi (octave_change.get_text ())
    chromatic_shift = string.atoi (transpose.get_named_child ('chromatic').get_text ())
    chromatic_shift_normalized = chromatic_shift % 12;
    (shift.step, shift.alteration) = [
        (0, 0), (0, 1), (1, 0), (2, -1), (2, 0),
        (3, 0), (3, 1), (4, 0), (5, -1), (5, 0),
        (6, -1), (6, 0)][chromatic_shift_normalized];

    shift.octave += (chromatic_shift - chromatic_shift_normalized) / 12

    diatonic = transpose.get_maybe_exist_named_child ('diatonic')
    if diatonic:
        diatonic_step = string.atoi (diatonic.get_text ()) % 7
        if diatonic_step != shift.step:
            # We got the alter incorrect!
            old_semitones = shift.semitones ()
            shift.step = diatonic_step
            new_semitones = shift.semitones ()
            shift.alteration += old_semitones - new_semitones

    transposition = musicexp.Transposition ()
    transposition.pitch = musicexp.Pitch ().transposed (shift)
    return transposition

def musicxml_staff_details_to_lily (attributes):
    details = attributes.get_maybe_exist_named_child ('staff-details')
    if not details:
        return None

    ## TODO: Handle staff-type, staff-lines, staff-tuning, capo, staff-size
    ret = []

    stafflines = details.get_maybe_exist_named_child ('staff-lines')
    if stafflines:
        lines = string.atoi (stafflines.get_text ());
        lines_event = musicexp.StaffLinesEvent (lines);
        ret.append (lines_event);

    return ret;


def musicxml_attributes_to_lily (attrs):
    elts = []
    attr_dispatch = {
        'clef': musicxml_clef_to_lily,
        'time': musicxml_time_to_lily,
        'key': musicxml_key_to_lily,
        'transpose': musicxml_transpose_to_lily,
        'staff-details': musicxml_staff_details_to_lily,
    }
    for (k, func) in attr_dispatch.items ():
        children = attrs.get_named_children (k)
        if children:
            ev = func (attrs)
            if isinstance (ev, list):
              for e in ev:
                elts.append (e)
            elif ev:
                elts.append (ev)

    return elts

def extract_display_text (el):
    child = el.get_maybe_exist_named_child ("display-text")
    if child:
        return child.get_text ()
    else:
        return False


def musicxml_print_to_lily (el):
    # TODO: Implement other print attributes
    #  <!ELEMENT print (page-layout?, system-layout?, staff-layout*,
    #          measure-layout?, measure-numbering?, part-name-display?,
    #          part-abbreviation-display?)>
    #  <!ATTLIST print
    #      staff-spacing %tenths; #IMPLIED
    #      new-system %yes-no; #IMPLIED
    #      new-page %yes-no-number; #IMPLIED
    #      blank-page NMTOKEN #IMPLIED
    #      page-number CDATA #IMPLIED
    #  >
    elts = []
    if (hasattr (el, "new-system") and conversion_settings.convert_page_layout):
        val = getattr (el, "new-system")
        if (val == "yes"):
            elts.append (musicexp.Break ("break"))
    if (hasattr (el, "new-page") and conversion_settings.convert_page_layout):
        val = getattr (el, "new-page")
        if (val == "yes"):
            elts.append (musicexp.Break ("pageBreak"))
    child = el.get_maybe_exist_named_child ("part-name-display")
    if child:
        elts.append (musicexp.SetEvent ("Staff.instrumentName",
                                        "\"%s\"" % extract_display_text (child)))
    child = el.get_maybe_exist_named_child ("part-abbreviation-display")
    if child:
        elts.append (musicexp.SetEvent ("Staff.shortInstrumentName",
                                        "\"%s\"" % extract_display_text (child)))
    return elts


class Marker (musicexp.Music):
    def __init__ (self):
        self.direction = 0
        self.event = None
    def print_ly (self, printer):
        ly.warning (_ ("Encountered unprocessed marker %s\n") % self)
        pass
    def ly_expression (self):
        return ""
class RepeatMarker (Marker):
    def __init__ (self):
        Marker.__init__ (self)
        self.times = 0
class EndingMarker (Marker):
    pass

# Convert the <barline> element to musicxml.BarLine (for non-standard barlines)
# and to RepeatMarker and EndingMarker objects for repeat and
# alternatives start/stops
def musicxml_barline_to_lily (barline):
    # retval contains all possible markers in the order:
    # 0..bw_ending, 1..bw_repeat, 2..barline, 3..fw_repeat, 4..fw_ending
    retval = {}
    bartype_element = barline.get_maybe_exist_named_child ("bar-style")
    repeat_element = barline.get_maybe_exist_named_child ("repeat")
    ending_element = barline.get_maybe_exist_named_child ("ending")

    bartype = None
    if bartype_element:
        bartype = bartype_element.get_text ()

    if repeat_element and hasattr (repeat_element, 'direction'):
        repeat = RepeatMarker ()
        repeat.direction = {"forward": -1, "backward": 1}.get (repeat_element.direction, 0)

        if ( (repeat_element.direction == "forward" and bartype == "heavy-light") or
             (repeat_element.direction == "backward" and bartype == "light-heavy") ):
            bartype = None
        if hasattr (repeat_element, 'times'):
            try:
                repeat.times = int (repeat_element.times)
            except ValueError:
                repeat.times = 2
        repeat.event = barline
        if repeat.direction == -1:
            retval[3] = repeat
        else:
            retval[1] = repeat

    if ending_element and hasattr (ending_element, 'type'):
        ending = EndingMarker ()
        ending.direction = {"start": -1, "stop": 1, "discontinue": 1}.get (ending_element.type, 0)
        ending.event = barline
        if ending.direction == -1:
            retval[4] = ending
        else:
            retval[0] = ending

    if bartype:
        b = musicexp.BarLine ()
        b.type = bartype
        retval[2] = b

    return retval.values ()

spanner_event_dict = {
    'beam' : musicexp.BeamEvent,
    'dashes' : musicexp.TextSpannerEvent,
    'bracket' : musicexp.BracketSpannerEvent,
    'glissando' : musicexp.GlissandoEvent,
    'octave-shift' : musicexp.OctaveShiftEvent,
    'pedal' : musicexp.PedalEvent,
    'slide' : musicexp.GlissandoEvent,
    'slur' : musicexp.SlurEvent,
    'wavy-line' : musicexp.TrillSpanEvent,
    'wedge' : musicexp.HairpinEvent
}
spanner_type_dict = {
    'start': -1,
    'begin': -1,
    'crescendo': -1,
    'decreschendo': -1,
    'diminuendo': -1,
    'continue': 0,
    'change': 0,
    'up': -1,
    'down': -1,
    'stop': 1,
    'end' : 1
}

def musicxml_spanner_to_lily_event (mxl_event):
    ev = None

    name = mxl_event.get_name()
    func = spanner_event_dict.get (name)
    if func:
        ev = func()
    else:
        ly.warning (_ ('unknown span event %s') % mxl_event)


    type = mxl_event.get_type ()
    span_direction = spanner_type_dict.get (type)
    # really check for None, because some types will be translated to 0, which
    # would otherwise also lead to the unknown span warning
    if span_direction != None:
        ev.span_direction = span_direction
    else:
        ly.warning (_ ('unknown span type %s for %s') % (type, name))

    ev.set_span_type (type)
    ev.line_type = getattr (mxl_event, 'line-type', 'solid')

    # assign the size, which is used for octave-shift, etc.
    ev.size = mxl_event.get_size ()

    return ev

def musicxml_direction_to_indicator (direction):
    return { "above": 1, "upright": 1, "up": 1, "below": -1, "downright": -1, "down": -1, "inverted": -1 }.get (direction, 0)

def musicxml_fermata_to_lily_event (mxl_event):
    ev = musicexp.ArticulationEvent ()
    txt = mxl_event.get_text ()
    # The contents of the element defined the shape, possible are normal, angled and square
    ev.type = { "angled": "shortfermata", "square": "longfermata" }.get (txt, "fermata")
    if hasattr (mxl_event, 'type'):
      dir = musicxml_direction_to_indicator (mxl_event.type)
      if dir and options.convert_directions:
        ev.force_direction = dir
    return ev

def musicxml_arpeggiate_to_lily_event (mxl_event):
    ev = musicexp.ArpeggioEvent ()
    ev.direction = musicxml_direction_to_indicator (getattr (mxl_event, 'direction', None))
    return ev

def musicxml_nonarpeggiate_to_lily_event (mxl_event):
    ev = musicexp.ArpeggioEvent ()
    ev.non_arpeggiate = True
    ev.direction = musicxml_direction_to_indicator (getattr (mxl_event, 'direction', None))
    return ev

def musicxml_tremolo_to_lily_event (mxl_event):
    ev = musicexp.TremoloEvent ()
    txt = mxl_event.get_text ()
    if txt:
      ev.bars = txt
    else:
      ev.bars = "3"
    return ev

def musicxml_falloff_to_lily_event (mxl_event):
    ev = musicexp.BendEvent ()
    ev.alter = -4
    return ev

def musicxml_doit_to_lily_event (mxl_event):
    ev = musicexp.BendEvent ()
    ev.alter = 4
    return ev

def musicxml_bend_to_lily_event (mxl_event):
    ev = musicexp.BendEvent ()
    ev.alter = mxl_event.bend_alter ()
    return ev

def musicxml_caesura_to_lily_event (mxl_event):
    ev = musicexp.MarkupEvent ()
    # FIXME: default to straight or curved caesura?
    ev.contents = "\\musicglyph #\"scripts.caesura.straight\""
    ev.force_direction = 1
    return ev

def musicxml_fingering_event (mxl_event):
    ev = musicexp.ShortArticulationEvent ()
    ev.type = mxl_event.get_text ()
    return ev

def musicxml_string_event (mxl_event):
    ev = musicexp.NoDirectionArticulationEvent ()
    ev.type = mxl_event.get_text ()
    return ev

def musicxml_accidental_mark (mxl_event):
    ev = musicexp.MarkupEvent ()
    contents = { "sharp": "\\sharp",
      "natural": "\\natural",
      "flat": "\\flat",
      "double-sharp": "\\doublesharp",
      "sharp-sharp": "\\sharp\\sharp",
      "flat-flat": "\\flat\\flat",
      "flat-flat": "\\doubleflat",
      "natural-sharp": "\\natural\\sharp",
      "natural-flat": "\\natural\\flat",
      "quarter-flat": "\\semiflat",
      "quarter-sharp": "\\semisharp",
      "three-quarters-flat": "\\sesquiflat",
      "three-quarters-sharp": "\\sesquisharp",
    }.get (mxl_event.get_text ())
    if contents:
        ev.contents = contents
        return ev
    else:
        return None

# translate articulations, ornaments and other notations into ArticulationEvents
# possible values:
#   -) string  (ArticulationEvent with that name)
#   -) function (function(mxl_event) needs to return a full ArticulationEvent-derived object
#   -) (class, name)  (like string, only that a different class than ArticulationEvent is used)
# TODO: Some translations are missing!
articulations_dict = {
    "accent": (musicexp.ShortArticulationEvent, ">"), # or "accent"
    "accidental-mark": musicxml_accidental_mark,
    "bend": musicxml_bend_to_lily_event,
    "breath-mark": (musicexp.NoDirectionArticulationEvent, "breathe"),
    "caesura": musicxml_caesura_to_lily_event,
    #"delayed-turn": "?",
    "detached-legato": (musicexp.ShortArticulationEvent, "_"), # or "portato"
    "doit": musicxml_doit_to_lily_event,
    #"double-tongue": "?",
    "down-bow": "downbow",
    "falloff": musicxml_falloff_to_lily_event,
    "fingering": musicxml_fingering_event,
    #"fingernails": "?",
    #"fret": "?",
    #"hammer-on": "?",
    "harmonic": "flageolet",
    #"heel": "?",
    "inverted-mordent": "prall",
    "inverted-turn": "reverseturn",
    "mordent": "mordent",
    "open-string": "open",
    #"plop": "?",
    #"pluck": "?",
    #"pull-off": "?",
    #"schleifer": "?",
    #"scoop": "?",
    #"shake": "?",
    "snap-pizzicato": "snappizzicato",
    #"spiccato": "?",
    "staccatissimo": (musicexp.ShortArticulationEvent, "!"), # or "staccatissimo"
    "staccato": (musicexp.ShortArticulationEvent, "."), # or "staccato"
    "stopped": (musicexp.ShortArticulationEvent, "+"), # or "stopped"
    #"stress": "?",
    "string": musicxml_string_event,
    "strong-accent": (musicexp.ShortArticulationEvent, "^"), # or "marcato"
    #"tap": "?",
    "tenuto": (musicexp.ShortArticulationEvent, "-"), # or "tenuto"
    "thumb-position": "thumb",
    #"toe": "?",
    "turn": "turn",
    "tremolo": musicxml_tremolo_to_lily_event,
    "trill-mark": "trill",
    #"triple-tongue": "?",
    #"unstress": "?"
    "up-bow": "upbow",
    #"wavy-line": "?",
}
articulation_spanners = [ "wavy-line" ]

def musicxml_articulation_to_lily_event (mxl_event):
    # wavy-line elements are treated as trill spanners, not as articulation ornaments
    if mxl_event.get_name () in articulation_spanners:
        return musicxml_spanner_to_lily_event (mxl_event)

    tmp_tp = articulations_dict.get (mxl_event.get_name ())
    if not tmp_tp:
        return

    if isinstance (tmp_tp, str):
        ev = musicexp.ArticulationEvent ()
        ev.type = tmp_tp
    elif isinstance (tmp_tp, tuple):
        ev = tmp_tp[0] ()
        ev.type = tmp_tp[1]
    else:
        ev = tmp_tp (mxl_event)

    # Some articulations use the type attribute, other the placement...
    dir = None
    if hasattr (mxl_event, 'type') and options.convert_directions:
        dir = musicxml_direction_to_indicator (mxl_event.type)
    if hasattr (mxl_event, 'placement') and options.convert_directions:
        dir = musicxml_direction_to_indicator (mxl_event.placement)
    if dir:
        ev.force_direction = dir
    return ev



def musicxml_dynamics_to_lily_event (dynentry):
    dynamics_available = (
        "ppppp", "pppp", "ppp", "pp", "p", "mp", "mf",
        "f", "ff", "fff", "ffff", "fp", "sf", "sff", "sp", "spp", "sfz", "rfz" )
    dynamicsname = dynentry.get_name ()
    if dynamicsname == "other-dynamics":
        dynamicsname = dynentry.get_text ()
    if not dynamicsname or dynamicsname == "#text":
        return

    if not dynamicsname in dynamics_available:
        # Get rid of - in tag names (illegal in ly tags!)
        dynamicstext = dynamicsname
        dynamicsname = string.replace (dynamicsname, "-", "")
        additional_definitions[dynamicsname] = dynamicsname + \
              " = #(make-dynamic-script \"" + dynamicstext + "\")"
        needed_additional_definitions.append (dynamicsname)
    event = musicexp.DynamicsEvent ()
    event.type = dynamicsname
    return event

# Convert single-color two-byte strings to numbers 0.0 - 1.0
def hexcolorval_to_nr (hex_val):
    try:
        v = int (hex_val, 16)
        if v == 255:
            v = 256
        return v / 256.
    except ValueError:
        return 0.

def hex_to_color (hex_val):
    res = re.match (r'#([0-9a-f][0-9a-f]|)([0-9a-f][0-9a-f])([0-9a-f][0-9a-f])([0-9a-f][0-9a-f])$', hex_val, re.IGNORECASE)
    if res:
        return map (lambda x: hexcolorval_to_nr (x), res.group (2, 3, 4))
    else:
        return None

def musicxml_words_to_lily_event (words):
    event = musicexp.TextEvent ()
    text = words.get_text ()
    text = re.sub ('^ *\n? *', '', text)
    text = re.sub (' *\n? *$', '', text)
    event.text = text

    if hasattr (words, 'default-y') and options.convert_directions:
        offset = getattr (words, 'default-y')
        try:
            off = string.atoi (offset)
            if off > 0:
                event.force_direction = 1
            else:
                event.force_direction = -1
        except ValueError:
            event.force_direction = 0

    if hasattr (words, 'font-weight'):
        font_weight = { "normal": '', "bold": '\\bold' }.get (getattr (words, 'font-weight'), '')
        if font_weight:
            event.markup += font_weight

    if hasattr (words, 'font-size'):
        size = getattr (words, 'font-size')
        font_size = {
            "xx-small": '\\teeny',
            "x-small": '\\tiny',
            "small": '\\small',
            "medium": '',
            "large": '\\large',
            "x-large": '\\huge',
            "xx-large": '\\larger\\huge'
        }.get (size, '')
        if font_size:
            event.markup += font_size

    if hasattr (words, 'color'):
        color = getattr (words, 'color')
        rgb = hex_to_color (color)
        if rgb:
            event.markup += "\\with-color #(rgb-color %s %s %s)" % (rgb[0], rgb[1], rgb[2])

    if hasattr (words, 'font-style'):
        font_style = { "italic": '\\italic' }.get (getattr (words, 'font-style'), '')
        if font_style:
            event.markup += font_style

    # TODO: How should I best convert the font-family attribute?

    # TODO: How can I represent the underline, overline and line-through
    #       attributes in LilyPond? Values of these attributes indicate
    #       the number of lines

    return event


# convert accordion-registration to lilypond.
# Since lilypond does not have any built-in commands, we need to create
# the markup commands manually and define our own variables.
# Idea was taken from: http://lsr.dsi.unimi.it/LSR/Item?id=194
def musicxml_accordion_to_markup (mxl_event):
    commandname = "accReg"
    command = ""

    high = mxl_event.get_maybe_exist_named_child ('accordion-high')
    if high:
        commandname += "H"
        command += """\\combine
          \\raise #2.5 \\musicglyph #\"accordion.dot\"
          """
    middle = mxl_event.get_maybe_exist_named_child ('accordion-middle')
    if middle:
        # By default, use one dot (when no or invalid content is given). The
        # MusicXML spec is quiet about this case...
        txt = 1
        try:
          txt = string.atoi (middle.get_text ())
        except ValueError:
            pass
        if txt == 3:
            commandname += "MMM"
            command += """\\combine
          \\raise #1.5 \\musicglyph #\"accordion.dot\"
          \\combine
          \\raise #1.5 \\translate #(cons 1 0) \\musicglyph #\"accordion.dot\"
          \\combine
          \\raise #1.5 \\translate #(cons -1 0) \\musicglyph #\"accordion.dot\"
          """
        elif txt == 2:
            commandname += "MM"
            command += """\\combine
          \\raise #1.5 \\translate #(cons 0.5 0) \\musicglyph #\"accordion.dot\"
          \\combine
          \\raise #1.5 \\translate #(cons -0.5 0) \\musicglyph #\"accordion.dot\"
          """
        elif not txt <= 0:
            commandname += "M"
            command += """\\combine
          \\raise #1.5 \\musicglyph #\"accordion.dot\"
          """
    low = mxl_event.get_maybe_exist_named_child ('accordion-low')
    if low:
        commandname += "L"
        command += """\\combine
          \\raise #0.5 \musicglyph #\"accordion.dot\"
          """

    command += "\musicglyph #\"accordion.discant\""
    command = "\\markup { \\normalsize %s }" % command
    # Define the newly built command \accReg[H][MMM][L]
    additional_definitions[commandname] = "%s = %s" % (commandname, command)
    needed_additional_definitions.append (commandname)
    return "\\%s" % commandname

def musicxml_accordion_to_ly (mxl_event):
    txt = musicxml_accordion_to_markup (mxl_event)
    if txt:
        ev = musicexp.MarkEvent (txt)
        return ev
    return


def musicxml_rehearsal_to_ly_mark (mxl_event):
    text = mxl_event.get_text ()
    if not text:
        return
    # default is boxed rehearsal marks!
    encl = "box"
    if hasattr (mxl_event, 'enclosure'):
        encl = {"none": None, "square": "box", "circle": "circle" }.get (mxl_event.enclosure, None)
    if encl:
        text = "\\%s { %s }" % (encl, text)
    ev = musicexp.MarkEvent ("\\markup { %s }" % text)
    return ev

def musicxml_harp_pedals_to_ly (mxl_event):
    count = 0
    result = "\\harp-pedal #\""
    for t in mxl_event.get_named_children ('pedal-tuning'):
      alter = t.get_named_child ('pedal-alter')
      if alter:
        val = int (alter.get_text ().strip ())
        result += {1: "v", 0: "-", -1: "^"}.get (val, "")
      count += 1
      if count == 3:
        result += "|"
    ev = musicexp.MarkupEvent ()
    ev.contents = result + "\""
    return ev

def musicxml_eyeglasses_to_ly (mxl_event):
    needed_additional_definitions.append ("eyeglasses")
    return musicexp.MarkEvent ("\\markup { \\eyeglasses }")

def next_non_hash_index (lst, pos):
    pos += 1
    while pos < len (lst) and isinstance (lst[pos], musicxml.Hash_text):
        pos += 1
    return pos

def musicxml_metronome_to_ly (mxl_event):
    children = mxl_event.get_all_children ()
    if not children:
        return

    index = -1
    index = next_non_hash_index (children, index)
    if isinstance (children[index], musicxml.BeatUnit):
        # first form of metronome-mark, using unit and beats/min or other unit
        ev = musicexp.TempoMark ()
        if hasattr (mxl_event, 'parentheses'):
            ev.set_parentheses (mxl_event.parentheses == "yes")

        d = musicexp.Duration ()
        d.duration_log = musicxml.musicxml_duration_to_log (children[index].get_text ())
        index = next_non_hash_index (children, index)
        if isinstance (children[index], musicxml.BeatUnitDot):
            d.dots = 1
            index = next_non_hash_index (children, index)
        ev.set_base_duration (d)
        if isinstance (children[index], musicxml.BeatUnit):
            # Form "note = newnote"
            newd = musicexp.Duration ()
            newd.duration_log = musicxml.musicxml_duration_to_log (children[index].get_text ())
            index = next_non_hash_index (children, index)
            if isinstance (children[index], musicxml.BeatUnitDot):
                newd.dots = 1
                index = next_non_hash_index (children, index)
            ev.set_new_duration (newd)
        elif isinstance (children[index], musicxml.PerMinute):
            # Form "note = bpm"
            try:
                beats = int (children[index].get_text ())
                ev.set_beats_per_minute (beats)
            except ValueError:
                pass
        else:
            ly.warning (_ ("Unknown metronome mark, ignoring"))
            return
        return ev
    else:
        #TODO: Implement the other (more complex) way for tempo marks!
        ly.warning (_ ("Metronome marks with complex relations (<metronome-note> in MusicXML) are not yet implemented."))
        return

# translate directions into Events, possible values:
#   -) string  (MarkEvent with that command)
#   -) function (function(mxl_event) needs to return a full Event-derived object
#   -) (class, name)  (like string, only that a different class than MarkEvent is used)
directions_dict = {
    'accordion-registration' : musicxml_accordion_to_ly,
    'coda' : (musicexp.MusicGlyphMarkEvent, "coda"),
#     'damp' : ???
#     'damp-all' : ???
    'eyeglasses': musicxml_eyeglasses_to_ly,
    'harp-pedals' : musicxml_harp_pedals_to_ly,
#     'image' : ???
    'metronome' : musicxml_metronome_to_ly,
    'rehearsal' : musicxml_rehearsal_to_ly_mark,
#     'scordatura' : ???
    'segno' : (musicexp.MusicGlyphMarkEvent, "segno"),
    'words' : musicxml_words_to_lily_event,
}
directions_spanners = [ 'octave-shift', 'pedal', 'wedge', 'dashes', 'bracket' ]

def musicxml_direction_to_lily (n):
    # TODO: Handle the <staff> element!
    res = []
    # placement applies to all children!
    dir = None
    if hasattr (n, 'placement') and options.convert_directions:
        dir = musicxml_direction_to_indicator (n.placement)
    dirtype_children = []
    # TODO: The direction-type is used for grouping (e.g. dynamics with text),
    #       so we can't simply flatten them out!
    for dt in n.get_typed_children (musicxml.DirType):
        dirtype_children += dt.get_all_children ()

    for entry in dirtype_children:
        # backets, dashes, octave shifts. pedal marks, hairpins etc. are spanners:
        if entry.get_name() in directions_spanners:
            event = musicxml_spanner_to_lily_event (entry)
            if event:
                res.append (event)
            continue

        # now treat all the "simple" ones, that can be translated using the dict
        ev = None
        tmp_tp = directions_dict.get (entry.get_name (), None)
        if isinstance (tmp_tp, str): # string means MarkEvent
            ev = musicexp.MarkEvent (tmp_tp)
        elif isinstance (tmp_tp, tuple): # tuple means (EventClass, "text")
            ev = tmp_tp[0] (tmp_tp[1])
        elif tmp_tp:
            ev = tmp_tp (entry)
        if ev:
            # TODO: set the correct direction! Unfortunately, \mark in ly does
            #       not seem to support directions!
            ev.force_direction = dir
            res.append (ev)
            continue

        if entry.get_name () == "dynamics":
            for dynentry in entry.get_all_children ():
                ev = musicxml_dynamics_to_lily_event (dynentry)
                if ev:
                    res.append (ev)

    return res

def musicxml_frame_to_lily_event (frame):
    ev = musicexp.FretEvent ()
    ev.strings = frame.get_strings ()
    ev.frets = frame.get_frets ()
    #offset = frame.get_first_fret () - 1
    barre = []
    for fn in frame.get_named_children ('frame-note'):
        fret = fn.get_fret ()
        if fret <= 0:
            fret = "o"
        el = [ fn.get_string (), fret ]
        fingering = fn.get_fingering ()
        if fingering >= 0:
            el.append (fingering)
        ev.elements.append (el)
        b = fn.get_barre ()
        if b == 'start':
            barre[0] = el[0] # start string
            barre[2] = el[1] # fret
        elif b == 'stop':
            barre[1] = el[0] # end string
    if barre:
        ev.barre = barre
    return ev

def musicxml_harmony_to_lily (n):
    res = []
    for f in n.get_named_children ('frame'):
        ev = musicxml_frame_to_lily_event (f)
        if ev:
            res.append (ev)
    return res


notehead_styles_dict = {
    'slash': '\'slash',
    'triangle': '\'triangle',
    'diamond': '\'diamond',
    'square': '\'la', # TODO: Proper squared note head
    'cross': None, # TODO: + shaped note head
    'x': '\'cross',
    'circle-x': '\'xcircle',
    'inverted triangle': None, # TODO: Implement
    'arrow down': None, # TODO: Implement
    'arrow up': None, # TODO: Implement
    'slashed': None, # TODO: Implement
    'back slashed': None, # TODO: Implement
    'normal': None,
    'cluster': None, # TODO: Implement
    'none': '#f',
    'do': '\'do',
    're': '\'re',
    'mi': '\'mi',
    'fa': '\'fa',
    'so': None,
    'la': '\'la',
    'ti': '\'ti',
    }

def musicxml_notehead_to_lily (nh):
    styles = []

    # Notehead style
    style = notehead_styles_dict.get (nh.get_text ().strip (), None)
    style_elm = musicexp.NotestyleEvent ()
    if style:
        style_elm.style = style
    if hasattr (nh, 'filled'):
        style_elm.filled = (getattr (nh, 'filled') == "yes")
    if style_elm.style or (style_elm.filled != None):
        styles.append (style_elm)

    # parentheses
    if hasattr (nh, 'parentheses') and (nh.parentheses == "yes"):
        styles.append (musicexp.ParenthesizeEvent ())

    return styles

def musicxml_chordpitch_to_lily (mxl_cpitch):
    r = musicexp.ChordPitch ()
    r.alteration = mxl_cpitch.get_alteration ()
    r.step = musicxml_step_to_lily (mxl_cpitch.get_step ())
    return r

chordkind_dict = {
    'major': '5',
    'minor': 'm5',
    'augmented': 'aug5',
    'diminished': 'dim5',
        # Sevenths:
    'dominant': '7',
    'dominant-seventh': '7',
    'major-seventh': 'maj7',
    'minor-seventh': 'm7',
    'diminished-seventh': 'dim7',
    'augmented-seventh': 'aug7',
    'half-diminished': 'dim5m7',
    'major-minor': 'maj7m5',
        # Sixths:
    'major-sixth': '6',
    'minor-sixth': 'm6',
        # Ninths:
    'dominant-ninth': '9',
    'major-ninth': 'maj9',
    'minor-ninth': 'm9',
        # 11ths (usually as the basis for alteration):
    'dominant-11th': '11',
    'major-11th': 'maj11',
    'minor-11th': 'm11',
        # 13ths (usually as the basis for alteration):
    'dominant-13th': '13.11',
    'major-13th': 'maj13.11',
    'minor-13th': 'm13',
        # Suspended:
    'suspended-second': 'sus2',
    'suspended-fourth': 'sus4',
        # Functional sixths:
    # TODO
    #'Neapolitan': '???',
    #'Italian': '???',
    #'French': '???',
    #'German': '???',
        # Other:
    #'pedal': '???',(pedal-point bass)
    'power': '5^3',
    #'Tristan': '???',
    'other': '1',
    'none': None,
}

def musicxml_chordkind_to_lily (kind):
    res = chordkind_dict.get (kind, None)
    # Check for None, since a major chord is converted to ''
    if res == None:
        ly.warning (_ ("Unable to convert chord type %s to lilypond.") % kind)
    return res

def musicxml_harmony_to_lily_chordname (n):
    res = []
    root = n.get_maybe_exist_named_child ('root')
    if root:
        ev = musicexp.ChordNameEvent ()
        ev.root = musicxml_chordpitch_to_lily (root)
        kind = n.get_maybe_exist_named_child ('kind')
        if kind:
            ev.kind = musicxml_chordkind_to_lily (kind.get_text ())
            if not ev.kind:
                return res
        bass = n.get_maybe_exist_named_child ('bass')
        if bass:
            ev.bass = musicxml_chordpitch_to_lily (bass)
        inversion = n.get_maybe_exist_named_child ('inversion')
        if inversion:
            # TODO: LilyPond does not support inversions, does it?

            # Mail from Carl Sorensen on lilypond-devel, June 11, 2008:
            # 4. LilyPond supports the first inversion in the form of added
            # bass notes.  So the first inversion of C major would be c:/g.
            # To get the second inversion of C major, you would need to do
            # e:6-3-^5 or e:m6-^5.  However, both of these techniques
            # require you to know the chord and calculate either the fifth
            # pitch (for the first inversion) or the third pitch (for the
            # second inversion) so they may not be helpful for musicxml2ly.
            inversion_count = string.atoi (inversion.get_text ())
            if inversion_count == 1:
              # TODO: Calculate the bass note for the inversion...
              pass
            pass
        for deg in n.get_named_children ('degree'):
            d = musicexp.ChordModification ()
            d.type = deg.get_type ()
            d.step = deg.get_value ()
            d.alteration = deg.get_alter ()
            ev.add_modification (d)
        #TODO: convert the user-symbols attribute:
            #major: a triangle, like Unicode 25B3
            #minor: -, like Unicode 002D
            #augmented: +, like Unicode 002B
            #diminished: (degree), like Unicode 00B0
            #half-diminished: (o with slash), like Unicode 00F8
        if ev and ev.root:
            res.append (ev)

    return res

def musicxml_figured_bass_note_to_lily (n):
    res = musicexp.FiguredBassNote ()
    suffix_dict = { 'sharp' : "+",
                    'flat' : "-",
                    'natural' : "!",
                    'double-sharp' : "++",
                    'flat-flat' : "--",
                    'sharp-sharp' : "++",
                    'slash' : "/" }
    prefix = n.get_maybe_exist_named_child ('prefix')
    if prefix:
        res.set_prefix (suffix_dict.get (prefix.get_text (), ""))
    fnumber = n.get_maybe_exist_named_child ('figure-number')
    if fnumber:
        res.set_number (fnumber.get_text ())
    suffix = n.get_maybe_exist_named_child ('suffix')
    if suffix:
        res.set_suffix (suffix_dict.get (suffix.get_text (), ""))
    if n.get_maybe_exist_named_child ('extend'):
        # TODO: Implement extender lines (unfortunately, in lilypond you have
        #       to use \set useBassFigureExtenders = ##t, which turns them on
        #       globally, while MusicXML has a property for each note...
        #       I'm not sure there is a proper way to implement this cleanly
        #n.extend
        pass
    return res



def musicxml_figured_bass_to_lily (n):
    if not isinstance (n, musicxml.FiguredBass):
        return
    res = musicexp.FiguredBassEvent ()
    for i in n.get_named_children ('figure'):
        note = musicxml_figured_bass_note_to_lily (i)
        if note:
            res.append (note)
    dur = n.get_maybe_exist_named_child ('duration')
    if dur:
        # apply the duration to res
        length = Rational(int(dur.get_text()), n._divisions) * Rational(1, 4)
        res.set_real_duration (length)
        duration = rational_to_lily_duration (length)
        if duration:
            res.set_duration (duration)
    if hasattr (n, 'parentheses') and n.parentheses == "yes":
        res.set_parentheses (True)
    return res

instrument_drumtype_dict = {
    'Acoustic Snare Drum': 'acousticsnare',
    'Side Stick': 'sidestick',
    'Open Triangle': 'opentriangle',
    'Mute Triangle': 'mutetriangle',
    'Tambourine': 'tambourine',
    'Bass Drum': 'bassdrum',
}

def musicxml_note_to_lily_main_event (n):
    pitch = None
    duration = None
    event = None

    mxl_pitch = n.get_maybe_exist_typed_child (musicxml.Pitch)
    if mxl_pitch:
        pitch = musicxml_pitch_to_lily (mxl_pitch)
        event = musicexp.NoteEvent ()
        event.pitch = pitch

        acc = n.get_maybe_exist_named_child ('accidental')
        if acc:
            # AccidentalCautionary in lily has parentheses
            # so treat accidental explicitly in parentheses as cautionary
            if hasattr(acc, 'parentheses') and acc.parentheses == "yes":
                event.cautionary = True
            else:
                event.cautionary = acc.cautionary
            # TODO: Handle editorial accidentals
            # TODO: Handle the level-display setting for displaying brackets/parentheses

    elif n.get_maybe_exist_typed_child (musicxml.Unpitched):
        # Unpitched elements have display-step and can also have
        # display-octave.
        unpitched = n.get_maybe_exist_typed_child (musicxml.Unpitched)
        event = musicexp.NoteEvent ()
        event.pitch = musicxml_unpitched_to_lily (unpitched)

    elif n.get_maybe_exist_typed_child (musicxml.Rest):
        # rests can have display-octave and display-step, which are
        # treated like an ordinary note pitch
        rest = n.get_maybe_exist_typed_child (musicxml.Rest)
        event = musicexp.RestEvent ()
        if options.convert_rest_positions:
            pitch = musicxml_restdisplay_to_lily (rest)
            event.pitch = pitch

    elif n.instrument_name:
        event = musicexp.NoteEvent ()
        drum_type = instrument_drumtype_dict.get (n.instrument_name)
        if drum_type:
            event.drum_type = drum_type
        else:
            n.message (_ ("drum %s type unknown, please add to instrument_drumtype_dict") % n.instrument_name)
            event.drum_type = 'acousticsnare'

    else:
        n.message (_ ("cannot find suitable event"))

    if event:
        event.duration = musicxml_duration_to_lily (n)

    noteheads = n.get_named_children ('notehead')
    for nh in noteheads:
        styles = musicxml_notehead_to_lily (nh)
        for s in styles:
            event.add_associated_event (s)

    return event

def musicxml_lyrics_to_text (lyrics):
    # TODO: Implement text styles for lyrics syllables
    continued = False
    extended = False
    text = ''
    for e in lyrics.get_all_children ():
        if isinstance (e, musicxml.Syllabic):
            continued = e.continued ()
        elif isinstance (e, musicxml.Text):
            # We need to convert soft hyphens to -, otherwise the ascii codec as well
            # as lilypond will barf on that character
            text += string.replace( e.get_text(), u'\xad', '-' )
        elif isinstance (e, musicxml.Elision):
            if text:
                text += " "
            continued = False
            extended = False
        elif isinstance (e, musicxml.Extend):
            if text:
                text += " "
            extended = True

    if text == "-" and continued:
        return "--"
    elif text == "_" and extended:
        return "__"
    elif continued and text:
        return musicxml.escape_ly_output_string (text) + " --"
    elif continued:
        return "--"
    elif extended and text:
        return musicxml.escape_ly_output_string (text) + " __"
    elif extended:
        return "__"
    elif text:
        return musicxml.escape_ly_output_string (text)
    else:
        return ""

## TODO
class NegativeSkip:
    def __init__ (self, here, dest):
        self.here = here
        self.dest = dest

class LilyPondVoiceBuilder:
    def __init__ (self):
        self.elements = []
        self.pending_dynamics = []
        self.end_moment = Rational (0)
        self.begin_moment = Rational (0)
        self.pending_multibar = Rational (0)
        self.ignore_skips = False
        self.has_relevant_elements = False
        self.measure_length = Rational (4, 4)

    def _insert_multibar (self):
        layout_information.set_context_item ('Score', 'skipBars = ##t')
        r = musicexp.MultiMeasureRest ()
        lenfrac = self.measure_length
        r.duration = rational_to_lily_duration (lenfrac)
        r.duration.factor *= self.pending_multibar / lenfrac
        self.elements.append (r)
        self.begin_moment = self.end_moment
        self.end_moment = self.begin_moment + self.pending_multibar
        self.pending_multibar = Rational (0)

    def set_measure_length (self, mlen):
        if (mlen != self.measure_length) and self.pending_multibar:
            self._insert_multibar ()
        self.measure_length = mlen

    def add_multibar_rest (self, duration):
        self.pending_multibar += duration

    def set_duration (self, duration):
        self.end_moment = self.begin_moment + duration
    def current_duration (self):
        return self.end_moment - self.begin_moment

    def add_music (self, music, duration, relevant=True):
        assert isinstance (music, musicexp.Music)
        if self.pending_multibar > Rational (0):
            self._insert_multibar ()

        self.has_relevant_elements = self.has_relevant_elements or relevant
        self.elements.append (music)
        self.begin_moment = self.end_moment
        self.set_duration (duration)

        # Insert all pending dynamics right after the note/rest:
        if isinstance (music, musicexp.ChordEvent) and self.pending_dynamics:
            for d in self.pending_dynamics:
                music.append (d)
            self.pending_dynamics = []

    # Insert some music command that does not affect the position in the measure
    def add_command (self, command, relevant=True):
        assert isinstance (command, musicexp.Music)
        if self.pending_multibar > Rational (0):
            self._insert_multibar ()
        self.has_relevant_elements = self.has_relevant_elements or relevant
        self.elements.append (command)
    def add_barline (self, barline, relevant=False):
        # Insert only if we don't have a barline already
        # TODO: Implement proper merging of default barline and custom bar line
        has_relevant = self.has_relevant_elements
        if (not (self.elements) or
            not (isinstance (self.elements[-1], musicexp.BarLine)) or
            (self.pending_multibar > Rational (0))):
            self.add_music (barline, Rational (0))
        self.has_relevant_elements = has_relevant or relevant
    def add_partial (self, command):
        self.ignore_skips = True
        # insert the partial, but restore relevant_elements (partial is not relevant)
        relevant = self.has_relevant_elements
        self.add_command (command)
        self.has_relevant_elements = relevant

    def add_dynamics (self, dynamic):
        # store the dynamic item(s) until we encounter the next note/rest:
        self.pending_dynamics.append (dynamic)

    def add_bar_check (self, number):
        # re/store has_relevant_elements, so that a barline alone does not
        # trigger output for figured bass, chord names
        b = musicexp.BarLine ()
        b.bar_number = number
        self.add_barline (b)

    def jumpto (self, moment):
        current_end = self.end_moment + self.pending_multibar
        diff = moment - current_end

        if diff < Rational (0):
            ly.warning (_ ('Negative skip %s (from position %s to %s)')
                % (diff, current_end, moment))
            diff = Rational (0)

        if diff > Rational (0) and not (self.ignore_skips and moment == 0):
            skip = musicexp.SkipEvent()
            duration_factor = 1
            duration_log = {1: 0, 2: 1, 4:2, 8:3, 16:4, 32:5, 64:6, 128:7, 256:8, 512:9}.get (diff.denominator (), -1)
            duration_dots = 0
            # TODO: Use the time signature for skips, too. Problem: The skip
            #       might not start at a measure boundary!
            if duration_log > 0: # denominator is a power of 2...
                if diff.numerator () == 3:
                    duration_log -= 1
                    duration_dots = 1
                else:
                    duration_factor = Rational (diff.numerator ())
            else:
                # for skips of a whole or more, simply use s1*factor
                duration_log = 0
                duration_factor = diff
            skip.duration.duration_log = duration_log
            skip.duration.factor = duration_factor
            skip.duration.dots = duration_dots

            evc = musicexp.ChordEvent ()
            evc.elements.append (skip)
            self.add_music (evc, diff, False)

        if diff > Rational (0) and moment == 0:
            self.ignore_skips = False

    def last_event_chord (self, starting_at):

        value = None

        # if the position matches, find the last ChordEvent, do not cross a bar line!
        at = len(self.elements) - 1
        while (at >= 0 and
               not isinstance (self.elements[at], musicexp.ChordEvent) and
               not isinstance (self.elements[at], musicexp.BarLine)):
            at -= 1

        if (self.elements
            and at >= 0
            and isinstance (self.elements[at], musicexp.ChordEvent)
            and self.begin_moment == starting_at):
            value = self.elements[at]
        else:
            self.jumpto (starting_at)
            value = None
        return value

    def correct_negative_skip (self, goto):
        self.end_moment = goto
        self.begin_moment = goto
        evc = musicexp.ChordEvent ()
        self.elements.append (evc)


class VoiceData:
    def __init__ (self):
        self.voicename = None
        self.voicedata = None
        self.ly_voice = None
        self.figured_bass = None
        self.chordnames = None
        self.lyrics_dict = {}
        self.lyrics_order = []

def measure_length_from_attributes (attr, current_measure_length):
    len = attr.get_measure_length ()
    if not len:
        len = current_measure_length
    return len

def musicxml_voice_to_lily_voice (voice):
    tuplet_events = []
    modes_found = {}
    lyrics = {}
    return_value = VoiceData ()
    return_value.voicedata = voice

    # First pitch needed for relative mode (if selected in command-line options)
    first_pitch = None

    # Needed for melismata detection (ignore lyrics on those notes!):
    inside_slur = False
    is_tied = False
    is_chord = False
    is_beamed = False
    ignore_lyrics = False

    current_staff = None

    pending_figured_bass = []
    pending_chordnames = []

    # Make sure that the keys in the dict don't get reordered, since
    # we need the correct ordering of the lyrics stanzas! By default,
    # a dict will reorder its keys
    return_value.lyrics_order = voice.get_lyrics_numbers ()
    for k in return_value.lyrics_order:
        lyrics[k] = []

    voice_builder = LilyPondVoiceBuilder ()
    figured_bass_builder = LilyPondVoiceBuilder ()
    chordnames_builder = LilyPondVoiceBuilder ()
    current_measure_length = Rational (4, 4)
    voice_builder.set_measure_length (current_measure_length)

    for n in voice._elements:
        tie_started = False
        if n.get_name () == 'forward':
            continue
        staff = n.get_maybe_exist_named_child ('staff')
        if staff:
            staff = staff.get_text ()
            if current_staff and staff <> current_staff and not n.get_maybe_exist_named_child ('chord'):
                voice_builder.add_command (musicexp.StaffChange (staff))
            current_staff = staff

        if isinstance (n, musicxml.Partial) and n.partial > 0:
            a = musicxml_partial_to_lily (n.partial)
            if a:
                voice_builder.add_partial (a)
                figured_bass_builder.add_partial (a)
                chordnames_builder.add_partial (a)
            continue

        is_chord = n.get_maybe_exist_named_child ('chord')
        is_after_grace = (isinstance (n, musicxml.Note) and n.is_after_grace ());
        if not is_chord and not is_after_grace:
            try:
                voice_builder.jumpto (n._when)
                figured_bass_builder.jumpto (n._when)
                chordnames_builder.jumpto (n._when)
            except NegativeSkip, neg:
                voice_builder.correct_negative_skip (n._when)
                figured_bass_builder.correct_negative_skip (n._when)
                chordnames_builder.correct_negative_skip (n._when)
                n.message (_ ("Negative skip found: from %s to %s, difference is %s") % (neg.here, neg.dest, neg.dest - neg.here))

        if isinstance (n, musicxml.Barline):
            barlines = musicxml_barline_to_lily (n)
            for a in barlines:
                if isinstance (a, musicexp.BarLine):
                    voice_builder.add_barline (a)
                    figured_bass_builder.add_barline (a, False)
                    chordnames_builder.add_barline (a, False)
                elif isinstance (a, RepeatMarker) or isinstance (a, EndingMarker):
                    voice_builder.add_command (a)
                    figured_bass_builder.add_barline (a, False)
                    chordnames_builder.add_barline (a, False)
            continue


        if isinstance (n, musicxml.Print):
            for a in musicxml_print_to_lily (n):
                voice_builder.add_command (a, False)
            continue

        # Continue any multimeasure-rests before trying to add bar checks!
        # Don't handle new MM rests yet, because for them we want bar checks!
        rest = n.get_maybe_exist_typed_child (musicxml.Rest)
        if (rest and rest.is_whole_measure ()
                 and voice_builder.pending_multibar > Rational (0)):
            voice_builder.add_multibar_rest (n._duration)
            continue


        # print a bar check at the beginning of each measure!
        if n.is_first () and n._measure_position == Rational (0) and n != voice._elements[0]:
            try:
                num = int (n.get_parent ().number)
            except ValueError:
                num = 0
            if num > 0:
                voice_builder.add_bar_check (num)
                figured_bass_builder.add_bar_check (num)
                chordnames_builder.add_bar_check (num)

        # Start any new multimeasure rests
        if (rest and rest.is_whole_measure ()):
            voice_builder.add_multibar_rest (n._duration)
            continue


        if isinstance (n, musicxml.Direction):
            for a in musicxml_direction_to_lily (n):
                if a.wait_for_note ():
                    voice_builder.add_dynamics (a)
                else:
                    voice_builder.add_command (a)
            continue

        if isinstance (n, musicxml.Harmony):
            for a in musicxml_harmony_to_lily (n):
                if a.wait_for_note ():
                    voice_builder.add_dynamics (a)
                else:
                    voice_builder.add_command (a)
            for a in musicxml_harmony_to_lily_chordname (n):
                pending_chordnames.append (a)
            continue

        if isinstance (n, musicxml.FiguredBass):
            a = musicxml_figured_bass_to_lily (n)
            if a:
                pending_figured_bass.append (a)
            continue

        if isinstance (n, musicxml.Attributes):
            for a in musicxml_attributes_to_lily (n):
                voice_builder.add_command (a)
            measure_length = measure_length_from_attributes (n, current_measure_length)
            if current_measure_length != measure_length:
                current_measure_length = measure_length
                voice_builder.set_measure_length (current_measure_length)
            continue

        if not n.__class__.__name__ == 'Note':
            n.message (_ ('unexpected %s; expected %s or %s or %s') % (n, 'Note', 'Attributes', 'Barline'))
            continue

        main_event = musicxml_note_to_lily_main_event (n)
        if main_event and not first_pitch:
            first_pitch = main_event.pitch
        # ignore lyrics for notes inside a slur, tie, chord or beam
        ignore_lyrics = inside_slur or is_tied or is_chord or is_beamed

        if main_event and hasattr (main_event, 'drum_type') and main_event.drum_type:
            modes_found['drummode'] = True

        ev_chord = voice_builder.last_event_chord (n._when)
        if not ev_chord:
            ev_chord = musicexp.ChordEvent()
            voice_builder.add_music (ev_chord, n._duration)

        # For grace notes:
        grace = n.get_maybe_exist_typed_child (musicxml.Grace)
        if n.is_grace ():
            is_after_grace = ev_chord.has_elements () or n.is_after_grace ();
            is_chord = n.get_maybe_exist_typed_child (musicxml.Chord)

            grace_chord = None

            # after-graces and other graces use different lists; Depending on
            # whether we have a chord or not, obtain either a new ChordEvent or
            # the previous one to create a chord
            if is_after_grace:
                if ev_chord.after_grace_elements and n.get_maybe_exist_typed_child (musicxml.Chord):
                    grace_chord = ev_chord.after_grace_elements.get_last_event_chord ()
                if not grace_chord:
                    grace_chord = musicexp.ChordEvent ()
                    ev_chord.append_after_grace (grace_chord)
            elif n.is_grace ():
                if ev_chord.grace_elements and n.get_maybe_exist_typed_child (musicxml.Chord):
                    grace_chord = ev_chord.grace_elements.get_last_event_chord ()
                if not grace_chord:
                    grace_chord = musicexp.ChordEvent ()
                    ev_chord.append_grace (grace_chord)

            if hasattr (grace, 'slash') and not is_after_grace:
                # TODO: use grace_type = "appoggiatura" for slurred grace notes
                if grace.slash == "yes":
                    ev_chord.grace_type = "acciaccatura"
            # now that we have inserted the chord into the grace music, insert
            # everything into that chord instead of the ev_chord
            ev_chord = grace_chord
            ev_chord.append (main_event)
            ignore_lyrics = True
        else:
            ev_chord.append (main_event)
            # When a note/chord has grace notes (duration==0), the duration of the
            # event chord is not yet known, but the event chord was already added
            # with duration 0. The following correct this when we hit the real note!
            if voice_builder.current_duration () == 0 and n._duration > 0:
                voice_builder.set_duration (n._duration)

        # if we have a figured bass, set its voice builder to the correct position
        # and insert the pending figures
        if pending_figured_bass:
            try:
                figured_bass_builder.jumpto (n._when)
            except NegativeSkip, neg:
                pass
            for fb in pending_figured_bass:
                # if a duration is given, use that, otherwise the one of the note
                dur = fb.real_duration
                if not dur:
                    dur = ev_chord.get_length ()
                if not fb.duration:
                    fb.duration = ev_chord.get_duration ()
                figured_bass_builder.add_music (fb, dur)
            pending_figured_bass = []

        if pending_chordnames:
            try:
                chordnames_builder.jumpto (n._when)
            except NegativeSkip, neg:
                pass
            for cn in pending_chordnames:
                # Assign the duration of the EventChord
                cn.duration = ev_chord.get_duration ()
                chordnames_builder.add_music (cn, ev_chord.get_length ())
            pending_chordnames = []

        notations_children = n.get_typed_children (musicxml.Notations)
        tuplet_event = None
        span_events = []

        # The <notation> element can have the following children (+ means implemented, ~ partially, - not):
        # +tied | +slur | +tuplet | glissando | slide |
        #    ornaments | technical | articulations | dynamics |
        #    +fermata | arpeggiate | non-arpeggiate |
        #    accidental-mark | other-notation
        for notations in notations_children:
            for tuplet_event in notations.get_tuplets():
                time_mod = n.get_maybe_exist_typed_child (musicxml.Time_modification)
                tuplet_events.append ((ev_chord, tuplet_event, time_mod))

            # First, close all open slurs, only then start any new slur
            # TODO: Record the number of the open slur to dtermine the correct
            #       closing slur!
            endslurs = [s for s in notations.get_named_children ('slur')
                if s.get_type () in ('stop')]
            if endslurs and not inside_slur:
                endslurs[0].message (_ ('Encountered closing slur, but no slur is open'))
            elif endslurs:
                if len (endslurs) > 1:
                    endslurs[0].message (_ ('Cannot have two simultaneous (closing) slurs'))
                # record the slur status for the next note in the loop
                inside_slur = False
                lily_ev = musicxml_spanner_to_lily_event (endslurs[0])
                ev_chord.append (lily_ev)

            startslurs = [s for s in notations.get_named_children ('slur')
                if s.get_type () in ('start')]
            if startslurs and inside_slur:
                startslurs[0].message (_ ('Cannot have a slur inside another slur'))
            elif startslurs:
                if len (startslurs) > 1:
                    startslurs[0].message (_ ('Cannot have two simultaneous slurs'))
                # record the slur status for the next note in the loop
                inside_slur = True
                lily_ev = musicxml_spanner_to_lily_event (startslurs[0])
                ev_chord.append (lily_ev)


            if not grace:
                mxl_tie = notations.get_tie ()
                if mxl_tie and mxl_tie.type == 'start':
                    ev_chord.append (musicexp.TieEvent ())
                    is_tied = True
                    tie_started = True
                else:
                    is_tied = False

            fermatas = notations.get_named_children ('fermata')
            for a in fermatas:
                ev = musicxml_fermata_to_lily_event (a)
                if ev:
                    ev_chord.append (ev)

            arpeggiate = notations.get_named_children ('arpeggiate')
            for a in arpeggiate:
                ev = musicxml_arpeggiate_to_lily_event (a)
                if ev:
                    ev_chord.append (ev)

            arpeggiate = notations.get_named_children ('non-arpeggiate')
            for a in arpeggiate:
                ev = musicxml_nonarpeggiate_to_lily_event (a)
                if ev:
                    ev_chord.append (ev)

            glissandos = notations.get_named_children ('glissando')
            glissandos += notations.get_named_children ('slide')
            for a in glissandos:
                ev = musicxml_spanner_to_lily_event (a)
                if ev:
                    ev_chord.append (ev)

            # accidental-marks are direct children of <notation>!
            for a in notations.get_named_children ('accidental-mark'):
                ev = musicxml_articulation_to_lily_event (a)
                if ev:
                    ev_chord.append (ev)

            # Articulations can contain the following child elements:
            #         accent | strong-accent | staccato | tenuto |
            #         detached-legato | staccatissimo | spiccato |
            #         scoop | plop | doit | falloff | breath-mark |
            #         caesura | stress | unstress
            # Technical can contain the following child elements:
            #         up-bow | down-bow | harmonic | open-string |
            #         thumb-position | fingering | pluck | double-tongue |
            #         triple-tongue | stopped | snap-pizzicato | fret |
            #         string | hammer-on | pull-off | bend | tap | heel |
            #         toe | fingernails | other-technical
            # Ornaments can contain the following child elements:
            #         trill-mark | turn | delayed-turn | inverted-turn |
            #         shake | wavy-line | mordent | inverted-mordent |
            #         schleifer | tremolo | other-ornament, accidental-mark
            ornaments = notations.get_named_children ('ornaments')
            ornaments += notations.get_named_children ('articulations')
            ornaments += notations.get_named_children ('technical')

            for a in ornaments:
                for ch in a.get_all_children ():
                    ev = musicxml_articulation_to_lily_event (ch)
                    if ev:
                        ev_chord.append (ev)

            dynamics = notations.get_named_children ('dynamics')
            for a in dynamics:
                for ch in a.get_all_children ():
                    ev = musicxml_dynamics_to_lily_event (ch)
                    if ev:
                        ev_chord.append (ev)


        mxl_beams = [b for b in n.get_named_children ('beam')
                     if (b.get_type () in ('begin', 'end')
                         and b.is_primary ())]
        if mxl_beams and not conversion_settings.ignore_beaming:
            beam_ev = musicxml_spanner_to_lily_event (mxl_beams[0])
            if beam_ev:
                ev_chord.append (beam_ev)
                if beam_ev.span_direction == -1: # beam and thus melisma starts here
                    is_beamed = True
                elif beam_ev.span_direction == 1: # beam and thus melisma ends here
                    is_beamed = False

        # Extract the lyrics
        if not rest and not ignore_lyrics:
            note_lyrics_processed = []
            note_lyrics_elements = n.get_typed_children (musicxml.Lyric)
            for l in note_lyrics_elements:
                if l.get_number () < 0:
                    for k in lyrics.keys ():
                        lyrics[k].append (musicxml_lyrics_to_text (l))
                        note_lyrics_processed.append (k)
                else:
                    lyrics[l.number].append(musicxml_lyrics_to_text (l))
                    note_lyrics_processed.append (l.number)
            for lnr in lyrics.keys ():
                if not lnr in note_lyrics_processed:
                    lyrics[lnr].append ("\skip4")

        # Assume that a <tie> element only lasts for one note.
        # This might not be correct MusicXML interpretation, but works for
        # most cases and fixes broken files, which have the end tag missing
        if is_tied and not tie_started:
            is_tied = False

    ## force trailing mm rests to be written out.
    voice_builder.add_music (musicexp.ChordEvent (), Rational (0))

    ly_voice = group_tuplets (voice_builder.elements, tuplet_events)
    ly_voice = group_repeats (ly_voice)

    seq_music = musicexp.SequentialMusic ()

    if 'drummode' in modes_found.keys ():
        ## \key <pitch> barfs in drummode.
        ly_voice = [e for e in ly_voice
                    if not isinstance(e, musicexp.KeySignatureChange)]

    seq_music.elements = ly_voice
    for k in lyrics.keys ():
        return_value.lyrics_dict[k] = musicexp.Lyrics ()
        return_value.lyrics_dict[k].lyrics_syllables = lyrics[k]


    if len (modes_found) > 1:
       ly.warning (_ ('cannot simultaneously have more than one mode: %s') % modes_found.keys ())

    if options.relative:
        v = musicexp.RelativeMusic ()
        v.element = seq_music
        v.basepitch = first_pitch
        seq_music = v

    return_value.ly_voice = seq_music
    for mode in modes_found.keys ():
        v = musicexp.ModeChangingMusicWrapper()
        v.element = seq_music
        v.mode = mode
        return_value.ly_voice = v

    # create \figuremode { figured bass elements }
    if figured_bass_builder.has_relevant_elements:
        fbass_music = musicexp.SequentialMusic ()
        fbass_music.elements = group_repeats (figured_bass_builder.elements)
        v = musicexp.ModeChangingMusicWrapper()
        v.mode = 'figuremode'
        v.element = fbass_music
        return_value.figured_bass = v

    # create \chordmode { chords }
    if chordnames_builder.has_relevant_elements:
        cname_music = musicexp.SequentialMusic ()
        cname_music.elements = group_repeats (chordnames_builder.elements)
        v = musicexp.ModeChangingMusicWrapper()
        v.mode = 'chordmode'
        v.element = cname_music
        return_value.chordnames = v

    return return_value

def musicxml_id_to_lily (id):
    digits = ['Zero', 'One', 'Two', 'Three', 'Four', 'Five',
              'Six', 'Seven', 'Eight', 'Nine', 'Ten']

    for digit in digits:
        d = digits.index (digit)
        id = re.sub ('%d' % d, digit, id)

    id = re.sub  ('[^a-zA-Z]', 'X', id)
    return id

def musicxml_pitch_to_lily (mxl_pitch):
    p = musicexp.Pitch ()
    p.alteration = mxl_pitch.get_alteration ()
    p.step = musicxml_step_to_lily (mxl_pitch.get_step ())
    p.octave = mxl_pitch.get_octave () - 4
    return p

def musicxml_unpitched_to_lily (mxl_unpitched):
    p = None
    step = mxl_unpitched.get_step ()
    if step:
        p = musicexp.Pitch ()
        p.step = musicxml_step_to_lily (step)
    octave = mxl_unpitched.get_octave ()
    if octave and p:
        p.octave = octave - 4
    return p

def musicxml_restdisplay_to_lily (mxl_rest):
    p = None
    step = mxl_rest.get_step ()
    if step:
        p = musicexp.Pitch ()
        p.step = musicxml_step_to_lily (step)
    octave = mxl_rest.get_octave ()
    if octave and p:
        p.octave = octave - 4
    return p

def voices_in_part (part):
    """Return a Name -> Voice dictionary for PART"""
    part.interpret ()
    part.extract_voices ()
    voices = part.get_voices ()
    part_info = part.get_staff_attributes ()

    return (voices, part_info)

def voices_in_part_in_parts (parts):
    """return a Part -> Name -> Voice dictionary"""
    # don't crash if p doesn't have an id (that's invalid MusicXML,
    # but such files are out in the wild!
    dictionary = {}
    for p in parts:
        voices = voices_in_part (p)
        if (hasattr (p, "id")):
             dictionary[p.id] = voices
        else:
             # TODO: extract correct part id from other sources
             dictionary[None] = voices
    return dictionary;


def get_all_voices (parts):
    all_voices = voices_in_part_in_parts (parts)

    all_ly_voices = {}
    all_ly_staffinfo = {}
    for p, (name_voice, staff_info) in all_voices.items ():

        part_ly_voices = {}
        for n, v in name_voice.items ():
            ly.progress (_ ("Converting to LilyPond expressions..."), True)
            # musicxml_voice_to_lily_voice returns (lily_voice, {nr->lyrics, nr->lyrics})
            part_ly_voices[n] = musicxml_voice_to_lily_voice (v)

        all_ly_voices[p] = part_ly_voices
        all_ly_staffinfo[p] = staff_info

    return (all_ly_voices, all_ly_staffinfo)


def option_parser ():
    p = ly.get_option_parser (usage = _ ("musicxml2ly [OPTION]... FILE.xml"),
                             description =
_ ("""Convert MusicXML from FILE.xml to LilyPond input.
If the given filename is -, musicxml2ly reads from the command line.
"""), add_help_option=False)

    p.add_option("-h", "--help",
                 action="help",
                 help=_ ("show this help and exit"))

    p.version = ('''%prog (LilyPond) 2.18.2\n\n'''
+
_ ("""Copyright (c) 2005--2012 by
    Han-Wen Nienhuys <hanwen@xs4all.nl>,
    Jan Nieuwenhuizen <janneke@gnu.org> and
    Reinhold Kainhofer <reinhold@kainhofer.com>
"""
+
"""
This program is free software.  It is covered by the GNU General Public
License and you are welcome to change it and/or distribute copies of it
under certain conditions.  Invoke as `%s --warranty' for more
information.""") % 'lilypond')

    p.add_option("--version",
                 action="version",
                 help=_ ("show version number and exit"))

    p.add_option ('-v', '--verbose',
                  action="callback",
                  callback=ly.handle_loglevel_option,
                  callback_args=("DEBUG",),
                  help = _ ("be verbose"))

    p.add_option ('', '--lxml',
                  action = "store_true",
                  default = False,
                  dest = "use_lxml",
                  help = _ ("use lxml.etree; uses less memory and cpu time"))

    p.add_option ('-z', '--compressed',
                  action = "store_true",
                  dest = 'compressed',
                  default = False,
                  help = _ ("input file is a zip-compressed MusicXML file"))

    p.add_option ('-r', '--relative',
                  action = "store_true",
                  default = True,
                  dest = "relative",
                  help = _ ("convert pitches in relative mode (default)"))

    p.add_option ('-a', '--absolute',
                  action = "store_false",
                  dest = "relative",
                  help = _ ("convert pitches in absolute mode"))

    p.add_option ('-l', '--language',
                  metavar = _ ("LANG"),
                  action = "store",
                  help = _ ("use LANG for pitch names, e.g. 'deutsch' for note names in German"))

    p.add_option ("--loglevel",
                  help=_ ("Print log messages according to LOGLEVEL "
                          "(NONE, ERROR, WARNING, PROGRESS (default), DEBUG)"),
                  metavar=_ ("LOGLEVEL"),
                  action='callback',
                  callback=ly.handle_loglevel_option,
                  type='string')

    p.add_option ('--nd', '--no-articulation-directions',
                  action = "store_false",
                  default = True,
                  dest = "convert_directions",
                  help = _ ("do not convert directions (^, _ or -) for articulations, dynamics, etc."))

    p.add_option ('--nrp', '--no-rest-positions',
                  action = "store_false",
                  default = True,
                  dest = "convert_rest_positions",
                  help = _ ("do not convert exact vertical positions of rests"))

    p.add_option ('--npl', '--no-page-layout',
                  action = "store_false",
                  default = True,
                  dest = "convert_page_layout",
                  help = _ ("do not convert the exact page layout and breaks"))

    p.add_option ('--no-beaming',
                  action = "store_false",
                  default = True,
                  dest = "convert_beaming",
                  help = _ ("do not convert beaming information, use lilypond's automatic beaming instead"))

    p.add_option ('-o', '--output',
                  metavar = _ ("FILE"),
                  action = "store",
                  default = None,
                  type = 'string',
                  dest = 'output_name',
                  help = _ ("set output filename to FILE, stdout if -"))

    p.add_option ('-m', '--midi',
                  action = "store_true",
                  default = False,
                  dest = "midi",
                  help = _("activate midi-block"))

    p.add_option_group ('',
                        description = (
            _ ("Report bugs via %s")
            % 'http://post.gmane.org/post.php'
            '?group=gmane.comp.gnu.lilypond.bugs') + '\n')
    return p

def music_xml_voice_name_to_lily_name (part_id, name):
    str = "Part%sVoice%s" % (part_id, name)
    return musicxml_id_to_lily (str)

def music_xml_lyrics_name_to_lily_name (part_id, name, lyricsnr):
    str = "Part%sVoice%sLyrics%s" % (part_id, name, lyricsnr)
    return musicxml_id_to_lily (str)

def music_xml_figuredbass_name_to_lily_name (part_id, voicename):
    str = "Part%sVoice%sFiguredBass" % (part_id, voicename)
    return musicxml_id_to_lily (str)

def music_xml_chordnames_name_to_lily_name (part_id, voicename):
    str = "Part%sVoice%sChords" % (part_id, voicename)
    return musicxml_id_to_lily (str)

def print_voice_definitions (printer, part_list, voices):
    for part in part_list:
        part_id = part.id
        nv_dict = voices.get (part_id, {})
        for (name, voice) in nv_dict.items ():
            k = music_xml_voice_name_to_lily_name (part_id, name)
            printer.dump ('%s = ' % k)
            voice.ly_voice.print_ly (printer)
            printer.newline()
            if voice.chordnames:
                cnname = music_xml_chordnames_name_to_lily_name (part_id, name)
                printer.dump ('%s = ' % cnname )
                voice.chordnames.print_ly (printer)
                printer.newline()
            for l in voice.lyrics_order:
                lname = music_xml_lyrics_name_to_lily_name (part_id, name, l)
                printer.dump ('%s = ' % lname )
                voice.lyrics_dict[l].print_ly (printer)
                printer.newline()
            if voice.figured_bass:
                fbname = music_xml_figuredbass_name_to_lily_name (part_id, name)
                printer.dump ('%s = ' % fbname )
                voice.figured_bass.print_ly (printer)
                printer.newline()


def uniq_list (l):
    return dict ([(elt, 1) for elt in l]).keys ()

# format the information about the staff in the form
#     [staffid,
#         [
#            [voiceid1, [lyricsid11, lyricsid12,...], figuredbassid1],
#            [voiceid2, [lyricsid21, lyricsid22,...], figuredbassid2],
#            ...
#         ]
#     ]
# raw_voices is of the form [(voicename, lyricsids, havefiguredbass)*]
def format_staff_info (part_id, staff_id, raw_voices):
    voices = []
    for (v, lyricsids, figured_bass, chordnames) in raw_voices:
        voice_name = music_xml_voice_name_to_lily_name (part_id, v)
        voice_lyrics = [music_xml_lyrics_name_to_lily_name (part_id, v, l)
                   for l in lyricsids]
        figured_bass_name = ''
        if figured_bass:
            figured_bass_name = music_xml_figuredbass_name_to_lily_name (part_id, v)
        chordnames_name = ''
        if chordnames:
            chordnames_name = music_xml_chordnames_name_to_lily_name (part_id, v)
        voices.append ([voice_name, voice_lyrics, figured_bass_name, chordnames_name])
    return [staff_id, voices]

def update_score_setup (score_structure, part_list, voices):

    for part_definition in part_list:
        part_id = part_definition.id
        nv_dict = voices.get (part_id)
        if not nv_dict:
            ly.warning (_ ('unknown part in part-list: %s') % part_id)
            continue

        staves = reduce (lambda x,y: x+ y,
                [voice.voicedata._staves.keys ()
                 for voice in nv_dict.values ()],
                [])
        staves_info = []
        if len (staves) > 1:
            staves_info = []
            staves = uniq_list (staves)
            staves.sort ()
            for s in staves:
                thisstaff_raw_voices = [(voice_name, voice.lyrics_order, voice.figured_bass, voice.chordnames)
                    for (voice_name, voice) in nv_dict.items ()
                    if voice.voicedata._start_staff == s]
                staves_info.append (format_staff_info (part_id, s, thisstaff_raw_voices))
        else:
            thisstaff_raw_voices = [(voice_name, voice.lyrics_order, voice.figured_bass, voice.chordnames)
                for (voice_name, voice) in nv_dict.items ()]
            staves_info.append (format_staff_info (part_id, None, thisstaff_raw_voices))
        score_structure.set_part_information (part_id, staves_info)

# Set global values in the \layout block, like auto-beaming etc.
def update_layout_information ():
    if not conversion_settings.ignore_beaming and layout_information:
        layout_information.set_context_item ('Score', 'autoBeaming = ##f')

def print_ly_preamble (printer, filename):
    printer.dump_version ()
    printer.print_verbatim ('%% automatically converted by musicxml2ly from %s\n' % filename)

def print_ly_additional_definitions (printer, filename):
    if needed_additional_definitions:
        printer.newline ()
        printer.print_verbatim ('%% additional definitions required by the score:')
        printer.newline ()
    for a in set(needed_additional_definitions):
        printer.print_verbatim (additional_definitions.get (a, ''))
        printer.newline ()
    printer.newline ()

# Read in the tree from the given I/O object (either file or string) and
# demarshall it using the classes from the musicxml.py file
def read_xml (io_object, use_lxml):
    if use_lxml:
        import lxml.etree
        tree = lxml.etree.parse (io_object)
        mxl_tree = musicxml.lxml_demarshal_node (tree.getroot ())
        return mxl_tree
    else:
        from xml.dom import minidom, Node
        doc = minidom.parse(io_object)
        node = doc.documentElement
        return musicxml.minidom_demarshal_node (node)
    return None


def read_musicxml (filename, compressed, use_lxml):
    raw_string = None
    if compressed:
        if filename == "-":
             ly.progress (_ ("Input is compressed, extracting raw MusicXML data from stdin"), True)
             # unfortunately, zipfile.ZipFile can't read directly from
             # stdin, so copy everything from stdin to a temp file and read
             # that. TemporaryFile() will remove the file when it is closed.
             tmp = tempfile.TemporaryFile()
             sys.stdin = os.fdopen(sys.stdin.fileno(), 'rb', 0) # Make sys.stdin binary
             bytes_read = sys.stdin.read (8192)
             while bytes_read:
                 for b in bytes_read:
                     tmp.write(b)
                 bytes_read = sys.stdin.read (8192)
             z = zipfile.ZipFile (tmp, "r")
        else:
            ly.progress (_ ("Input file %s is compressed, extracting raw MusicXML data") % filename, True)
            z = zipfile.ZipFile (filename, "r")
        container_xml = z.read ("META-INF/container.xml")
        if not container_xml:
            return None
        container = read_xml (StringIO.StringIO (container_xml), use_lxml)
        if not container:
            return None
        rootfiles = container.get_maybe_exist_named_child ('rootfiles')
        if not rootfiles:
            return None
        rootfile_list = rootfiles.get_named_children ('rootfile')
        mxml_file = None
        if len (rootfile_list) > 0:
            mxml_file = getattr (rootfile_list[0], 'full-path', None)
        if mxml_file:
            raw_string = z.read (mxml_file)

    if raw_string:
        io_object = StringIO.StringIO (raw_string)
    elif filename == "-":
        io_object = sys.stdin
    else:
        io_object = filename

    return read_xml (io_object, use_lxml)


def convert (filename, options):
    if filename == "-":
        ly.progress (_ ("Reading MusicXML from Standard input ..."), True)
    else:
        ly.progress (_ ("Reading MusicXML from %s ...") % filename, True)

    tree = read_musicxml (filename, options.compressed, options.use_lxml)
    score_information = extract_score_information (tree)
    paper_information = extract_paper_information (tree)

    parts = tree.get_typed_children (musicxml.Part)
    (voices, staff_info) = get_all_voices (parts)

    score = None
    mxl_pl = tree.get_maybe_exist_typed_child (musicxml.Part_list)
    if mxl_pl:
        score = extract_score_structure (mxl_pl, staff_info)
        part_list = mxl_pl.get_named_children ("score-part")

    # score information is contained in the <work>, <identification> or <movement-title> tags
    update_score_setup (score, part_list, voices)
    # After the conversion, update the list of settings for the \layout block
    update_layout_information ()

    if not options.output_name:
        options.output_name = os.path.basename (filename)
        options.output_name = os.path.splitext (options.output_name)[0]
    elif re.match (".*\.ly", options.output_name):
        options.output_name = os.path.splitext (options.output_name)[0]


    #defs_ly_name = options.output_name + '-defs.ly'
    if (options.output_name == "-"):
      output_ly_name = 'Standard output'
    else:
      output_ly_name = options.output_name + '.ly'

    ly.progress (_ ("Output to `%s'") % output_ly_name, True)
    printer = musicexp.Output_printer()
    #ly.progress (_ ("Output to `%s'") % defs_ly_name, True)
    if (options.output_name == "-"):
      printer.set_file (codecs.getwriter ("utf-8")(sys.stdout))
    else:
      printer.set_file (codecs.open (output_ly_name, 'wb', encoding='utf-8'))
    print_ly_preamble (printer, filename)
    print_ly_additional_definitions (printer, filename)
    if score_information:
        score_information.print_ly (printer)
    if paper_information and conversion_settings.convert_page_layout:
        paper_information.print_ly (printer)
    if layout_information:
        layout_information.print_ly (printer)
    print_voice_definitions (printer, part_list, voices)

    printer.newline ()
    printer.dump ("% The score definition")
    printer.newline ()
    score.print_ly (printer)
    printer.newline ()

    return voices

def get_existing_filename_with_extension (filename, ext):
    if os.path.exists (filename):
        return filename
    newfilename = filename + "." + ext
    if os.path.exists (newfilename):
        return newfilename;
    newfilename = filename + ext
    if os.path.exists (newfilename):
        return newfilename;
    return ''

def main ():
    opt_parser = option_parser()

    global options
    (options, args) = opt_parser.parse_args ()
    if not args:
        opt_parser.print_usage()
        sys.exit (2)

    if options.midi:
        musicexp.set_create_midi (options.midi)

    if options.language:
        musicexp.set_pitch_language (options.language)
        needed_additional_definitions.append (options.language)
        additional_definitions[options.language] = "\\language \"%s\"\n" % options.language
    conversion_settings.ignore_beaming = not options.convert_beaming
    conversion_settings.convert_page_layout = options.convert_page_layout

    # Allow the user to leave out the .xml or xml on the filename
    basefilename = args[0].decode('utf-8')
    if basefilename == "-": # Read from stdin
        filename = "-"
    else:
        filename = get_existing_filename_with_extension (basefilename, "xml")
        if not filename:
            filename = get_existing_filename_with_extension (basefilename, "mxl")
            options.compressed = True
    if filename and filename.endswith ("mxl"):
        options.compressed = True

    if filename and (filename == "-" or os.path.exists (filename)):
        voices = convert (filename, options)
    else:
        ly.error (_ ("Unable to find input file %s") % basefilename)

if __name__ == '__main__':
    main()
