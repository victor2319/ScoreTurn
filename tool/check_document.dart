import '../lib/core/score_document.dart';

void check(bool condition) {
  if (!condition) throw StateError('Check failed');
}

void main() {
  final document = ScoreDocument(
    pages: [const PageGeometry(1000, 2000)],
    measures: [
      RecognizedMeasure(
        id: 0,
        label: '1',
        page: 0,
        beats: 4,
        box: [0.1, 0.1, 0.9, 0.3],
        events: [
          const ScoreEvent(0, 1, [60, 64, 67]),
        ],
      ),
    ],
    order: [0],
    turnAfter: [null],
    warnings: [],
    musicXml: '<score-partwise/>',
  );
  check(!document.ready);
  document.reviewed = true;
  check(ScoreDocument.fromJson(document.toJson()).ready);
  for (final box in [
    [-0.1, 0.1, 0.9, 0.3],
    [0.9, 0.1, 0.1, 0.3],
    [0.1, double.nan, 0.9, 0.3],
  ]) {
    document.measures[0].box = box;
    try {
      document.validate();
      throw StateError('Invalid bounds accepted');
    } on FormatException {
      /* Expected. */
    }
  }
  print('Document round-trip/readiness/bounds checks passed');
}
