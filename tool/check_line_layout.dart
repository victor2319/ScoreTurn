// ignore_for_file: avoid_relative_lib_imports, avoid_print
import 'dart:typed_data';

import '../lib/core/line_following/line_layout.dart';

void main() {
  final gray = Uint8List(835 * 1181)..fillRange(0, 835 * 1181, 255);
  for (final top in [100, 240, 600, 740]) {
    for (var line = 0; line < 5; line++) {
      for (var x = 60; x < 780; x++) {
        gray[(top + line * 10) * 835 + x] = 0;
      }
    }
  }
  final p = LineLayout.prepare(gray);
  if (p.rows.length != 2) {
    throw StateError('Expected two paired systems, got ${p.rows.length}');
  }
  if (p.pixels.length != 416 * 416) throw StateError('Wrong image tensor');
  if (p.rows[0].top > 100 / 1181 || p.rows[0].bottom < 280 / 1181) {
    throw StateError('Wrong bounds');
  }
  try {
    LineLayout.prepare(Uint8List(835 * 1181)..fillRange(0, 835 * 1181, 255));
    throw StateError('Blank accepted');
  } on FormatException {
    /* Expected. */
  }
  print(
    'PASS staff pairing, normalized bounds, model tensor and blank rejection',
  );
}
