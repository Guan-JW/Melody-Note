# -*- coding: utf-8 -*-
import inspect
import sys
import string
import re
import lilylib as ly

_ = ly._

from rational import Rational

# Store previously converted pitch for \relative conversion as a global state variable
previous_pitch = None
relative_pitches = False


def escape_instrument_string (input_string):
    retstring = string.replace (input_string, "\"", "\\\"")
    if re.match ('.*[\r\n]+.*', retstring):
        rx = re.compile (r'[\n\r]+')
        strings = rx.split (retstring)
        retstring = "\\markup { \\center-column { "
        for s in strings:
            retstring += "\\line {\"" + s + "\"} "
        retstring += "} }"
    else:
        retstring = "\"" + retstring + "\""
    return retstring

class Output_stack_element:
    def __init__ (self):
        self.factor = Rational (1)
    def copy (self):
        o = Output_stack_element()
        o.factor = self.factor
        return o

class Output_printer:

    """A class that takes care of formatting (eg.: indenting) a
    Music expression as a .ly file.

    """

    def __init__ (self):
        self._line = ''
        self._indent = 4
        self._nesting = 0
        self._file = sys.stdout
        self._line_len = 72
        self._output_state_stack = [Output_stack_element()]
        self._skipspace = False
        self._last_duration = None

    def set_file (self, file):
        self._file = file

    def dump_version (self):
        self.newline ()
        self.print_verbatim ('\\version "2.18.2"')
        self.newline ()

    def get_indent (self):
        return self._nesting * self._indent

    def override (self):
        last = self._output_state_stack[-1]
        self._output_state_stack.append (last.copy())

    def add_factor (self, factor):
        self.override()
        self._output_state_stack[-1].factor *=  factor

    def revert (self):
        del self._output_state_stack[-1]
        if not self._output_state_stack:
            raise 'empty'

    def duration_factor (self):
        return self._output_state_stack[-1].factor

    def print_verbatim (self, str):
        self._line += str

    def unformatted_output (self, str):
        # don't indent on \< and indent only once on <<
        self._nesting += ( str.count ('<')
                         - str.count ('\<') - str.count ('<<')
                         + str.count ('{') )
        self._nesting -= ( str.count ('>') - str.count ('\>') - str.count ('>>')
                                           - str.count ('->') - str.count ('_>')
                                           - str.count ('^>')
                         + str.count ('}') )
        self.print_verbatim (str)

    def print_duration_string (self, str):
        if self._last_duration == str:
            return

        self.unformatted_output (str)

    def add_word (self, str):
        if (len (str) + 1 + len (self._line) > self._line_len):
            self.newline()
            self._skipspace = True

        if not self._skipspace:
            self._line += ' '
        self.unformatted_output (str)
        self._skipspace = False

    def newline (self):
        self._file.write (self._line + '\n')
        self._line = ' ' * self._indent * self._nesting
        self._skipspace = True

    def skipspace (self):
        self._skipspace = True

    def __call__(self, arg):
        self.dump (arg)

    def dump (self, str):
        if self._skipspace:
            self._skipspace = False
            self.unformatted_output (str)
        else:
            words = string.split (str)
            for w in words:
                self.add_word (w)


    def close (self):
        self.newline ()
        self._file.close ()
        self._file = None


class Duration:
    def __init__ (self):
        self.duration_log = 0
        self.dots = 0
        self.factor = Rational (1)

    def lisp_expression (self):
        return '(ly:make-duration %d %d %d %d)' % (self.duration_log,
                             self.dots,
                             self.factor.numerator (),
                             self.factor.denominator ())


    def ly_expression (self, factor = None, scheme_mode = False):
        if not factor:
            factor = self.factor

        if self.duration_log < 0:
            if scheme_mode:
                longer_dict = {-1: "breve", -2: "longa"}
            else:
                longer_dict = {-1: "\\breve", -2: "\\longa"}
            str = longer_dict.get (self.duration_log, "1")
        else:
            str = '%d' % (1 << self.duration_log)
        str += '.'*self.dots

        if factor <> Rational (1,1):
            if factor.denominator () <> 1:
                str += '*%d/%d' % (factor.numerator (), factor.denominator ())
            else:
                str += '*%d' % factor.numerator ()

        return str

    def print_ly (self, outputter):
        str = self.ly_expression (self.factor / outputter.duration_factor ())
        outputter.print_duration_string (str)

    def __repr__(self):
        return self.ly_expression()

    def copy (self):
        d = Duration ()
        d.dots = self.dots
        d.duration_log = self.duration_log
        d.factor = self.factor
        return d

    def get_length (self):
        dot_fact = Rational( (1 << (1 + self.dots))-1,
                             1 << self.dots)

        log = abs (self.duration_log)
        dur = 1 << log
        if self.duration_log < 0:
            base = Rational (dur)
        else:
            base = Rational (1, dur)

        return base * dot_fact * self.factor

# implement the midi command line option '-m' and '--midi'
# if TRUE add midi-block to .ly file (see below)
def set_create_midi (option):
    global midi_option
    midi_option = option

def get_create_midi ():
    try:
        return midi_option
    except:
        return False

# Implement the different note names for the various languages
def pitch_generic (pitch, notenames, accidentals):
    str = notenames[pitch.step]
    halftones = int (pitch.alteration)
    if halftones < 0:
        str += accidentals[0] * (-halftones)
    elif pitch.alteration > 0:
        str += accidentals[3] * (halftones)
    # Handle remaining fraction to pitch.alteration (for microtones)
    if (halftones != pitch.alteration):
        if None in accidentals[1:3]:
            ly.warning (_ ("Language does not support microtones contained in the piece"))
        else:
            try:
                str += {-0.5: accidentals[1], 0.5: accidentals[2]}[pitch.alteration-halftones]
            except KeyError:
                ly.warning (_ ("Language does not support microtones contained in the piece"))
    return str

def pitch_general (pitch):
    str = pitch_generic (pitch, ['c', 'd', 'e', 'f', 'g', 'a', 'b'], ['es', 'eh', 'ih', 'is'])
    return str.replace ('aes', 'as').replace ('ees', 'es')

def pitch_nederlands (pitch):
    return pitch_general (pitch)

def pitch_english (pitch):
    str = pitch_generic (pitch, ['c', 'd', 'e', 'f', 'g', 'a', 'b'], ['f', 'qf', 'qs', 's'])
    return str.replace ('aes', 'as').replace ('ees', 'es')

def pitch_deutsch (pitch):
    str = pitch_generic (pitch, ['c', 'd', 'e', 'f', 'g', 'a', 'h'], ['es', 'eh', 'ih', 'is'])
    return str.replace ('hes', 'b').replace ('aes', 'as').replace ('ees', 'es')

def pitch_norsk (pitch):
    return pitch_deutsch (pitch)

def pitch_svenska (pitch):
    str = pitch_generic (pitch, ['c', 'd', 'e', 'f', 'g', 'a', 'h'], ['ess', None, None, 'iss'])
    return str.replace ('hess', 'b').replace ('aes', 'as').replace ('ees', 'es')

def pitch_italiano (pitch):
    str = pitch_generic (pitch, ['do', 're', 'mi', 'fa', 'sol', 'la', 'si'], ['b', 'sb', 'sd', 'd'])
    return str

def pitch_catalan (pitch):
    return pitch_italiano (pitch)

def pitch_espanol (pitch):
    str = pitch_generic (pitch, ['do', 're', 'mi', 'fa', 'sol', 'la', 'si'], ['b', None, None, 's'])
    return str

