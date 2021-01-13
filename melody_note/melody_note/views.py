from binstar_client.pprintb import user_list
from django.shortcuts import render,redirect
from django.http import HttpResponse
from django.db import connections
from django.http import HttpResponseRedirect
import json
import time
import os
from melody_note.work.sound_recorder import record
from melody_note.work.wav_note import music_transcriber
from melody_note.work.compose import music

# 全局变量
BASE_DIR = os.getcwd()
music_name = 'default'      # 音乐名
rec = record.Recorder()     # 录音
rec.set_name(music_name)
composer = music.Music()    # 音符转乐器
begin = time.time()
final = begin



# 设置音乐名（不需要带.wav或.mid等后缀）
def set_music_name(name):
    global music_name
    global rec
    global composer
    music_name = name
    print("set:"+music_name)
    rec.set_name(music_name)
    composer.set_name(music_name)


# 开始录音
def start_record():
    rec.start()


# 结束录音并将wav文件保存在record_wav文件夹
def stop_record():
    rec.stop()
    print("stop:"+music_name)
    rec.save(os.path.join(BASE_DIR, 'melody_note','work','record_wav', music_name + '.wav'))


# 提取音符并将乐谱pdf保存在note_pdf文件夹下
def get_notes(file_name=None):
    if file_name == None:
        file_name = os.path.join(BASE_DIR,'melody_note','work', 'record_wav', music_name + '.wav')
    transcriber = music_transcriber.MusicTranscriber(file_name)
    notes, durations = transcriber.transcribe()
    durations = [i * 2 for i in durations]
    melody = [tuple(i) for i in zip(notes, durations)]
    return melody


# 设置乐器：https://blog.csdn.net/ruyulin/article/details/84103186
def choose_program(program=0):
    composer.set_program(program)


# 音符转乐器音并将mid文件保存在compose_mid文件夹下
def create_melody(melody):
    composer.set_melody(melody)


# 播放保存的mid文件
def play_music():
    if os.path.exists(os.path.join(composer.save_path, composer.name + '.mid')):
        composer.play_midi()


# mid转wav
def mid2wav():
    if os.path.exists(os.path.join(composer.save_path, composer.name + '.mid')):
        composer.transfer_wav()






def setname(request):
    # step 1. 设置乐曲名
    if(request.GET.get("title")):
        title = request.GET.get("title")
    else:
        title = "tmp"
    set_music_name(title)
    print("set:"+title)
    response = HttpResponse(json.dumps({"status": 1}), content_type="application/json")
    response["Access-Control-Allow-Origin"] = "*"
    response["Access-Control-Allow-Methods"] = "POST, GET, OPTIONS"
    response["Access-Control-Max-Age"] = "1000"
    response["Access-Control-Allow-Headers"] = "*"
    return response

def startrecord(request):
    # step 2. 开始录制
    start_record()
    print("start:"+music_name)
    print("1:"+os.path.abspath(os.path.dirname(__file__)))
    print("2:"+os.path.dirname(__file__))
    response = HttpResponse(json.dumps({"status": 1}), content_type="application/json")
    response["Access-Control-Allow-Origin"] = "*"
    response["Access-Control-Allow-Methods"] = "POST, GET, OPTIONS"
    response["Access-Control-Max-Age"] = "1000"
    response["Access-Control-Allow-Headers"] = "*"
    return response


def stoprecord(request):
    # step 3. 结束录制
    stop_record()
    print("stop:" + music_name)

    response = HttpResponse(json.dumps({"status": 1}), content_type="application/json")
    response["Access-Control-Allow-Origin"] = "*"
    response["Access-Control-Allow-Methods"] = "POST, GET, OPTIONS"
    response["Access-Control-Max-Age"] = "1000"
    response["Access-Control-Allow-Headers"] = "*"
    return response


def getmusic(request):
    # step 4. 音频转乐谱音符
    melody = get_notes()

    # step 5. 音符转乐器曲
    choose_program(0)  # 可以设置乐器
    create_melody(melody)

    response = HttpResponse(json.dumps({"status": 1}), content_type="application/json")
    response["Access-Control-Allow-Origin"] = "*"
    response["Access-Control-Allow-Methods"] = "POST, GET, OPTIONS"
    response["Access-Control-Max-Age"] = "1000"
    response["Access-Control-Allow-Headers"] = "*"
    return response


def playmusic(request):
    play_music()
    response = HttpResponse(json.dumps({"status": 1}), content_type="application/json")
    response["Access-Control-Allow-Origin"] = "*"
    response["Access-Control-Allow-Methods"] = "POST, GET, OPTIONS"
    response["Access-Control-Max-Age"] = "1000"
    response["Access-Control-Allow-Headers"] = "*"
    return response

def melody_note(request):
    return render(request, 'melody_note.html')

def homepage(request):
    return render(request, 'homepage.html')


def index(request):
    return render(request, 'index.html')


def dayin(request):
    ook("666")
    response = HttpResponse(json.dumps({"status": 1}), content_type="application/json")
    response["Access-Control-Allow-Origin"] = "*"
    response["Access-Control-Allow-Methods"] = "POST, GET, OPTIONS"
    response["Access-Control-Max-Age"] = "1000"
    response["Access-Control-Allow-Headers"] = "*"
    return response


def test(request):
    return render(request, 'test.html')