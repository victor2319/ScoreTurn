// ignore_for_file: avoid_relative_lib_imports, avoid_print
import '../lib/core/line_following/line_gate.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  final g = LineGate(3, stableFrames: 3);
  for (var i = 0; i < 10; i++) {
    check(!g.add(2, audioValid: true), 'skip cannot trigger');
  }
  for (final row in [0, 1]) {
    for (var i = 0; i < 3; i++) {
      check(!g.add(row, audioValid: true), 'early turn');
    }
  }
  check(!g.add(2, audioValid: true), 'needs stability');
  check(!g.add(2, audioValid: false), 'silence clears evidence');
  check(!g.add(2, audioValid: true), 'start over');
  check(!g.add(2, audioValid: true), 'still building');
  check(g.add(2, audioValid: true), 'stable final row');
  check(!g.add(2, audioValid: true), 'one turn per page');
  g.seek(1);
  for (var i = 0; i < 2; i++) {
    check(!g.add(2, audioValid: true), 'seek resets');
  }
  check(g.add(2, audioValid: true), 'seek resumes after stability');
  print('PASS sequential/stability/silence/seek/one-turn gate');
}