def pitch_vlaams (pitch):
    str = pitch_generic (pitch, ['do', 're', 'mi', 'fa', 'sol', 'la', 'si'], ['b', None, None, 'k'])
    return str

def set_pitch_language (language):
    global pitch_generating_function
    function_dict = {
        "nederlands": pitch_nederlands,
        "english": pitch_english,
        "deutsch": pitch_deutsch,
        "norsk": pitch_norsk,
        "svenska": pitch_svenska,
        "italiano": pitch_italiano,
        "catalan": pitch_catalan,
        "espanol": pitch_espanol,
        "vlaams": pitch_vlaams}
    pitch_generating_function = function_dict.get (language, pitch_general)

# global variable to hold the formatting function.
pitch_generating_function = pitch_general


class Pitch:
    def __init__ (self):
        self.alteration = 0
        self.step = 0
        self.octave = 0
        self._force_absolute_pitch = False

    def __repr__(self):
        return self.ly_expression()

    def transposed (self, interval):
        c = self.copy ()
        c.alteration  += interval.alteration
        c.step += interval.step
        c.octave += interval.octave
        c.normalize ()

        target_st = self.semitones()  + interval.semitones()
        c.alteration += target_st - c.semitones()
        return c

    def normalize (c):
        while c.step < 0:
            c.step += 7
            c.octave -= 1
        c.octave += c.step / 7
        c.step = c.step  % 7

    def lisp_expression (self):
        return '(ly:make-pitch %d %d %d)' % (self.octave,
                                             self.step,
                                             self.alteration)

    def copy (self):
        p = Pitch ()
        p.alteration = self.alteration
        p.step = self.step
        p.octave = self.octave
        return p

    def steps (self):
        return self.step + self.octave *7

    def semitones (self):
        return self.octave * 12 + [0,2,4,5,7,9,11][self.step] + self.alteration

    def ly_step_expression (self):
        return pitch_generating_function (self)

    def absolute_pitch (self):
        if self.octave >= 0:
            return "'" * (self.octave + 1)
        elif self.octave < -1:
            return "," * (-self.octave - 1)
        else:
            return ''

    def relative_pitch (self):
        global previous_pitch
        if not previous_pitch:
            previous_pitch = self
            return self.absolute_pitch ()
        previous_pitch_steps = previous_pitch.octave * 7 + previous_pitch.step
        this_pitch_steps = self.octave * 7 + self.step
        pitch_diff = (this_pitch_steps - previous_pitch_steps)
        previous_pitch = self
        if pitch_diff > 3:
            return "'" * ((pitch_diff + 3) / 7)
        elif pitch_diff < -3:
            return "," * ((-pitch_diff + 3) / 7)
        else:
            return ""

    def ly_expression (self):
        str = self.ly_step_expression ()
        if relative_pitches and not self._force_absolute_pitch:
            str += self.relative_pitch ()
        else:
            str += self.absolute_pitch ()

        return str

    def print_ly (self, outputter):
        outputter (self.ly_expression())

class Music:
    def __init__ (self):
        self.parent = None
        self.start = Rational (0)
        self.comment = ''
        self.identifier = None

    def get_length(self):
        return Rational (0)

    def get_properties (self):
        return ''

    def has_children (self):
        return False

    def get_index (self):
        if self.parent:
            return self.parent.elements.index (self)
        else:
            return None
    def name (self):
        return self.__class__.__name__

    def lisp_expression (self):
        name = self.name()

        props = self.get_properties ()

        return "(make-music '%s %s)" % (name,  props)

    def set_start (self, start):
        self.start = start

    def find_first (self, predicate):
        if predicate (self):
            return self
        return None

    def print_comment (self, printer, text = None):
        if not text:
            text = self.comment

        if not text:
            return

        if text == '\n':
            printer.newline ()
            return

        lines = string.split (text, '\n')
        for l in lines:
            if l:
                printer.unformatted_output ('% ' + l)
            printer.newline ()


    def print_with_identifier (self, printer):
        if self.identifier:
            printer ("\\%s" % self.identifier)
        else:
            self.print_ly (printer)

    def print_ly (self, printer):
        printer (self.ly_expression ())

class MusicWrapper (Music):
    def __init__ (self):
        Music.__init__(self)
        self.element = None
    def print_ly (self, func):
        self.element.print_ly (func)

class ModeChangingMusicWrapper (MusicWrapper):
    def __init__ (self):
        MusicWrapper.__init__ (self)
        self.mode = 'notemode'

    def print_ly (self, func):
        func ('\\%s' % self.mode)
        MusicWrapper.print_ly (self, func)

class RelativeMusic (MusicWrapper):
    def __init__ (self):
        MusicWrapper.__init__ (self)
        self.basepitch = None

    def print_ly (self, func):
        global previous_pitch
        global relative_pitches
        prev_relative_pitches = relative_pitches
        relative_pitches = True
        previous_pitch = self.basepitch
        if not previous_pitch:
            previous_pitch = Pitch ()
        func ('\\relative %s%s' % (pitch_generating_function (previous_pitch),
                                   previous_pitch.absolute_pitch ()))
        MusicWrapper.print_ly (self, func)
        relative_pitches = prev_relative_pitches

class TimeScaledMusic (MusicWrapper):
    def __init__ (self):
        MusicWrapper.__init__ (self)
        self.numerator = 1
        self.denominator = 1
        self.display_number = "actual" # valid values "actual" | "both" | None
        # Display the basic note length for the tuplet:
        self.display_type = None       # value values "actual" | "both" | None
        self.display_bracket = "bracket" # valid values "bracket" | "curved" | None
        self.actual_type = None   # The actually played unit of the scaling
        self.normal_type = None   # The basic unit of the scaling
        self.display_numerator = None
        self.display_denominator = None

    def print_ly (self, func):
        if self.display_bracket == None:
            func ("\\once \\override TupletBracket #'stencil = ##f")
            func.newline ()
        elif self.display_bracket == "curved":
            ly.warning (_ ("Tuplet brackets of curved shape are not correctly implemented"))
            func ("\\once \\override TupletBracket #'stencil = #ly:slur::print")
            func.newline ()

        base_number_function = {None: "#f",
             "actual": "tuplet-number::calc-denominator-text",
             "both": "tuplet-number::calc-fraction-text"}.get (self.display_number, None)
        # If we have non-standard numerator/denominator, use our custom function
        if self.display_number == "actual" and self.display_denominator:
            base_number_function = "(tuplet-number::non-default-tuplet-denominator-text %s)" % self.display_denominator
        elif self.display_number == "both" and (self.display_denominator or self.display_numerator):
            if self.display_numerator:
                num = self.display_numerator
            else:
                num = "#f"
            if self.display_denominator:
                den = self.display_denominator
            else:
                den = "#f"
            base_number_function = "(tuplet-number::non-default-tuplet-fraction-text %s %s)" % (den, num)


        if self.display_type == "actual" and self.normal_type:
            # Obtain the note duration in scheme-mode, i.e. \longa as \\longa
            base_duration = self.normal_type.ly_expression (None, True)
            func ("\\once \\override TupletNumber #'text = #(tuplet-number::append-note-wrapper %s \"%s\")" %
                (base_number_function, base_duration))
            func.newline ()
        elif self.display_type == "both": # TODO: Implement this using actual_type and normal_type!
            if self.display_number == None:
                func ("\\once \\override TupletNumber #'stencil = ##f")
                func.newline ()
            elif self.display_number == "both":
                den_duration = self.normal_type.ly_expression (None, True)
                # If we don't have an actual type set, use the normal duration!
                if self.actual_type:
                    num_duration = self.actual_type.ly_expression (None, True)
                else:
                    num_duration = den_duration
                if (self.display_denominator or self.display_numerator):
                    func ("\\once \\override TupletNumber #'text = #(tuplet-number::non-default-fraction-with-notes %s \"%s\" %s \"%s\")" %
                                (self.display_denominator, den_duration,
                                 self.display_numerator, num_duration))
                    func.newline ()
                else:
                    func ("\\once \\override TupletNumber #'text = #(tuplet-number::fraction-with-notes \"%s\" \"%s\")" %
                                (den_duration, num_duration))
                    func.newline ()
        else:
            if self.display_number == None:
                func ("\\once \\override TupletNumber #'stencil = ##f")
                func.newline ()
            elif self.display_number == "both":
                func ("\\once \\override TupletNumber #'text = #%s" % base_number_function)
                func.newline ()

        func ('\\times %d/%d ' %
           (self.numerator, self.denominator))
        func.add_factor (Rational (self.numerator, self.denominator))
        MusicWrapper.print_ly (self, func)
        func.revert ()

