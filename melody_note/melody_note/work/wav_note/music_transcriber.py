import sys
import os
curPath = os.path.abspath(os.path.dirname(__file__))

sys.path.append(curPath)

from melody_note.work.wav_note.onset_frames_split import OnsetFrameSplitter
#from first_peaks_method import MIDI_Detector
from melody_note.work.wav_note.plotNotes import NotePlotter
#from highest_peak_method import Highest_Peaks_MIDI_Detector
import os


class MusicTranscriber(object):
    """
        The class responsible for transcibing music stored in a .wav file
        to pdf sheet notes.
    """

    def __init__(self, music_file):
        self.music_file = music_file
        self.onset_frames_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)),'frames')

    def transcribe(self):
        """
            Splits the music file to be transcribed into onset frames,
            detects the notes in each frame and plots them on the staff.
        """
        print("1:" + os.path.abspath(os.path.dirname(__file__)))
        print("2:" + os.path.dirname(__file__))
        splitter = OnsetFrameSplitter(self.music_file, self.onset_frames_dir)
        print ('Created onset frame splitter object')
        splitter.onset_frames_split()
        print ('Splitted the file into frames')
        note_plotter = NotePlotter(self.music_file)
        print ('Created a note plotter object')
        notes, durations = note_plotter.plot_multiple_notes(self.onset_frames_dir)
        print ('Plotted multiple notes')
        return notes, durations


if __name__ == '__main__':
    # Provide the name of the music file (in wav. format) to be transcribed.
    music_file = sys.argv[1]
    print ('Read in a music file')
    transcriber = MusicTranscriber(music_file)
    print ('Created a transcriber object')
    notes, durations = transcriber.transcribe()
    print ('Transcribed the music piece')
