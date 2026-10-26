import 'package:flutter_test/flutter_test.dart';

import '../tool/check_line_gate.dart' as gate;
import '../tool/check_line_layout.dart' as layout;
import '../tool/check_line_spectrum.dart' as spectrum;

void main() {
  test('sequential stable final-line trigger and manual correction', gate.main);
  test('automatic staff pairing and blank-page rejection', layout.main);
  test(
    'exact model spectrum and arbitrarily split microphone PCM',
    spectrum.main,
  );
}
