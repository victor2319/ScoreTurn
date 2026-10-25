import 'package:flutter_test/flutter_test.dart';
import 'package:autoscore/core/score.dart';
import 'package:autoscore/core/clock.dart';

void main() {
  const sample = Score(
    id: 'one', title: 'Waldstein', isPdf: false,
    localPaths: ['a.jpg', 'b.jpg'], pageCount: 2,
    firstMeasure: 1, lastMeasureByPage: [19, 40],
    beatsPerMeasure: 4, bpm: 155, advanceMeasures: 2,
  );

  test('page and measure mapping', () {
    sample.validate();
    expect(sample.pageForMeasure(1), 0);
    expect(sample.pageForMeasure(19), 0);
    expect(sample.pageForMeasure(20), 1);
    expect(sample.triggerMeasureForPage(0), 18);
    expect(sample.triggerMeasureForPage(1), 41);
  });

  test('serialization round trip', () {
    final json = Score.encodeLibrary([sample]);
    final restored = Score.parseLibrary(json).single;
    expect(restored.lastMeasureByPage, [19, 40]);
    expect(restored.bpm, 155);
  });

  test('invalid page measure ranges are rejected', () {
    expect(() => sample.update(lastMeasureByPage: [19, 18]).validate(), throwsFormatException);
  });

  test('clock can be repositioned without running', () {
    final clock = BeatClock(bpm: 150, beatsPerMeasure: 4, firstMeasure: 1);
    clock.seekMeasure(18);
    expect(clock.measure, 18);
    clock.setTempo(120);
    expect(clock.measure, 18);
    clock.reset();
    expect(clock.measure, 1);
  });
}
