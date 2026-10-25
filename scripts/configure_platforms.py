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
    # Explicitly disallow network in RELEASE. Packages must not inject it.
    # Generated debug/profile manifests may have INTERNET for Flutter tooling.
    if 'android.permission.INTERNET' in s:
        raise RuntimeError('Unexpected INTERNET permission in main manifest')
    s = re.sub(r'android:label="[^"]*"', 'android:label="AutoScore"', s, count=1)
    path.write_text(s, encoding='utf-8')


def configure_ios(path: Path):
    s = path.read_text(encoding='utf-8')
    if 'NSMicrophoneUsageDescription' not in s:
        s = s.replace('</dict>',
            '    <key>NSMicrophoneUsageDescription</key>\n'
            '    <string>用于检测钢琴演奏开始，音频仅在本机处理。</string>\n'
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
    # file_picker 13 uses PHPickerViewController on iOS and requires iOS 14+.
    if IOS_PODFILE.exists():
        pod = IOS_PODFILE.read_text(encoding='utf-8')
        pod = re.sub(r"^#?\s*platform :ios, ['\"]\d+(?:\.\d+)*['\"]",
                     "platform :ios, '14.0'", pod, flags=re.MULTILINE)
        if "platform :ios" not in pod:
            pod = "platform :ios, '14.0'\n" + pod
        IOS_PODFILE.write_text(pod, encoding='utf-8')
    if IOS_PROJECT.exists():
        project = IOS_PROJECT.read_text(encoding='utf-8')
        project = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;',
                         'IPHONEOS_DEPLOYMENT_TARGET = 14.0;', project)
        IOS_PROJECT.write_text(project, encoding='utf-8')
    if IOS_FRAMEWORK.exists():
        info = IOS_FRAMEWORK.read_text(encoding='utf-8')
        info = re.sub(r'(<key>MinimumOSVersion</key>\s*<string>)[0-9.]+(</string>)',
                      r'\g<1>14.0\g<2>', info)
        IOS_FRAMEWORK.write_text(info, encoding='utf-8')
    print('Android mic permission + iOS mic description configured. No release INTERNET permission.')


if __name__ == '__main__':
    main()
