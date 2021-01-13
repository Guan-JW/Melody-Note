"""melody_note URL Configuration

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/3.1/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import path
from melody_note import views
from melody_note import work
from melody_note.work.sound_recorder import record


urlpatterns = [
    path('melody_note/', views.melody_note),
    path('homepage/', views.homepage),
    path('index/', views.index),
    path('get_notes/', views.get_notes),
    path('test/',views.test),
    path('print/', views.dayin),
    path('set_name/' ,views.setname),
    path('start_record/', views.startrecord),
    path('stop_record/', views.stoprecord),
    path('get_music/', views.getmusic),
    path('play_music/', views.playmusic),
]


# python manage.py migrate  先执行这个