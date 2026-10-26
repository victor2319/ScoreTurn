// ignore_for_file: avoid_relative_lib_imports, avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../lib/core/line_following/line_spectrum.dart';

void main() {
  final bankBytes = File('assets/line_model/filterbank.f32').readAsBytesSync();
  final bank = Float32List.view(
    bankBytes.buffer,
    bankBytes.offsetInBytes,
    1025 * 78,
  );
  final frames = <LineAudioFrame>[];
  final extractor = LineSpectrum(bank, frames.add);
  final samples = Float32List.fromList(
    List.generate(
      2048,
      (i) => (9000 * math.sin(2 * math.pi * 440 * i / 22050)).round() / 32768,
    ),
  );
  final actual = extractor.analyze(samples);
  final expected = (jsonDecode(
    File('test/fixtures/line_spectrum_expected.json').readAsStringSync(),
  ) as List).cast<num>();
  for (var i = 0; i < 78; i++) {
    if ((actual.features[i] - expected[i]).abs() > 0.0002) {
      throw StateError('Spectrum mismatch band $i');
    }
  }
  final bytes = Uint8List(4096), view = ByteData(4096);
  for (var i = 0; i < 2048; i++) {
    view.setInt16(i * 2, (samples[i] * 32768).round(), Endian.little);
  }
  bytes.setAll(0, view.buffer.asUint8List());
  for (var i = 0; i < bytes.length; i += 777) {
    extractor.add(
      Uint8List.sublistView(bytes, i, math.min(bytes.length, i + 777)),
    );
  }
  if (frames.length != 1) throw StateError('PCM alignment/frame count failed');
  print('PASS exact PyTorch spectrum parity and odd PCM packet framing');
}