class NestedMusic(Music):
    def __init__ (self):
        Music.__init__ (self)
        self.elements = []

    def append (self, what):
        if what:
            self.elements.append (what)

    def has_children (self):
        return self.elements

    def insert_around (self, succ, elt, dir):
        assert elt.parent == None
        assert succ == None or succ in self.elements


        idx = 0
        if succ:
            idx = self.elements.index (succ)
            if dir > 0:
                idx += 1
        else:
            if dir < 0:
                idx = 0
            elif dir > 0:
                idx = len (self.elements)

        self.elements.insert (idx, elt)
        elt.parent = self

    def get_properties (self):
        return ("'elements (list %s)"
            % string.join (map (lambda x: x.lisp_expression(),
                      self.elements)))

    def get_subset_properties (self, predicate):
        return ("'elements (list %s)"
            % string.join (map (lambda x: x.lisp_expression(),
                      filter ( predicate,  self.elements))))
    def get_neighbor (self, music, dir):
        assert music.parent == self
        idx = self.elements.index (music)
        idx += dir
        idx = min (idx, len (self.elements) -1)
        idx = max (idx, 0)

        return self.elements[idx]

    def delete_element (self, element):
        assert element in self.elements

        self.elements.remove (element)
        element.parent = None

    def set_start (self, start):
        self.start = start
        for e in self.elements:
            e.set_start (start)

    def find_first (self, predicate):
        r = Music.find_first (self, predicate)
        if r:
            return r

        for e in self.elements:
            r = e.find_first (predicate)
            if r:
                return r
        return None

class SequentialMusic (NestedMusic):
    def get_last_event_chord (self):
        value = None
        at = len( self.elements ) - 1
        while (at >= 0 and
               not isinstance (self.elements[at], ChordEvent) and
               not isinstance (self.elements[at], BarLine)):
            at -= 1

        if (at >= 0 and isinstance (self.elements[at], ChordEvent)):
            value = self.elements[at]
        return value

    def print_ly (self, printer, newline = True):
        printer ('{')
        if self.comment:
            self.print_comment (printer)

        if newline:
            printer.newline()
        for e in self.elements:
            e.print_ly (printer)

        printer ('}')
        if newline:
            printer.newline()

    def lisp_sub_expression (self, pred):
        name = self.name()


        props = self.get_subset_properties (pred)

        return "(make-music '%s %s)" % (name,  props)

    def set_start (self, start):
        for e in self.elements:
            e.set_start (start)
            start += e.get_length()

class RepeatedMusic:
    def __init__ (self):
        self.repeat_type = "volta"
        self.repeat_count = 2
        self.endings = []
        self.music = None
    def set_music (self, music):
        if isinstance (music, Music):
            self.music = music
        elif isinstance (music, list):
            self.music = SequentialMusic ()
            self.music.elements = music
        else:
            ly.warning (_ ("unable to set the music %(music)s for the repeat %(repeat)s") % \
                            {'music':music, 'repeat':self})
    def add_ending (self, music):
        self.endings.append (music)
    def print_ly (self, printer):
        printer.dump ('\\repeat %s %s' % (self.repeat_type, self.repeat_count))
        if self.music:
            self.music.print_ly (printer)
        else:
            ly.warning (_ ("encountered repeat without body"))
            printer.dump ('{}')
        if self.endings:
            printer.dump ('\\alternative {')
            for e in self.endings:
                e.print_ly (printer)
            printer.dump ('}')


class Lyrics:
    def __init__ (self):
        self.lyrics_syllables = []

    def print_ly (self, printer):
        printer.dump ("\lyricmode {")
        for l in self.lyrics_syllables:
            printer.dump ( "%s " % l )
        printer.dump ("}")

    def ly_expression (self):
        lstr = "\lyricmode {\n  "
        for l in self.lyrics_syllables:
            lstr += l + " "
        lstr += "\n}"
        return lstr


class Header:
    def __init__ (self):
        self.header_fields = {}
    def set_field (self, field, value):
        self.header_fields[field] = value

    def print_ly (self, printer):
        printer.dump ("\header {")
        printer.newline ()
        for (k,v) in self.header_fields.items ():
            if v:
                printer.dump ('%s = %s' % (k,v))
                printer.newline ()
        printer.dump ("}")
        printer.newline ()
        printer.newline ()


class Paper:
    def __init__ (self):
        self.global_staff_size = -1
        # page size
        self.page_width = -1
        self.page_height = -1
        # page margins
        self.top_margin = -1
        self.bottom_margin = -1
        self.left_margin = -1
        self.right_margin = -1
        self.system_left_margin = -1
        self.system_right_margin = -1
        self.system_distance = -1
        self.top_system_distance = -1

    def print_length_field (self, printer, field, value):
        if value >= 0:
            printer.dump ("%s = %s\\cm" % (field, value))
            printer.newline ()
    def print_ly (self, printer):
        if self.global_staff_size > 0:
            printer.dump ('#(set-global-staff-size %s)' % self.global_staff_size)
            printer.newline ()
        printer.dump ('\\paper {')
        printer.newline ()
        self.print_length_field (printer, "paper-width", self.page_width)
        self.print_length_field (printer, "paper-height", self.page_height)
        self.print_length_field (printer, "top-margin", self.top_margin)
        self.print_length_field (printer, "bottom-margin", self.bottom_margin)
        self.print_length_field (printer, "left-margin", self.left_margin)
        # TODO: maybe set line-width instead of right-margin?
        self.print_length_field (printer, "right-margin", self.right_margin)
        # TODO: What's the corresponding setting for system_left_margin and
        #        system_right_margin in LilyPond?
        self.print_length_field (printer, "between-system-space", self.system_distance)
        self.print_length_field (printer, "page-top-space", self.top_system_distance)

        printer.dump ('}')
        printer.newline ()

class Layout:
    def __init__ (self):
        self.context_dict = {}
    def add_context (self, context):
        if not self.context_dict.has_key (context):
            self.context_dict[context] = []
    def set_context_item (self, context, item):
        self.add_context (context)
        if not item in self.context_dict[context]:
            self.context_dict[context].append (item)
    def print_ly (self, printer):
        if self.context_dict.items ():
            printer.dump ('\\layout {')
            printer.newline ()
            for (context, defs) in self.context_dict.items ():
                printer.dump ('\\context { \\%s' % context)
                printer.newline ()
                for d in defs:
                    printer.dump (d)
                    printer.newline ()
                printer.dump ('}')
                printer.newline ()
            printer.dump ('}')
            printer.newline ()


