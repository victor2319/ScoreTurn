// Standalone SDK checks also run without a Flutter package configuration.
// ignore_for_file: avoid_relative_lib_imports, avoid_print
import 'dart:math' as math;
import 'dart:typed_data';

import '../lib/core/chroma.dart';
import '../lib/core/score_document.dart';
import '../lib/core/score_follower.dart';

void main() {
  checkAudioFollowing();
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

// End-to-end DSP -> follower check with harmonics and nonuniform note lengths.
void checkAudioFollowing() {
  final pitches = [60, 62, 64, 65];
  final document = ScoreDocument(
    pages: [const PageGeometry(100, 200)],
    measures: List.generate(
      4,
      (i) => RecognizedMeasure(
        id: i,
        label: '${i + 1}',
        page: 0,
        beats: 4,
        box: [0.1, 0.1, 0.9, 0.3],
        events: [
          ScoreEvent(0, 1, [pitches[i]]),
        ],
      ),
    ),
    order: [0, 1, 2, 3],
    turnAfter: [null],
    warnings: [],
    musicXml: '',
    reviewed: true,
  );
  final follower = ScoreFollower(document);
  final extractor = ChromaExtractor(
    (frame) => follower.add(frame.chroma, rms: frame.rms, onset: frame.onset),
  );
  for (var note = 0; note < pitches.length; note++) {
    final count = ([0.8, 1.3, 0.6, 1.0][note] * 22050).round();
    final pcm = Uint8List(count * 2);
    final samples = ByteData.sublistView(pcm);
    final frequency = 440 * math.pow(2, (pitches[note] - 69) / 12);
    for (var i = 0; i < count; i++) {
      final phase = 2 * math.pi * frequency * i / 22050;
      final signal =
          math.sin(phase) +
          0.3 * math.sin(2 * phase) +
          0.12 * math.sin(3 * phase);
      samples.setInt16(i * 2, (9000 * signal).round(), Endian.little);
    }
    extractor.add(pcm);
    if (!follower.locked || follower.measureId != note) {
      throw StateError(
        'PCM following failed at note $note: position ${follower.measureId}',
      );
    }
    extractor.add(Uint8List(4410));
  }
  print('End-to-end PCM harmonic/variable-tempo following passed');
}
