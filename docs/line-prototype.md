# 离线谱行跟随原型 0.4

曲库中导入 PDF 或照片，打开曲谱菜单，选择「谱行跟随原型（离线）」。首次准备前两页，后续页后台预备；页面、谱行与模型输入缓存在应用私有目录。无需联网识谱、MusicXML 或参考录音，模型随安装包提供。

检查框出的钢琴双谱表是否正确；从第一行开始，或点击当前谱行校准起点，再点击「开始监听」。连续五次定位（约半秒）确认相邻下一行后更新位置。确认进入最后一行时显示下一页，同时保留上一页末行；确认进入新页第二行后收起旧末行，也可手动收起。单行页面仅支持手动换页，避免连续误翻。

进入原型并完成初始化后自动监听；用户主动暂停、手动翻页和离开应用会停止监听，返回前台时尝试自动恢复。演奏静音或证据不足时保持位置，不应自行停止麦克风。手动翻页后自动关闭自动模式；点击实际谱行可重新校准。推理积压超过八帧会暂停，防止过期音频驱动翻页。音频只在内存中处理，不保存录音。原有 BPM 和 OMR 入口保留。

## 测试范围与限制

实验原型优先支持清晰、正向、竖版钢琴双谱表。模糊照片、歪斜、单谱表、标题页、复杂配器或错误行框可能无法准备。反复与跳奏需要手动定位，尚无自动识别任意起点和反复结构。行框可点击校准位置，当前不支持编辑检测边界。音量门限与顺序门限不能保证排除其他音乐。

先测试两页：正常演奏、放慢／加快、末行持续演奏、停顿、手动接管，再测试多页。观察定位是否逐行推进、末行触发时机、旧末行是否可读，以及推理耗时／积压。手机速度、真实音乐准确率和独立演奏的页间衔接仍需真机验证。

## 模型来源与复现

模型来自 [CPJKU/cyolo_score_following](https://github.com/CPJKU/cyolo_score_following)，固定提交 `4b34947a9b7cc19a139ce3768eac6079aaff5cfe` 的 `trained_models/cyolo_sb_a/best_model.pt`。MIT 许可随资产置于 `assets/line_model/LICENSE`，原始权重 SHA256 与配置记录在 metadata.json。没有上传用户曲谱或录音。

`scripts/export_line_models.py` 导出图像网络、流式音频上下文网络及原始滤波器。导出时已检查随机图像输入与 90 帧连续上下文的 PyTorch／ONNX 数值一致性；Dart 频谱与 PyTorch 固定输入对照通过。谱行检测、连续定位／静音／跳行门限和 PCM 分包测试在 `test/line_prototype_test.dart`，这些检查不等同于真机识别准确率。

运行使用 flutter_onnxruntime 1.9.0，CPU 推理，最低 iOS 16。Android APK 为测试用 debug 构建。

## Android 真机诊断（Windows）

在电脑安装 Android Platform Tools，手机打开 USB 调试并授权，然后执行：

```powershell
adb devices
adb logcat -c
adb logcat -v threadtime -s flutter:I flutter:D '*:S' > scoreturn-test.log
```

演奏结束后按 Ctrl+C，发送 `scoreturn-test.log`。专用日志前缀为 `SCORETURN_TRACE`，包括 `listener_start`、`listener_stop`、`audio_backlog_drop`、`row_confirmed`、`final_row_confirmed`、`page_turn`、`inference_error`；每条记录附带页码（从 0 开始）、行号（从 0 开始）、队列深度、丢帧数、音量及推理耗时。日志不包含录音。若没有输出，改用 `adb logcat -v threadtime > scoreturn-full.log` 收集完整日志。测试前注意清除旧日志，避免混入历史会话。

当前提交尚未经过 Flutter 编译、CI 和真机回归验证；自动恢复、积压处理及行号准确率仍需实际测试。
