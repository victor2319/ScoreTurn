import 'package:flutter_test/flutter_test.dart';

import '../tool/check_document.dart' as document;
import '../tool/check_follower.dart' as follower;
import '../tool/check_chroma.dart' as chroma;

import '../tool/check_recognition_cancel.dart' as cancel;

void main() {
  test('cancel during preload prevents upload', cancel.main);
  test('document validation and persistence contract', document.main);
  test(
    'variable tempo, silence, sustain, noise and manual correction',
    follower.main,
  );
  test('real PCM framing, spectral A4 and silence', chroma.main);
}
