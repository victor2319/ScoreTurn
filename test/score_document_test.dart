import 'package:flutter_test/flutter_test.dart';
import 'package:autoscore/core/score_document.dart';

Map<String, dynamic> fixture() => {
  'version': 1,
  'reviewed': false,
  'pages': [
    {'width': 1000, 'height': 2000},
    {'width': 1000, 'height': 2000},
  ],
  'measures': List.generate(
    4,
    (i) => {
      'id': i,
      'label': '${i + 1}',
      'page': i ~/ 2,
      'beats': 4,
      'box': [0.1, 0.1 + (i % 2) * 0.3, 0.9, 0.3 + (i % 2) * 0.3],
      'events': [
        {
          'beat': 0,
          'duration': 1,
          'pitches': [60 + i],
        },
      ],
    },
  ),
  'order': [0, 1, 2, 3],
  'turnAfter': [0, null],
  'warnings': [],
  'musicXml': '<score-partwise/>',
};
void main() {
  test('document round trip preserves score and original coordinates', () {
    final d = ScoreDocument.fromJson(fixture());
    expect(ScoreDocument.fromJson(d.toJson()).measures[2].page, 1);
    expect(d.measures[0].box, [0.1, 0.1, 0.9, 0.3]);
    expect(d.ready, false);
    d.reviewed = true;
    expect(d.ready, true);
  });
  test('out of image bounds and nonexistent order are rejected', () {
    final invalid = fixture();
    (invalid['measures'] as List)[0]['box'] = [-0.1, 0.1, 1.0, 0.5];
    expect(() => ScoreDocument.fromJson(invalid), throwsFormatException);
    invalid['measures'] = fixture()['measures'];
    invalid['order'] = [99];
    expect(() => ScoreDocument.fromJson(invalid), throwsFormatException);
  });
  test('turn point must belong to its page', () {
    final invalid = fixture()..['turnAfter'] = [2, null];
    expect(() => ScoreDocument.fromJson(invalid), throwsFormatException);
  });
  test('complex navigation requires manual order', () {
    final d = ScoreDocument.fromJson(fixture()..['order'] = [])
      ..reviewed = true;
    expect(d.ready, false);
    d.order = [0, 1, 0, 1, 2, 3];
    expect(d.ready, true);
  });
  test('nonfinite duration and out of range pitch rejected', () {
    final invalid = fixture();
    invalid['measures'][0]['events'][0]['duration'] = double.nan;
    expect(() => ScoreDocument.fromJson(invalid), throwsFormatException);
    invalid['measures'][0]['events'][0]['duration'] = 1;
    invalid['measures'][0]['events'][0]['pitches'] = [128];
    expect(() => ScoreDocument.fromJson(invalid), throwsFormatException);
  });
}