class ChordEvent (NestedMusic):
    def __init__ (self):
        NestedMusic.__init__ (self)
        self.after_grace_elements = None
        self.grace_elements = None
        self.grace_type = None
    def append_grace (self, element):
        if element:
            if not self.grace_elements:
                self.grace_elements = SequentialMusic ()
            self.grace_elements.append (element)
    def append_after_grace (self, element):
        if element:
            if not self.after_grace_elements:
                self.after_grace_elements = SequentialMusic ()
            self.after_grace_elements.append (element)

    def has_elements (self):
        return [e for e in self.elements if
               isinstance (e, NoteEvent) or isinstance (e, RestEvent)] != []


    def get_length (self):
        l = Rational (0)
        for e in self.elements:
            l = max(l, e.get_length())
        return l

    def get_duration (self):
        note_events = [e for e in self.elements if
               isinstance (e, NoteEvent) or isinstance (e, RestEvent)]
        if note_events:
            return note_events[0].duration
        else:
            return None

    def print_ly (self, printer):
        note_events = [e for e in self.elements if
               isinstance (e, NoteEvent)]

        rest_events = [e for e in self.elements if
               isinstance (e, RhythmicEvent)
               and not isinstance (e, NoteEvent)]

        other_events = [e for e in self.elements if
                not isinstance (e, RhythmicEvent)]

        if self.after_grace_elements:
            printer ('\\afterGrace {')

        if self.grace_elements and self.elements:
            if self.grace_type:
                printer ('\\%s' % self.grace_type)
            else:
                printer ('\\grace')
            # don't print newlines after the { and } braces
            self.grace_elements.print_ly (printer, False)
        elif self.grace_elements: # no self.elements!
            ly.warning (_ ("Grace note with no following music: %s") % self.grace_elements)
            if self.grace_type:
                printer ('\\%s' % self.grace_type)
            else:
                printer ('\\grace')
            self.grace_elements.print_ly (printer, False)
            printer ('{}')

        # Print all overrides and other settings needed by the
        # articulations/ornaments before the note
        for e in other_events:
            e.print_before_note (printer)

        if rest_events:
            rest_events[0].print_ly (printer)
        elif len (note_events) == 1:
            note_events[0].print_ly (printer)
        elif note_events:
            global previous_pitch
            pitches = []
            basepitch = None
            for x in note_events:
                pitches.append (x.chord_element_ly ())
                if not basepitch:
                    basepitch = previous_pitch
            printer ('<%s>' % string.join (pitches))
            previous_pitch = basepitch
            duration = self.get_duration ()
            if duration:
                duration.print_ly (printer)
        else:
            pass

        for e in other_events:
            e.print_ly (printer)

        for e in other_events:
            e.print_after_note (printer)

        if self.after_grace_elements:
            printer ('}')
            self.after_grace_elements.print_ly (printer, False)

        self.print_comment (printer)

class Partial (Music):
    def __init__ (self):
        Music.__init__ (self)
        self.partial = None
    def print_ly (self, printer):
        if self.partial:
            printer.dump ("\\partial %s" % self.partial.ly_expression ())

class BarLine (Music):
    def __init__ (self):
        Music.__init__ (self)
        self.bar_number = 0
        self.type = None

    def print_ly (self, printer):
        bar_symbol = { 'regular': "|", 'dotted': ":", 'dashed': "dashed",
                       'heavy': "|", 'light-light': "||", 'light-heavy': "|.",
                       'heavy-light': ".|", 'heavy-heavy': ".|.", 'tick': "'",
                       'short': "'", 'none': "" }.get (self.type, None)
        if bar_symbol <> None:
            printer.dump ('\\bar "%s"' % bar_symbol)
        else:
            printer.dump ("|")

        if self.bar_number > 0 and (self.bar_number % 10) == 0:
            printer.dump ("\\barNumberCheck #%d " % self.bar_number)
        elif self.bar_number > 0:
            printer.print_verbatim (' %% %d' % self.bar_number)
        printer.newline ()

    def ly_expression (self):
        return " | "

class Event(Music):
    def __init__ (self):
        # strings to print before the note to which an event is attached.
        # Ignored for notes etc.
        self.before_note = None
        self.after_note = None
   # print something before the note to which an event is attached, e.g. overrides
    def print_before_note (self, printer):
        if self.before_note:
            printer.dump (self.before_note)
   # print something after the note to which an event is attached, e.g. resetting
    def print_after_note (self, printer):
        if self.after_note:
            printer.dump (self.after_note)
    pass

class SpanEvent (Event):
    def __init__ (self):
        Event.__init__ (self)
        self.span_direction = 0 # start/stop
        self.line_type = 'solid'
        self.span_type = 0 # e.g. cres/decrescendo, ottava up/down
        self.size = 0 # size of e.g. ocrave shift
    def wait_for_note (self):
        return True
    def get_properties(self):
        return "'span-direction  %d" % self.span_direction
    def set_span_type (self, type):
        self.span_type = type

class SlurEvent (SpanEvent):
    def print_before_note (self, printer):
        command = {'dotted': '\\slurDotted',
                  'dashed' : '\\slurDashed'}.get (self.line_type, '')
        if command and self.span_direction == -1:
            printer.dump (command)
    def print_after_note (self, printer):
        # reset non-solid slur types!
        command = {'dotted': '\\slurSolid',
                  'dashed' : '\\slurSolid'}.get (self.line_type, '')
        if command and self.span_direction == -1:
            printer.dump (command)
    def ly_expression (self):
        return {-1: '(', 1:')'}.get (self.span_direction, '')

class BeamEvent (SpanEvent):
    def ly_expression (self):
        return {-1: '[', 1:']'}.get (self.span_direction, '')

class PedalEvent (SpanEvent):
    def ly_expression (self):
        return {-1: '\\sustainOn',
            0:'\\sustainOff\\sustainOn',
            1:'\\sustainOff'}.get (self.span_direction, '')

class TextSpannerEvent (SpanEvent):
    def ly_expression (self):
        return {-1: '\\startTextSpan',
            1:'\\stopTextSpan'}.get (self.span_direction, '')

class BracketSpannerEvent (SpanEvent):
    # Ligature brackets use prefix-notation!!!
    def print_before_note (self, printer):
        if self.span_direction == -1:
            printer.dump ('\[')
    # the bracket after the last note
    def print_after_note (self, printer):
        if self.span_direction == 1:
            printer.dump ('\]')
    # we're printing everything in print_(before|after)_note...
    def ly_expression (self):
        return '';


class OctaveShiftEvent (SpanEvent):
    def wait_for_note (self):
        return False
    def set_span_type (self, type):
        self.span_type = {'up': 1, 'down': -1}.get (type, 0)
    def ly_octave_shift_indicator (self):
        # convert 8/15 to lilypond indicators (+-1/+-2)
        try:
            value = {8: 1, 15: 2}[self.size]
        except KeyError:
            ly.warning (_ ("Invalid octave shift size found: %s. Using no shift.") % self.size)
            value = 0
        # negative values go up!
        value *= -1*self.span_type
        return value
    def ly_expression (self):
        dir = self.ly_octave_shift_indicator ()
        value = ''
        if dir:
            value = '\ottava #%s' % dir
        return {
            -1: value,
            1: '\ottava #0'}.get (self.span_direction, '')

class TrillSpanEvent (SpanEvent):
    def ly_expression (self):
        return {-1: '\\startTrillSpan',
            0: '', # no need to write out anything for type='continue'
            1:'\\stopTrillSpan'}.get (self.span_direction, '')

