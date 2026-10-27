import 'package:flutter_test/flutter_test.dart';
import 'package:autoscore/core/line_following/line_layout.dart';
import 'package:autoscore/core/line_following/line_localization.dart';

void main() {
  const rows = [ScoreRow(0.1, 0.2), ScoreRow(0.4, 0.5), ScoreRow(0.7, 0.8)];
  // Coordinates in the model's padded 416px square.
  List<double> box(double x, double y, double score) =>
      [(x * 835 + 173) * 416 / 1181, y * 416, 10, 10, score];
  test('strongest forbidden jump rejects weaker allowed-row fallback', () {
    expect(selectLineEstimate([
      ...box(0.2, 0.75, 0.9), ...box(0.2, 0.45, 0.01),
    ], rows, 0), isNull);
  });
  test('initial alignment needs strongest candidate at start of first row', () {
    expect(selectLineEstimate([
      ...box(0.8, 0.15, 0.9), ...box(0.2, 0.15, 0.4),
    ], rows, -1), isNull);
  });
  test('valid adjacent strongest candidate passes; weak/nonfinite fail', () {
    expect(selectLineEstimate(box(0.2, 0.45, 0.8), rows, 0)?.row, 1);
    expect(selectLineEstimate(box(0.2, 0.45, 0.01), rows, 0), isNull);
    expect(selectLineEstimate(box(0.2, 0.45, double.nan), rows, 0), isNull);
  });
}
