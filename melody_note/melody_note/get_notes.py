import os
from .work.sound_recorder import record
from .work.wav_note import music_transcriber
from .work.compose import music

# 全局变量
BASE_DIR = os.getcwd()
music_name = 'default'      # 音乐名
rec = record.Recorder()     # 录音
rec.set_name(music_name)
composer = music.Music()    # 音符转乐器


def get_notes(file_name=None):
    if file_name == None:
        file_name=os.path.join('test.wav')
    transcriber = music_transcriber.MusicTranscriber(file_name)
    notes, durations = transcriber.transcribe()
    durations = [i*2 for i in durations]
    melody = [tuple(i) for i in zip(notes,durations)]
    return melody