class GlissandoEvent (SpanEvent):
    def print_before_note (self, printer):
        if self.span_direction == -1:
            style= {
                "dashed" : "dashed-line",
                "dotted" : "dotted-line",
                "wavy"   : "zigzag"
            }. get (self.line_type, None)
            if style:
                printer.dump ("\\once \\override Glissando #'style = #'%s" % style)
    def ly_expression (self):
        return {-1: '\\glissando',
            1:''}.get (self.span_direction, '')

class ArpeggioEvent(Event):
    def __init__ (self):
        Event.__init__ (self)
        self.direction = 0
        self.non_arpeggiate = False
    def wait_for_note (self):
        return True
    def print_before_note (self, printer):
        if self.non_arpeggiate:
            printer.dump ("\\arpeggioBracket")
        else:
          dir = { -1: "\\arpeggioArrowDown", 1: "\\arpeggioArrowUp" }.get (self.direction, '')
          if dir:
              printer.dump (dir)
    def print_after_note (self, printer):
        if self.non_arpeggiate or self.direction:
            printer.dump ("\\arpeggioNormal")
    def ly_expression (self):
        return ('\\arpeggio')


class TieEvent(Event):
    def ly_expression (self):
        return '~'


class HairpinEvent (SpanEvent):
    def set_span_type (self, type):
        self.span_type = {'crescendo' : 1, 'decrescendo' : -1, 'diminuendo' : -1 }.get (type, 0)
    def hairpin_to_ly (self):
        if self.span_direction == 1:
            return '\!'
        else:
            return {1: '\<', -1: '\>'}.get (self.span_type, '')

    def ly_expression (self):
        return self.hairpin_to_ly ()

    def print_ly (self, printer):
        val = self.hairpin_to_ly ()
        if val:
            printer.dump (val)



class DynamicsEvent (Event):
    def __init__ (self):
        Event.__init__ (self)
        self.type = None
    def wait_for_note (self):
        return True
    def ly_expression (self):
        if self.type:
            return '\%s' % self.type
        else:
            return

    def print_ly (self, printer):
        if self.type:
            printer.dump ("\\%s" % self.type)

class MarkEvent (Event):
    def __init__ (self, text="\\default"):
        Event.__init__ (self)
        self.mark = text
    def wait_for_note (self):
        return False
    def ly_contents (self):
        if self.mark:
            return '%s' % self.mark
        else:
            return "\"ERROR\""
    def ly_expression (self):
        return '\\mark %s' % self.ly_contents ()

class MusicGlyphMarkEvent (MarkEvent):
    def ly_contents (self):
        if self.mark:
            return '\\markup { \\musicglyph #"scripts.%s" }' % self.mark
        else:
            return ''


class TextEvent (Event):
    def __init__ (self):
        Event.__init__ (self)
        self.Text = None
        self.force_direction = None
        self.markup = ''
    def wait_for_note (self):
        return True

    def direction_mod (self):
        return { 1: '^', -1: '_', 0: '-' }.get (self.force_direction, '-')

    def ly_expression (self):
        base_string = '%s\"%s\"'
        if self.markup:
            base_string = '%s\markup{ ' + self.markup + ' {%s} }'
        return base_string % (self.direction_mod (), self.text)

class ArticulationEvent (Event):
    def __init__ (self):
        Event.__init__ (self)
        self.type = None
        self.force_direction = None
    def wait_for_note (self):
        return True

    def direction_mod (self):
        return { 1: '^', -1: '_', 0: '-' }.get (self.force_direction, '')

    def ly_expression (self):
        return '%s\\%s' % (self.direction_mod (), self.type)

class ShortArticulationEvent (ArticulationEvent):
    def direction_mod (self):
        # default is -
        return { 1: '^', -1: '_', 0: '-' }.get (self.force_direction, '-')
    def ly_expression (self):
        if self.type:
            return '%s%s' % (self.direction_mod (), self.type)
        else:
            return ''

class NoDirectionArticulationEvent (ArticulationEvent):
    def ly_expression (self):
        if self.type:
            return '\\%s' % self.type
        else:
            return ''

class MarkupEvent (ShortArticulationEvent):
    def __init__ (self):
        ArticulationEvent.__init__ (self)
        self.contents = None
    def ly_expression (self):
        if self.contents:
            return "%s\\markup { %s }" % (self.direction_mod (), self.contents)
        else:
            return ''

class FretEvent (MarkupEvent):
    def __init__ (self):
        MarkupEvent.__init__ (self)
        self.force_direction = 1
        self.strings = 6
        self.frets = 4
        self.barre = None
        self.elements = []
    def ly_expression (self):
        val = ""
        if self.strings <> 6:
            val += "w:%s;" % self.strings
        if self.frets <> 4:
            val += "h:%s;" % self.frets
        if self.barre and len (self.barre) >= 3:
            val += "c:%s-%s-%s;" % (self.barre[0], self.barre[1], self.barre[2])
        have_fingering = False
        for i in self.elements:
            if len (i) > 1:
                val += "%s-%s" % (i[0], i[1])
            if len (i) > 2:
                have_fingering = True
                val += "-%s" % i[2]
            val += ";"
        if have_fingering:
            val = "f:1;" + val
        if val:
            return "%s\\markup { \\fret-diagram #\"%s\" }" % (self.direction_mod (), val)
        else:
            return ''


class FunctionWrapperEvent (Event):
    def __init__ (self, function_name = None):
        Event.__init__ (self)
        self.function_name = function_name
    def pre_note_ly (self, is_chord_element):
        if self.function_name:
            return "\\%s" % self.function_name
        else:
            return ''
    def pre_chord_ly (self):
        return ''
    def ly_expression (self):
        if self.function_name:
            return "\\%s" % self.function_name
        else:
            return ''

class ParenthesizeEvent (FunctionWrapperEvent):
    def __init__ (self):
        FunctionWrapperEvent.__init__ (self, "parenthesize")

class NotestyleEvent (Event):
    def __init__ (self):
        Event.__init__ (self)
        self.style = None
        self.filled = None
    def pre_chord_ly (self):
        if self.style:
            return "\\once \\override NoteHead #'style = #%s" % self.style
        else:
            return ''
    def pre_note_ly (self, is_chord_element):
        if self.style and is_chord_element:
            return "\\tweak #'style #%s" % self.style
        else:
            return ''
    def ly_expression (self):
        return self.pre_chord_ly ()


class ChordPitch:
    def __init__ (self):
        self.alteration = 0
        self.step = 0
    def __repr__(self):
        return self.ly_expression()
    def ly_expression (self):
        return pitch_generating_function (self)

class ChordModification:
    def __init__ (self):
        self.alteration = 0
        self.step = 0
        self.type = 0
    def ly_expression (self):
        if self.type:
            val = {1: ".", -1: "^" }.get (self.type, "")
            val += "%s" % self.step
            val += {1: "+", -1: "-"}.get (self.alteration, "")
            return val
        else:
            return ''

class ChordNameEvent (Event):
    def __init__ (self):
        Event.__init__ (self)
        self.root = None
        self.kind = None
        self.duration = None
        self.modifications = []
        self.bass = None
    def add_modification (self, mod):
        self.modifications.append (mod)
    def ly_expression (self):
        if not self.root:
            return ''
        value = self.root.ly_expression ()
        if self.duration:
            value += self.duration.ly_expression ()
        if self.kind:
            value += ":"
            value += self.kind
        # First print all additions/changes, and only afterwards all subtractions
        for m in self.modifications:
            if m.type == 1:
              value += m.ly_expression ()
        for m in self.modifications:
            if m.type == -1:
              value += m.ly_expression ()
        if self.bass:
            value += "/+%s" % self.bass.ly_expression ()
        return value


