#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v flutter >/dev/null; then
  echo '未找到 Flutter SDK。请先安装当前稳定版 Flutter 并运行 flutter doctor。' >&2
  exit 1
fi
# Generates platform scaffolding without overwriting existing app code.
flutter create --project-name autoscore --org app.autoscore --platforms=android,ios .
# Flutter's default widget_test.dart targets the template MyApp, not AutoScore.
# Remove only the untouched generated template test, if present.
if [[ -f test/widget_test.dart ]] && grep -q 'MyApp' test/widget_test.dart; then
  rm test/widget_test.dart
fi
python3 scripts/configure_platforms.py
flutter pub get
flutter test
printf '\n已完成工程初始化与 Flutter 单元测试。使用 flutter devices 查看设备，然后 flutter run。\n'
