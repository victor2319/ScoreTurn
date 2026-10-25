"""Offline source-package consistency checks, not a replacement for flutter test."""
import re
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
files = list((ROOT / 'lib').rglob('*.dart'))
assert len(files) >= 8, len(files)
alltext = '\n'.join(f.read_text() for f in files)
performance = '\n'.join((ROOT / p).read_text() for p in ['lib/core/chroma.dart', 'lib/core/score_follower.dart', 'lib/ui/follow_screen.dart'])
assert 'HttpClient' not in performance and 'https://' not in performance, 'Network in performance path'
assert 'AudioEncoder.pcm16bits' in alltext
assert 'PdfDocument.openFile' in alltext
assert 'FilePicker.pickFiles' in alltext
assert 'WakelockPlus.enable' in alltext
assert 'advanceMeasures' in alltext
assert 'lastMeasureByPage' in alltext
assert (ROOT / 'assets/demo/page_88.jpg').stat().st_size > 100_000
assert (ROOT / 'assets/demo/page_89.jpg').stat().st_size > 100_000
assert 'android.permission.INTERNET' in (ROOT / 'scripts/configure_platforms.py').read_text()
assert (ROOT / 'test/score_test.dart').exists()
assert (ROOT / 'test/start_detector_test.dart').exists()
print(f'PASS: {len(files)} Dart source files, two demo pages, offline dependency design, platform config and tests present.')