class TremoloEvent (ArticulationEvent):
    def __init__ (self):
        Event.__init__ (self)
        self.bars = 0

    def ly_expression (self):
        str=''
        if self.bars and self.bars > 0:
            str += ':%s' % (2 ** (2 + string.atoi (self.bars)))
        return str

class BendEvent (ArticulationEvent):
    def __init__ (self):
        Event.__init__ (self)
        self.alter = None
    def ly_expression (self):
        if self.alter != None:
            return "-\\bendAfter #%s" % self.alter
        else:
            return ''

class RhythmicEvent(Event):
    def __init__ (self):
        Event.__init__ (self)
        self.duration = Duration()
        self.associated_events = []

    def add_associated_event (self, ev):
        if ev:
            self.associated_events.append (ev)

    def pre_chord_ly (self):
        return [ev.pre_chord_ly () for ev in self.associated_events]

    def pre_note_ly (self, is_chord_element):
        return [ev.pre_note_ly (is_chord_element) for ev in self.associated_events]

    def ly_expression_pre_note (self, is_chord_element):
        res = string.join (self.pre_note_ly (is_chord_element), ' ')
        if res != '':
            res = res + ' '
        return res

    def get_length (self):
        return self.duration.get_length()

    def get_properties (self):
        return ("'duration %s"
                % self.duration.lisp_expression ())

class RestEvent (RhythmicEvent):
    def __init__ (self):
        RhythmicEvent.__init__ (self)
        self.pitch = None

    def ly_expression (self):
        res = self.ly_expression_pre_note (False)
        if self.pitch:
            return res + "%s%s\\rest" % (self.pitch.ly_expression (), self.duration.ly_expression ())
        else:
            return 'r%s' % self.duration.ly_expression ()

    def print_ly (self, printer):
        for ev in self.associated_events:
            ev.print_ly (printer)
        if self.pitch:
            self.pitch.print_ly (printer)
            self.duration.print_ly (printer)
            printer ('\\rest')
        else:
            printer('r')
            self.duration.print_ly (printer)

class SkipEvent (RhythmicEvent):
    def ly_expression (self):
        return 's%s' % self.duration.ly_expression ()

class NoteEvent(RhythmicEvent):
    def  __init__ (self):
        RhythmicEvent.__init__ (self)
        self.pitch = None
        self.drum_type = None
        self.cautionary = False
        self.forced_accidental = False

    def get_properties (self):
        str = RhythmicEvent.get_properties (self)

        if self.pitch:
            str += self.pitch.lisp_expression ()
        elif self.drum_type:
            str += "'drum-type '%s" % self.drum_type

        return str

    def pitch_mods (self):
        excl_question = ''
        if self.cautionary:
            excl_question += '?'
        if self.forced_accidental:
            excl_question += '!'

        return excl_question

    def ly_expression (self):
        # obtain all stuff that needs to be printed before the note:
        res = self.ly_expression_pre_note (True)
        if self.pitch:
            return res + '%s%s%s' % (self.pitch.ly_expression (),
                               self.pitch_mods(),
                               self.duration.ly_expression ())
        elif self.drum_type:
            return res + '%s%s' (self.drum_type,
                           self.duration.ly_expression ())

    def chord_element_ly (self):
        # obtain all stuff that needs to be printed before the note:
        res = self.ly_expression_pre_note (True)
        if self.pitch:
            return res + '%s%s' % (self.pitch.ly_expression (),
                               self.pitch_mods())
        elif self.drum_type:
            return res + '%s%s' (self.drum_type)


    def print_ly (self, printer):
        for ev in self.associated_events:
            ev.print_ly (printer)
        if self.pitch:
            self.pitch.print_ly (printer)
            printer (self.pitch_mods ())
        else:
            printer (self.drum_type)

        self.duration.print_ly (printer)

class KeySignatureChange (Music):
    def __init__ (self):
        Music.__init__ (self)
        self.tonic = None
        self.mode = 'major'
        self.non_standard_alterations = None

    def format_non_standard_alteration (self, a):
        alter_dict = { -2:   ",DOUBLE-FLAT",
                       -1.5: ",THREE-Q-FLAT",
                       -1:   ",FLAT",
                       -0.5: ",SEMI-FLAT",
                        0:   ",NATURAL",
                        0.5: ",SEMI-SHARP",
                        1:   ",SHARP",
                        1.5: ",THREE-Q-SHARP",
                        2:   ",DOUBLE-SHARP"}
        try:
            accidental = alter_dict[a[1]]
        except KeyError:
            ly.warning (_ ("Unable to convert alteration %s to a lilypond expression") % a[1])
            return ''
        if len (a) == 2:
            return "( %s . %s )" % (a[0], accidental)
        elif len (a) == 3:
            return "(( %s . %s ) . %s )" % (a[2], a[0], accidental)
        else:
            return ''

    def ly_expression (self):
        if self.tonic:
            return '\\key %s \\%s' % (self.tonic.ly_step_expression (),
                     self.mode)
        elif self.non_standard_alterations:
            alterations = [self.format_non_standard_alteration (a) for
                                        a in self.non_standard_alterations]
            return "\\set Staff.keySignature = #`(%s)" % string.join (alterations, " ")
        else:
            return ''

class TimeSignatureChange (Music):
    def __init__ (self):
        Music.__init__ (self)
        self.fractions = [4,4]
        self.style = None
    def format_fraction (self, frac):
        if isinstance (frac, list):
            l = [self.format_fraction (f) for f in frac]
            return "(" + string.join (l, " ") + ")"
        else:
            return "%s" % frac

    def ly_expression (self):
        st = ''
        # Print out the style if we have ome, but the '() should only be
        # forced for 2/2 or 4/4, since in all other cases we'll get numeric
        # signatures anyway despite the default 'C signature style!
        is_common_signature = self.fractions in ([2,2], [4,4], [4,2])
        if self.style:
            if self.style == "common":
                st = "\\defaultTimeSignature"
            elif (self.style != "'()"):
                st = "\\once \\override Staff.TimeSignature #'style = #%s " % self.style
            elif (self.style != "'()") or is_common_signature:
                st = "\\numericTimeSignature"

        # Easy case: self.fractions = [n,d] => normal \time n/d call:
        if len (self.fractions) == 2 and isinstance (self.fractions[0], int):
            return st + '\\time %d/%d ' % tuple (self.fractions)
        elif self.fractions:
            return st + "\\compoundMeter #'%s" % self.format_fraction (self.fractions)
        else:
            return st + ''

class ClefChange (Music):
    def __init__ (self):
        Music.__init__ (self)
        self.type = 'G'
        self.position = 2
        self.octave = 0

    def octave_modifier (self):
        return {1: "^8", 2: "^15", -1: "_8", -2: "_15"}.get (self.octave, '')
    def clef_name (self):
        return {('G', 2): "treble",
                ('G', 1): "french",
                ('C', 1): "soprano",
                ('C', 2): "mezzosoprano",
                ('C', 3): "alto",
                ('C', 4): "tenor",
                ('C', 5): "baritone",
                ('F', 3): "varbaritone",
                ('F', 4): "bass",
                ('F', 5): "subbass",
                ("percussion", 2): "percussion",
                # Workaround: MuseScore uses PERC instead of percussion
                ("PERC", 2): "percussion",
                ("TAB", 5): "tab"}.get ((self.type, self.position), None)
    def ly_expression (self):
        return '\\clef "%s%s"' % (self.clef_name (), self.octave_modifier ())

    clef_dict = {
        "G": ("clefs.G", -2, -6),
        "C": ("clefs.C", 0, 0),
        "F": ("clefs.F", 2, 6),
        }

    def lisp_expression (self):
        try:
            (glyph, pos, c0) = self.clef_dict[self.type]
        except KeyError:
            return ""
        clefsetting = """
        (make-music 'SequentialMusic
        'elements (list
   (context-spec-music
   (make-property-set 'clefGlyph "%s") 'Staff)
   (context-spec-music
   (make-property-set 'clefPosition %d) 'Staff)
   (context-spec-music
   (make-property-set 'middleCPosition %d) 'Staff)))
""" % (glyph, pos, c0)
        return clefsetting

