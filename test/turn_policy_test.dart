import 'package:flutter_test/flutter_test.dart';
import 'package:autoscore/core/score.dart';
import 'package:autoscore/core/turn_policy.dart';

void main() {
  const score = Score(
    id: 'x', title: 'Test', isPdf: false,
    localPaths: ['1.jpg', '2.jpg', '3.jpg'], pageCount: 3,
    firstMeasure: 1, lastMeasureByPage: [19, 35, 50],
    beatsPerMeasure: 4, bpm: 155, advanceMeasures: 2,
  );

  test('preview at 17, turn at crossing 17 -> 18', () {
    final p = TurnPolicy(score)..reset(currentMeasure: 1, currentPage: 0);
    for (var m = 2; m <= 16; m++) {
      expect(p.update(measure: m, page: 0, running: true,
          automaticEnabled: true).turnPage, false);
    }
    final preview = p.update(measure: 17, page: 0,
        running: true, automaticEnabled: true);
    expect(preview.previewNext, true);
    expect(preview.turnPage, false);
    final crossed = p.update(measure: 18, page: 0,
        running: true, automaticEnabled: true);
    expect(crossed.turnPage, true);
    expect(p.update(measure: 18, page: 1,
        running: true, automaticEnabled: true).turnPage, false);
  });

  test('seek crossing, skipped boundary and resume never autorun', () {
    final p = TurnPolicy(score)..reset(currentMeasure: 15, currentPage: 0);
    p.reposition(measure: 18, page: 0); // user explicitly seeks here
    expect(p.update(measure: 18, page: 0, running: true,
        automaticEnabled: true).turnPage, false);
    p.reposition(measure: 14, page: 0);
    expect(p.update(measure: 25, page: 0, running: true,
        automaticEnabled: true).turnPage, false); // jump > 1 measure
    p.reposition(measure: 17, page: 0);
    expect(p.update(measure: 18, page: 0, running: false,
        automaticEnabled: true).turnPage, false);
    p.reposition(measure: 18, page: 0);
    expect(p.update(measure: 18, page: 0, running: true,
        automaticEnabled: true).turnPage, false);
  });

  test('disabled automation cannot backlog a flip', () {
    final p = TurnPolicy(score)..reset(currentMeasure: 17, currentPage: 0);
    expect(p.update(measure: 18, page: 0, running: true,
        automaticEnabled: false).turnPage, false);
    p.reposition(measure: 18, page: 0);
    expect(p.update(measure: 18, page: 0, running: true,
        automaticEnabled: true).turnPage, false);
  });
}
