#!/usr/bin/env python3
"""Idempotently configure Flutter-generated Android/iOS apps for offline mic use."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT / 'android/app/src/main/AndroidManifest.xml'
IOS = ROOT / 'ios/Runner/Info.plist'
IOS_PODFILE = ROOT / 'ios/Podfile'
IOS_PROJECT = ROOT / 'ios/Runner.xcodeproj/project.pbxproj'
IOS_FRAMEWORK = ROOT / 'ios/Flutter/AppFrameworkInfo.plist'


def configure_android(path: Path):
    s = path.read_text(encoding='utf-8')
    required = '<uses-permission android:name="android.permission.RECORD_AUDIO" />'
    if required not in s:
        s = re.sub(r'(<manifest\b[^>]*>)', r'\1\n    ' + required, s, count=1)
    # Network is used only by the explicit photo-import action. Performance
    # analysis and score following have no networking dependencies.
    network = '<uses-permission android:name="android.permission.INTERNET" />'
    if network not in s:
        s = re.sub(r'(<manifest\b[^>]*>)', r'\1\n    ' + network, s, count=1)
    s = re.sub(r'android:label="[^"]*"', 'android:label="AutoScore"', s, count=1)
    path.write_text(s, encoding='utf-8')


def configure_ios(path: Path):
    s = path.read_text(encoding='utf-8')
    if 'NSMicrophoneUsageDescription' not in s:
        s = s.replace('</dict>',
            '    <key>NSMicrophoneUsageDescription</key>\n'
            '    <string>用于在本机分析钢琴演奏并跟随曲谱，音频不会上传。</string>\n'
            '</dict>', 1)
    if '<key>CFBundleDisplayName</key>' not in s:
        s = s.replace('</dict>',
            '    <key>CFBundleDisplayName</key>\n'
            '    <string>AutoScore</string>\n'
            '</dict>', 1)
    path.write_text(s, encoding='utf-8')


def main():
    if not ANDROID.exists() or not IOS.exists():
        raise SystemExit('缺少 android/ios 平台工程。请先执行 flutter create --platforms=android,ios .')
    configure_android(ANDROID)
    configure_ios(IOS)
    # The local ONNX Runtime plugin requires iOS 16+.
    if IOS_PODFILE.exists():
        pod = IOS_PODFILE.read_text(encoding='utf-8')
        pod = re.sub(r"^#?\s*platform :ios, ['\"]\d+(?:\.\d+)*['\"]",
                     "platform :ios, '16.0'", pod, flags=re.MULTILINE)
        if "platform :ios" not in pod:
            pod = "platform :ios, '16.0'\n" + pod
        IOS_PODFILE.write_text(pod, encoding='utf-8')
    if IOS_PROJECT.exists():
        project = IOS_PROJECT.read_text(encoding='utf-8')
        project = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;',
                         'IPHONEOS_DEPLOYMENT_TARGET = 16.0;', project)
        IOS_PROJECT.write_text(project, encoding='utf-8')
    if IOS_FRAMEWORK.exists():
        info = IOS_FRAMEWORK.read_text(encoding='utf-8')
        info = re.sub(r'(<key>MinimumOSVersion</key>\s*<string>)[0-9.]+(</string>)',
                      r'\g<1>16.0\g<2>', info)
        IOS_FRAMEWORK.write_text(info, encoding='utf-8')
    print('Android mic permission + iOS mic description configured. Network permission for explicit photo recognition only.')


if __name__ == '__main__':
    main()
