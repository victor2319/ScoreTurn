// Standalone SDK checks also run without a Flutter package configuration.
// ignore_for_file: avoid_relative_lib_imports, avoid_print
import 'dart:math' as math;
import 'dart:typed_data';

import '../lib/core/chroma.dart';

void main() {
  final bytes = Uint8List(22050 * 2);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < 22050; i++) {
    data.setInt16(
      i * 2,
      (12000 * math.sin(2 * math.pi * 440 * i / 22050)).round(),
      Endian.little,
    );
  }
  final frames = <AudioFeature>[];
  final extractor = ChromaExtractor(frames.add);
  // Odd packet boundaries must preserve signed PCM16 sample alignment.
  for (var i = 0; i < bytes.length; i += 777) {
    extractor.add(
      Uint8List.sublistView(bytes, i, math.min(i + 777, bytes.length)),
    );
  }
  if (frames.length < 8) throw StateError('Too few frames');
  final c = frames.last.chroma;
  if (c.indexOf(c.reduce(math.max)) != 9) {
    throw StateError('A4 not recognized: $c');
  }
  extractor.add(Uint8List(22050 * 2));
  if (frames.last.rms != 0) throw StateError('Silence not detected');
  print(
    'PCM framing/A4 chroma/silence checks passed (${frames.length} frames)',
  );
}
