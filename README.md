# AutoScore MVP-02 · iOS / Android 离线翻谱开发版

**交付状态：Flutter 工程源码及自动构建流程已更新；尚未在本环境编译成 APK / IPA，尚未进行 Android/iOS 真机测试。**

在 MVP-01 的基础上，这一版优先修复工程真实使用和构建风险，而不是声称已移植 POC-24 的复杂声学定位算法。

## 本版新内容

1. **修复 `file_picker` 13.x API 兼容性**：删除已被移除的 `allowMultiple` 参数（原代码会导致编译错误）。
2. **抽出 `TurnPolicy` 翻页决策器**，只允许顺序演奏跨过触发小节时翻页。手动小节跳转、暂停恢复、手动翻页、速度设置后不允许“补偿性突然翻页”；禁止跳跃多小节自动翻页。
3. **可视化下一页预览**：导入的图片曲谱在预备阶段展示下一页小缩略图，当前正在演奏的页面保持可见；PDF 下一页目前只提供文字提示，PDF 缩略图渲染还未移植。
4. **随时调整速度**：演奏中 BPM ±5，使用 `Stopwatch` 保持已累计的拍数，不会重置歌曲进度。注意并非自动感知 Rubato。
5. **本地诊断日志**：记录开始／暂停／翻页／速度调整／中断／手动定位，保存 JSONL 于应用私有 `Documents/autoscore/diagnostics/`，工具栏可一键复制；**不储存音频 PCM、乐谱图像或位置信息**。录音音频只在内存中做简单振幅判断。
6. **麦克风取消竞态保护**：用户在请求权限期间退出或取消监听，不再允许迟到的授权结果自动重新开始录制。
7. **平台配置**：保留 Android `RECORD_AUDIO`、无主程序 INTERNET 权限，iOS 麦克风用途说明。设置 iOS 最低支持版本 14.0（按 file_picker 13.x 要求）。
8. **Flutter 单元测试和 CI**：增加翻页边界、手动跳转、禁用自动、日志格式等测试；增加 GitHub Actions 的 Android Debug APK 和 iOS 无签名构建工作流。Flutter CLI 仍需生成原生脚手架。
9. **优化资源**：仅演奏计时期间每 100ms 刷新，不在暂停时空转重绘；小屏按键自动换行。

## 原本保留的功能

- Flutter / Dart，iOS 和 Android 共用界面；平板优先。
- 本机 PDF、PNG、JPEG、WEBP 曲谱导入；曲库与每页最后小节的配置本地保存。
- 公开仓库内置两张通用测试占位页，不包含用户提供的曲谱照片；占位页没有可供演奏的音符。可通过导入功能在本机使用自己的乐谱。
- 音频 `record` 插件采集 22,050 Hz mono PCM16，校准环境声后用音量触发节拍时钟。
- 可手动开始、停止、暂停、恢复和前后翻页；屏幕常亮。
- 4/4（可设定每小节拍数）+ BPM 按小节计时；默认提前小节触发的 **实验性自动翻页**。
- 运行时无云端推理、网络 API、帐号或同步。

## 快速开始：Android

需 Linux / Windows / macOS + Flutter Stable + Android SDK + JDK。

```bash
unzip autoscore_mvp02_source.zip
cd autoscore_mvp02
flutter doctor
bash scripts/bootstrap.sh
flutter analyze
flutter test
flutter devices
flutter run -d <ANDROID_DEVICE_ID>
flutter build apk --debug
```

运行 `bash scripts/bootstrap.sh` 会生成 `android/` 和 `ios/`（不会覆盖 `lib/` 源码）、注入麦克风权限并运行 Dart 测试。

APK 如成功构建，路径为 `build/app/outputs/flutter-apk/app-debug.apk`。**此包并未随当前交付预生成。**

## 快速开始：iOS

需要 macOS + Xcode；不能在 Linux 直接打包 IPA。

```bash
bash scripts/bootstrap.sh
flutter analyze
flutter test
flutter build ios --no-codesign --debug
```

真机安装需要配置 Apple 开发签名，使用 Xcode 或 `flutter run`。

## 可选：无需本地安装 SDK 的 CI 构建

将源码上传至 GitHub 仓库（公开版本仅含测试占位页），启用 Actions，手动运行 `AutoScore CI` 或推送提交。工作流在 GitHub 提供的机器上联网获取 Flutter SDK / 依赖，运行 `flutter analyze`、`flutter test`、构建 Android Debug APK，并在 macOS 上尝试 iOS 无签名编译。成功后 Android APK 可从 workflow Artifacts 下载。**CI 还未真正跑过，不保证第一次构建通过**。CI 环境需要联网，但**演奏时 App 不需要联网**。

用户上传的曲谱照片只授权用于当前研发验证，**不要直接放在公共 GitHub 仓库或发布的 App 中**，除非确认图像版权与许可。

## 实际试弹检查（首次真机阶段）

1. 安装测试 App，首次启动可查看两张测试占位页；关闭设备网络验证本机资源正常。
2. 手动翻两页、放大缩小；在设置中确认第 1 页最后小节 `19`、第二页 `40` 仅为占位标注。
3. 将预设 BPM 设为 155，选择 `手动开始`，查看预设在第 17 小节出现图片预览、第 18 小节自动翻页。理论时间分别约 **24.77 秒 / 26.32 秒**（从第 1 小节起按 4/4、155 BPM）。
4. 重新启动监听：先允许 0.6 秒环境噪声校准，再弹第一个强起音，验证开始检测。**这是音量门控，不保证一定检测正确的第一个小节。**
5. 演奏时调 BPM ±5，看计时是否连续；测试手动翻页暂停自动、恢复自动、手动校正小节和后台中断。
6. 点工具栏“复制日志”，复制 JSONL 并检查是否有 `microphone_start`、`automatic_page` 等事件。注意日志不包含实际 PCM 音频。

## 关键限制和下一步

- **尚未实现**：真正的和声确认、直接从图片识别音符、动态跟谱、PDF 下一页图像缩略图、自动识别任意拍号及不同小节拍数、长停顿自动跟谱恢复、端到端音频延迟验证。默认翻页仍是按 BPM 定时，因此不适合未经排练用于正式音乐会。
- **仍未运行**：本环境没有 Dart / Flutter / Android SDK 且不能下载，所以无法完成 `flutter analyze`、`flutter test`、APK / IPA 构建。离线 Python 静态检查通过不等于 Flutter 编译通过。
- 下一阶段：Android 真机测试 PCM 流起奏延迟、计时漂移和设备差异，然后移植 POC-24 的和声确认算法，并执行 iOS 真机测试。

## 本地源码检查（不需要 Flutter SDK）

```bash
python3 scripts/mvp02_verify.py
```

独立运行单元测试仍需 `flutter test`。本项目当前只有 Flutter 应用源码和自动脚手架工具，不含预编译原生平台工程。
