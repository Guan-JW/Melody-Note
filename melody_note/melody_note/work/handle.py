import os
from .sound_recorder import record
from .wav_note import music_transcriber
from .compose import music

# 全局变量
BASE_DIR = os.getcwd()
music_name = 'default'      # 音乐名
rec = record.Recorder()     # 录音
rec.set_name(music_name)
composer = music.Music()    # 音符转乐器

# 设置音乐名（不需要带.wav或.mid等后缀）
def set_music_name(name):
    global music_name
    global rec
    global composer
    music_name = name
    rec.set_name(music_name)
    composer.set_name(music_name)

# 开始录音
def start_record():
    rec.start()

# 结束录音并将wav文件保存在record_wav文件夹
def stop_record():
    rec.stop()
    rec.save(os.path.join(BASE_DIR,'record_wav',music_name+'.wav'))

# 提取音符并将乐谱pdf保存在note_pdf文件夹下
def get_notes(file_name=None):
    if file_name == None:
        file_name=os.path.join(BASE_DIR,'record_wav',music_name+'.wav')
    transcriber = music_transcriber.MusicTranscriber(file_name)
    notes, durations = transcriber.transcribe()
    durations = [i*2 for i in durations]
    melody = [tuple(i) for i in zip(notes,durations)]
    return melody

# 设置乐器：https://blog.csdn.net/ruyulin/article/details/84103186
def choose_program(program=0):
    composer.set_program(program)

# 音符转乐器音并将mid文件保存在compose_mid文件夹下
def create_melody(melody):
    composer.set_melody(melody)

# 播放保存的mid文件
def play_music():
    if os.path.exists(os.path.join(composer.save_path,composer.name+'.mid')):
        composer.play_midi()

# mid转wav
def mid2wav():
    if os.path.exists(os.path.join(composer.save_path,composer.name+'.mid')):
        composer.transfer_wav()

if __name__ == "__main__":
    # step 1. 设置乐曲名
    set_music_name("test")

    # step 2. 录音
    print("输入 1 开始录音，输入 2 结束录音……")
    start = int(input('请输入相应数字开始:'))
    end = 0
    if start == 1:
        start_record()
        end = int(input('请输入相应数字停止:'))
        if end == 2:
            stop_record()
            print("录音结束……")
    
    if end == 2:
        # step 3. 音频转乐谱音符
        melody = get_notes()

        # step 4. 音符转乐器曲
        choose_program(0) # 可以设置乐器
        create_melody(melody)

        # (step 5. 播放)
        #play_music()

        # (step 6. mid转wav)
        #mid2wav()
