import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:autoscore/core/start_detector.dart';

Uint8List pcm(double amplitude, int samples, {double freq = 440, int sampleRate = 22050}) {
  final data = ByteData(samples * 2);
  for (var i = 0; i < samples; i++) {
    final x = (32767 * amplitude * math.sin(2 * math.pi * freq * i / sampleRate)).round();
    data.setInt16(i * 2, x, Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  test('silent calibration never triggers', () {
    final d = AudioStartDetector();
    for (var i = 0; i < 120; i++) {
      expect(d.add(Uint8List(512)), isFalse);
    }
    expect(d.calibrated, isTrue);
    expect(d.started, isFalse);
  });

  test('sustained loud tone triggers only once', () {
    final d = AudioStartDetector();
    for (var i = 0; i < 64; i++) { d.add(Uint8List(512)); }
    var triggered = false;
    for (var i = 0; i < 20; i++) {
      if (d.add(pcm(0.15, 256))) triggered = true;
    }
    expect(triggered, isTrue);
    expect(d.add(pcm(0.2, 512)), isFalse);
  });

  test('odd PCM chunks preserve sample alignment', () {
    final d = AudioStartDetector();
    final signal = pcm(0.1, 21000);
    var triggered = false;
    for (var i = 0; i < signal.length; i += 77) {
      final n = math.min(signal.length, i + 77);
      if (d.add(Uint8List.sublistView(signal, i, n))) triggered = true;
    }
    // Calibration with a constantly loud tone raises the noise floor, so
    // it must not trigger merely because any sound exists.
    expect(triggered, isFalse);
  });
}
