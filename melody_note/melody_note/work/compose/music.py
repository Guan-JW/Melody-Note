from mido import Message, MidiFile, MidiTrack
import pygame
import os
import subprocess
import shutil
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
import sys
sys.path.append(os.path.join(BASE_DIR,'wav_note'))
import melody_note.work.wav_note.music_transcriber

"""
# 通过librosa得到歌曲的节拍bpm
import librosa
import numpy as np
import mido
yy ,sr = librosa.load('new_song.wav')
onset_env = librosa.onset.onset_strength(yy, sr=sr, hop_length=512, aggregate=np.median)
tempo, _ = librosa.beat.beat_track(onset_envelope=onset_env, sr=sr)
bmp = mido.tempo2bpm(tempo)
print(bpm)
"""

bpm = 75

class Music:
    """
    melody：[(音阶（0~127）, 长度（浮点数，例如0.25,0.5,1,1.5,2,3……）,(60,0.25),(63,1)]
            音高：C调do为基准60
    name：歌曲名
    program：乐器代号 https://blog.csdn.net/ruyulin/article/details/84103186
    bpm：节拍数（Beat Per Minute）
    """
    def __init__(self,melody=None,name='default',program=0,bpm=75,save_path=os.path.join(BASE_DIR,'compose_mid')):
        self.melody = melody
        self.name = name
        self.program = program
        self.bpm = bpm
        self.save_path = save_path
        if melody != None:
            self.mid = MidiFile()  # 创建MidiFile对象
            self.track = MidiTrack()  # 创建音轨
            self.mid.tracks.append(self.track)  # 把音轨加到MidiFile对象中
            self.track.append(Message('program_change', program=program, time=0))
            self.track.append(Message('note_on', note=64, velocity=64, time=32))
            self.track.append(Message('note_off', note=64, velocity=127, time=32))
            for m in melody:
                self.play_note(m[0],m[1])
            self.save_mid()
    
    # 重新设置参数
    # 音乐名
    def set_name(self, name='default'):
        self.name = name
    
    # 音符、时长 [(60,1),(63,2),(66,0.5),...]
    def set_melody(self, melody):
        self.melody = melody
        self.mid = MidiFile()  # 创建MidiFile对象
        self.track = MidiTrack()  # 创建音轨
        self.mid.tracks.append(self.track)  # 把音轨加到MidiFile对象中
        self.track.append(Message('program_change', program=self.program, time=0))
        self.track.append(Message('note_on', note=64, velocity=64, time=32))
        self.track.append(Message('note_off', note=64, velocity=127, time=32))
        for m in melody:
            self.play_note(m[0],m[1])
        self.save_mid()
    
    # 乐器代号 https://blog.csdn.net/ruyulin/article/details/84103186
    def set_program(self, program=0):
        self.program = program

    def play_note(self, note, length, delay=0, velocity=1.0, channel=0):
        meta_time = 60 * 60 * 10 / bpm
        major_notes = [0, 2, 2, 1, 2, 2, 2, 1]
        self.track.append(
            Message('note_on', note=note, 
                    velocity=round(64 * velocity),
                    time=int(round(delay * meta_time)), channel=channel))
        self.track.append(
            Message('note_off', note=note,
                    velocity=round(64 * velocity),
                    time=int(round(meta_time * length)), channel=channel))
    
    # 保存为midi文件
    def save_mid(self):
        if not os.path.exists(self.save_path):
            os.mkdir(self.save_path)
        self.mid.save(os.path.join(self.save_path, self.name+'.mid'))

    # 转换为wav，需要java环境：https://www.cnblogs.com/lzz1997/p/11480592.html
    # java_path：java安装路径
    def transfer_wav(self,java_path="C:/Program Files/Java/jdk1.8.0_221/bin/"):
        if not os.path.exists(self.save_path):
            print("文件不存在！")
            return
        file = self.save_path+'/'+self.name
        cmd = java_path + "java -jar midi2wav.jar " + file + '.mid'
        subprocess.Popen(cmd)
    
    # 播放midi歌曲
    def play_midi(self):
        freq = 44100
        bitsize = -16
        channels = 2
        buffer = 1024
        pygame.mixer.init(freq, bitsize, channels, buffer)
        pygame.mixer.music.set_volume(1)
        clock = pygame.time.Clock()
        try:
            pygame.mixer.music.load(os.path.join(self.save_path,self.name+'.mid'))
        except:
            import traceback
            print(traceback.format_exc())
        pygame.mixer.music.play()
        while pygame.mixer.music.get_busy():
            clock.tick(30)

if __name__ == "__main__":
    transcriber = music_transcriber.MusicTranscriber(os.path.join(BASE_DIR,'record_wav','twinkle_short.wav'))
    notes, durations = transcriber.transcribe()
    durations = [i*3 for i in durations]
    melody = [tuple(i) for i in zip(notes,durations)]
    twinkle = Music(b,'twinkle_short')
    #twinkle.play_midi()
    #twinkle.transfer_wav()