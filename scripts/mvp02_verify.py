#!/usr/bin/env python3
"""Offline source checks. Does not compile Dart or claim a real device test."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
checks = {}

def check(name, condition):
    checks[name] = bool(condition)
    if not condition:
        print('FAIL', name)
    else:
        print('PASS', name)

library = (root/'lib/ui/library_screen.dart').read_text()
reader = (root/'lib/ui/reader_screen.dart').read_text()
policy = (root/'lib/core/turn_policy.dart').read_text()
mic = (root/'lib/core/microphone.dart').read_text()
log = (root/'lib/core/session_log.dart').read_text()
check('file_picker 13 compatibility: removed allowMultiple', 'allowMultiple:' not in library)
check('file_picker 13 readAsBytes', 'readAsBytes()' in library)
check('crossing-only page turn', 'last < trigger' in policy and 'measure - last <= 1' in policy)
check('manual seek resets policy', reader.count('_policy.reposition(') >= 5)
check('manual BPM adjustment', '_clock.setTempo(next)' in reader)
check('real photo next-page thumbnail', 'Image.file(File(_score.localPaths[upcoming])' in reader)
check('event logs no PCM recordings', "'audioStored': false" in log and 'chunk' not in log.lower())
check('microphone cancel generation guard', 'generation != _generation' in mic)
check('full offline code', all('http://' not in p.read_text() and 'https://' not in p.read_text() for p in (root/'lib').rglob('*.dart')))
check('iOS 14 minimum configured', "'14.0'" in (root/'scripts/configure_platforms.py').read_text())
check('new Dart policy tests included', (root/'test/turn_policy_test.dart').is_file())
check('event log tests included', (root/'test/session_log_test.dart').is_file())
check('Android and iOS CI', 'flutter build apk --debug' in (root/'.github/workflows/build.yml').read_text() and 'flutter build ios --no-codesign' in (root/'.github/workflows/build.yml').read_text())
check('demo pages present', all((root/f'assets/demo/page_{i}.jpg').stat().st_size>100000 for i in [88,89]))
checks['platform XML test'] = subprocess.run([sys.executable,str(root/'scripts/test_platform_config.py')],capture_output=True).returncode == 0
check('platform XML test', checks['platform XML test'])
checks['legacy source check'] = subprocess.run([sys.executable,str(root/'scripts/static_check.py')],capture_output=True).returncode == 0
check('legacy source check',checks['legacy source check'])
passed=sum(checks.values())
print(f'{passed}/{len(checks)} checks passed (static/structure only)')
if not all(checks.values()):sys.exit(1)
