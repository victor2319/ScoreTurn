// Standalone SDK checks also run without a Flutter package configuration.
// ignore_for_file: avoid_relative_lib_imports, avoid_print
import 'dart:io';

import '../lib/core/recognition_client.dart';
import '../lib/core/score.dart';

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('scoreturn-cancel-');
  var createdClient = false;
  try {
    final file = File('${dir.path}/page.jpg');
    await file.writeAsBytes([1, 2, 3]);
    final score = Score(
      id: 'cancel-test',
      title: 'Cancel test',
      isPdf: false,
      localPaths: [file.path],
      pageCount: 1,
      firstMeasure: 1,
      lastMeasureByPage: [1],
      beatsPerMeasure: 4,
      bpm: 120,
      advanceMeasures: 2,
    );
    await HttpOverrides.runZoned(
      () async {
        final client = RecognitionClient();
        final future = client.recognize(
          score,
          'https://example.invalid/recognize',
          'test',
        );
        client.cancel(); // Runs while the first asynchronous file read is pending.
        Object? failure;
        try {
          await future;
        } catch (e) {
          failure = e;
        }
        if (createdClient) {
          throw StateError('Canceled import still created an HTTP client');
        }
        if (failure == null || !failure.toString().contains('已取消')) {
          throw StateError('Expected explicit cancellation, got $failure');
        }
      },
      createHttpClient: (_) {
        createdClient = true;
        throw StateError('Network forbidden by this test');
      },
    );
  } finally {
    await dir.delete(recursive: true);
  }
  print('Cancel during photo preload prevents all HTTP activity');
}