class Transposition (Music):
    def __init__ (self):
        Music.__init__ (self)
        self.pitch = None
    def ly_expression (self):
        self.pitch._force_absolute_pitch = True
        return '\\transposition %s' % self.pitch.ly_expression ()

class StaffChange (Music):
    def __init__ (self, staff):
        Music.__init__ (self)
        self.staff = staff
    def ly_expression (self):
        if self.staff:
            return "\\change Staff=\"%s\"" % self.staff
        else:
            return ''

class SetEvent (Music):
    def __init__ (self, contextprop, value):
        Music.__init__ (self)
        self.context_prop = contextprop
        self.value = value
    def ly_expression (self):
        if self.value:
            return "\\set %s = %s" % (self.context_prop, self.value)
        else:
            return ''

class StaffLinesEvent (Music):
    def __init__ (self, lines):
        Music.__init__ (self)
        self.lines = lines
    def ly_expression (self):
        if (self.lines > 0):
          return "\\stopStaff \\override Staff.StaffSymbol #'line-count = #%s \\startStaff" % self.lines
        else:
          return "\\stopStaff \\revert Staff.StaffSymbol #'line-count \\startStaff"

class TempoMark (Music):
    def __init__ (self):
        Music.__init__ (self)
        self.baseduration = None
        self.newduration = None
        self.beats = None
        self.parentheses = False
    def set_base_duration (self, dur):
        self.baseduration = dur
    def set_new_duration (self, dur):
        self.newduration = dur
    def set_beats_per_minute (self, beats):
        self.beats = beats
    def set_parentheses (self, parentheses):
        self.parentheses = parentheses
    def wait_for_note (self):
        return False
    def duration_to_markup (self, dur):
        if dur:
            # Generate the markup to print the note, use scheme mode for
            # ly_expression to get longa and not \longa (which causes an error)
            return "\\general-align #Y #DOWN \\smaller \\note #\"%s\" #UP" % dur.ly_expression(None, True)
        else:
            return ''
    def tempo_markup_template (self):
        return "\\mark\\markup { \\fontsize #-2 \\line { %s } }"
    def ly_expression (self):
        res = ''
        if not self.baseduration:
            return res
        if self.beats:
            if self.parentheses:
                res += "\\tempo \"\" %s=%s" % (self.baseduration.ly_expression(), self.beats)
            else:
                res += "\\tempo %s=%s" % (self.baseduration.ly_expression(), self.beats)
        elif self.newduration:
            dm = self.duration_to_markup (self.baseduration)
            ndm = self.duration_to_markup (self.newduration)
            if self.parentheses:
                contents = "\"(\" %s = %s \")\"" % (dm, ndm)
            else:
                contents = " %s = %s " % (dm, ndm)
            res += self.tempo_markup_template() % contents
        else:
            return ''
        return res

class FiguredBassNote (Music):
    def __init__ (self):
        Music.__init__ (self)
        self.number = ''
        self.prefix = ''
        self.suffix = ''
    def set_prefix (self, prefix):
        self.prefix = prefix
    def set_suffix (self, suffix):
        self.prefix = suffix
    def set_number (self, number):
        self.number = number
    def ly_expression (self):
        res = ''
        if self.number:
            res += self.number
        else:
            res += '_'
        if self.prefix:
            res += self.prefix
        if self.suffix:
            res += self.suffix
        return res


class FiguredBassEvent (NestedMusic):
    def __init__ (self):
        NestedMusic.__init__ (self)
        self.duration = None
        self.real_duration = 0
        self.parentheses = False
        return
    def set_duration (self, dur):
        self.duration = dur
    def set_parentheses (self, par):
        self.parentheses = par
    def set_real_duration (self, dur):
        self.real_duration = dur

    def print_ly (self, printer):
        figured_bass_events = [e for e in self.elements if
               isinstance (e, FiguredBassNote)]
        if figured_bass_events:
          notes = []
          for x in figured_bass_events:
              notes.append (x.ly_expression ())
          contents = string.join (notes)
          if self.parentheses:
              contents = '[%s]' % contents
          printer ('<%s>' % contents)
          self.duration.print_ly (printer)


class MultiMeasureRest(Music):

    def lisp_expression (self):
        return """
(make-music
  'MultiMeasureRestMusicGroup
  'elements
  (list (make-music (quote BarCheck))
        (make-music
          'ChordEvent
          'elements
          (list (make-music
                  'MultiMeasureRestEvent
                  'duration
                  %s)))
        (make-music (quote BarCheck))))
""" % self.duration.lisp_expression ()

    def ly_expression (self):
        return 'R%s' % self.duration.ly_expression ()


class Break (Music):
    def __init__ (self, tp="break"):
        Music.__init__ (self)
        self.type = tp
    def print_ly (self, printer):
        if self.type:
            printer.dump ("\\%s" % self.type)

class StaffGroup:
    def __init__ (self, command = "StaffGroup"):
        self.stafftype = command
        self.id = None
        self.instrument_name = None
        self.short_instrument_name = None
        self.symbol = None
        self.spanbar = None
        self.children = []
        self.is_group = True
        self.context_modifications = []
        # part_information is a list with entries of the form
        #     [staffid, voicelist]
        # where voicelist is a list with entries of the form
        #     [voiceid1, [lyricsid11, lyricsid12,...] ]
        self.part_information = None

    def append_staff (self, staff):
        self.children.append (staff)

    def set_part_information (self, part_name, staves_info):
        if part_name == self.id:
            self.part_information = staves_info
        else:
            for c in self.children:
                c.set_part_information (part_name, staves_info)

    def add_context_modification (self, modification):
        self.context_modifications.append (modification)

    def print_ly_contents (self, printer):
        for c in self.children:
            if c:
                c.print_ly (printer)
    def needs_with (self):
        needs_with = False
        needs_with |= self.spanbar == "no"
        needs_with |= self.instrument_name != None
        needs_with |= self.short_instrument_name != None
        needs_with |= (self.symbol != None) and (self.symbol != "bracket")
        return needs_with
    def print_ly_context_mods (self, printer):
        if self.instrument_name or self.short_instrument_name:
            printer.dump ("\\consists \"Instrument_name_engraver\"")
        if self.spanbar == "no":
            printer.dump ("\\override SpanBar #'transparent = ##t")
        brack = {"brace": "SystemStartBrace",
                 "none": "SystemStartBar",
                 "line": "SystemStartSquare"}.get (self.symbol, None)
        if brack:
            printer.dump ("systemStartDelimiter = #'%s" % brack)

    def print_ly_overrides (self, printer):
        needs_with = self.needs_with () | (len (self.context_modifications) > 0);
        if needs_with:
            printer.dump ("\\with {")
            self.print_ly_context_mods (printer)
            for m in self.context_modifications:
                printer.dump (m)
            printer.dump ("}")

    def print_ly_chords (self,printer):
        try:
            for [staff_id, voices] in self.part_information:
                for [v, lyrics, figuredbass, chordnames] in voices:
                    if chordnames:
                        printer ('\context ChordNames = "%s" \\%s' % (chordnames, chordnames))
                        printer.newline ()
        except TypeError:
            return

    def print_ly (self, printer):
        self.print_ly_chords (printer)
        if self.stafftype:
            printer.dump ("\\new %s" % self.stafftype)
        self.print_ly_overrides (printer)
        printer.dump ("<<")
        printer.newline ()
        if self.stafftype and self.instrument_name:
            printer.dump ("\\set %s.instrumentName = %s" % (self.stafftype,
                    escape_instrument_string (self.instrument_name)))
            printer.newline ()
        if self.stafftype and self.short_instrument_name:
            printer.dump ("\\set %s.shortInstrumentName = %s" % (self.stafftype,
                    escape_instrument_string (self.short_instrument_name)))
            printer.newline ()
        self.print_ly_contents (printer)
        printer.newline ()
        printer.dump (">>")
        printer.newline ()


