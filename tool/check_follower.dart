import '../lib/core/score_document.dart';
import '../lib/core/score_follower.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

List<double> tone(int pitch) =>
    List.generate(12, (i) => i == pitch % 12 ? 1.0 : 0.0);
void main() {
  final doc = ScoreDocument(
    pages: [const PageGeometry(100, 200), const PageGeometry(100, 200)],
    measures: List.generate(
      4,
      (i) => RecognizedMeasure(
        id: i,
        label: '${i + 1}',
        page: i ~/ 2,
        beats: 4,
        box: [0.1, 0.1, 0.9, 0.4],
        events: [
          ScoreEvent(0, 1, [60 + i * 2]),
        ],
      ),
    ),
    order: [0, 1, 2, 3],
    turnAfter: [0, null],
    warnings: [],
    musicXml: '',
    reviewed: true,
  );
  final f = ScoreFollower(doc);
  for (var i = 0; i < 5; i++) {
    f.add(tone(60), rms: 0.1, onset: i == 0);
  }
  check(f.locked && f.measureId == 0, 'acquire first measure');
  for (var i = 0; i < 100; i++) {
    f.add(tone(60), rms: 0.1);
  }
  check(f.measureId == 0, 'sustained note must not advance by time');
  for (final pitch in [62, 64, 66]) {
    for (var i = 0; i < 6; i++) {
      f.add(tone(pitch), rms: 0.1, onset: i == 0);
    }
  }
  check(f.measureId == 3, 'follow changed notes at arbitrary tempo');
  f.add(List.filled(12, 0), rms: 0);
  check(!f.locked && f.measureId == 3, 'silence holds position');
  f.seek(1);
  check(f.measureId == 1 && !f.locked, 'manual seek clears confidence');
  for (var i = 0; i < 8; i++) {
    f.add(List.filled(12, 1), rms: 0.1);
  }
  check(!f.locked && f.measureId == 1, 'broadband noise holds position');
  final repeated = ScoreDocument.fromJson(doc.toJson());
  repeated.measures[1].events[0].pitches[0] = 60;
  final r = ScoreFollower(repeated);
  for (var i = 0; i < 20; i++) {
    r.add(tone(60), rms: 0.1, onset: i == 0);
  }
  check(r.measureId == 0, 'same pitch sustain cannot cross a repeated note');
  print(
    'Follower variable tempo/sustain/silence/noise/manual seek checks passed',
  );
}
