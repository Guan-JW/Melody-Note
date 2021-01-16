# Melody-Note

灵感稍纵即逝，本项目的目标是能够记录下一段小调，以音频形式输入，读取识别其曲调，并制成谱子，最终以钢琴弹奏的形式输出，依此将一些日常生活中的小灵感保存起来，以便日后回忆甚至再创作。

项目实现使用 `python3.7` , `django`, `lilypond`，`midi`。

1. python manage.py runserver 0.0.0.0:8080 运行 `django` 项目后打开http://127.0.0.1:8080/index/

2. 点击“打开录音”按钮，获得录音权限；

3. 点击“录制”按钮，开始录音，“停止”按钮停止录音；

4. 点击“生成音乐”，需要稍等一下哦，可在后台查看是否转换完毕；

5. 点击“播放”按钮即可听到钢琴曲；

6. 有关保存文件请查看 `work` 文件夹下的 `说明.txt`。

   ![page.png](https://github.com/Guan-JW/Melody-Note/blob/main/pics/page.png?raw=true)