class Staff (StaffGroup):
    def __init__ (self, command = "Staff"):
        StaffGroup.__init__ (self, command)
        self.is_group = False
        self.part = None
        self.voice_command = "Voice"
        self.substafftype = None

    def needs_with (self):
        return False
    def print_ly_context_mods (self, printer):
        pass

    def print_ly_contents (self, printer):
        if not self.id or not self.part_information:
            return
        sub_staff_type = self.substafftype
        if not sub_staff_type:
            sub_staff_type = self.stafftype

        for [staff_id, voices] in self.part_information:
            if staff_id:
                printer ('\\context %s = "%s" << ' % (sub_staff_type, staff_id))
            else:
                printer ('\\context %s << ' % sub_staff_type)
            printer.newline ()
            n = 0
            nr_voices = len (voices)
            for [v, lyrics, figuredbass, chordnames] in voices:
                n += 1
                voice_count_text = ''
                if nr_voices > 1:
                    voice_count_text = {1: ' \\voiceOne', 2: ' \\voiceTwo',
                                        3: ' \\voiceThree'}.get (n, ' \\voiceFour')
                printer ('\\context %s = "%s" {%s \\%s }' % (self.voice_command, v, voice_count_text, v))
                printer.newline ()

                for l in lyrics:
                    printer ('\\new Lyrics \\lyricsto "%s" \\%s' % (v,l))
                    printer.newline()
                if figuredbass:
                    printer ('\context FiguredBass = "%s" \\%s' % (figuredbass, figuredbass))
            printer ('>>')

    def print_ly (self, printer):
        if self.part_information and len (self.part_information) > 1:
            self.stafftype = "PianoStaff"
            self.substafftype = "Staff"
        StaffGroup.print_ly (self, printer)

class TabStaff (Staff):
    def __init__ (self, command = "TabStaff"):
        Staff.__init__ (self, command)
        self.string_tunings = []
        self.tablature_format = None
        self.voice_command = "TabVoice"
    def print_ly_overrides (self, printer):
        if self.string_tunings or self.tablature_format:
            printer.dump ("\\with {")
            if self.string_tunings:
                printer.dump ("stringTunings = #`(")
                for i in self.string_tunings:
                    printer.dump (",%s" % i.lisp_expression ())
                printer.dump (")")
            if self.tablature_format:
                printer.dump ("tablatureFormat = #%s" % self.tablature_format)
            printer.dump ("}")


class DrumStaff (Staff):
    def __init__ (self, command = "DrumStaff"):
        Staff.__init__ (self, command)
        self.drum_style_table = None
        self.voice_command = "DrumVoice"
    def print_ly_overrides (self, printer):
        if self.drum_style_table:
            printer.dump ("\with {")
            printer.dump ("drumStyleTable = #%s" % self.drum_style_table)
            printer.dump ("}")

class RhythmicStaff (Staff):
    def __init__ (self, command = "RhythmicStaff"):
        Staff.__init__ (self, command)

class Score:
    def __init__ (self):
        self.contents = None
        self.create_midi = False

    def set_contents (self, contents):
        self.contents = contents

    def set_part_information (self, part_id, staves_info):
        if self.contents:
          self.contents.set_part_information (part_id, staves_info)

    def print_ly (self, printer):
        self.create_midi = get_create_midi ()
        printer.dump ("\\score {");
        printer.newline ()
        if self.contents:
            self.contents.print_ly (printer);
        printer.dump ("\\layout {}");
        printer.newline ()
        if not self.create_midi:
            printer.dump ("% To create MIDI output, uncomment the following line:");
            printer.newline ();
            printer.dump ("% ");
        printer.dump ("\\midi {}");
        printer.newline ()
        printer.dump ("}");
        printer.newline ()


def test_pitch ():
    bflat = Pitch()
    bflat.alteration = -1
    bflat.step =  6
    bflat.octave = -1
    fifth = Pitch()
    fifth.step = 4
    down = Pitch ()
    down.step = -4
    down.normalize ()


    print bflat.semitones()
    print bflat.transposed (fifth),  bflat.transposed (fifth).transposed (fifth)
    print bflat.transposed (fifth).transposed (fifth).transposed (fifth)

    print bflat.semitones(), 'down'
    print bflat.transposed (down)
    print bflat.transposed (down).transposed (down)
    print bflat.transposed (down).transposed (down).transposed (down)



def test_printer ():
    def make_note ():
        evc = ChordEvent()
        n = NoteEvent()
        evc.append (n)
        return n

    def make_tup ():
        m = SequentialMusic()
        m.append (make_note ())
        m.append (make_note ())
        m.append (make_note ())


        t = TimeScaledMusic ()
        t.numerator = 2
        t.denominator = 3
        t.element = m
        return t

    m = SequentialMusic ()
    m.append (make_tup ())
    m.append (make_tup ())
    m.append (make_tup ())

    printer = Output_printer()
    m.print_ly (printer)
    printer.newline ()

def test_expr ():
    m = SequentialMusic()
    l = 2
    evc = ChordEvent()
    n = NoteEvent()
    n.duration.duration_log = l
    n.pitch.step = 1
    evc.insert_around (None, n, 0)
    m.insert_around (None, evc, 0)

    evc = ChordEvent()
    n = NoteEvent()
    n.duration.duration_log = l
    n.pitch.step = 3
    evc.insert_around (None, n, 0)
    m.insert_around (None, evc, 0)

    evc = ChordEvent()
    n = NoteEvent()
    n.duration.duration_log = l
    n.pitch.step = 2
    evc.insert_around (None, n, 0)
    m.insert_around (None, evc, 0)

    evc = ClefChange()
    evc.type = 'treble'
    m.insert_around (None, evc, 0)

    evc = ChordEvent()
    tonic = Pitch ()
    tonic.step = 2
    tonic.alteration = -2
    n = KeySignatureChange()
    n.tonic=tonic.copy()
    n.scale = [0, 0, -2, 0, 0,-2,-2]

    evc.insert_around (None, n, 0)
    m.insert_around (None, evc, 0)

    return m


if __name__ == '__main__':
    test_printer ()
    raise 'bla'
    test_pitch()

    expr = test_expr()
    expr.set_start (Rational (0))
    print expr.ly_expression()
    start = Rational (0,4)
    stop = Rational (4,2)
    def sub(x, start=start, stop=stop):
        ok = x.start >= start and x.start +x.get_length() <= stop
        return ok

    print expr.lisp_sub_expression(sub)

