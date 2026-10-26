import 'line_layout.dart';

class LineEstimate {
  const LineEstimate(this.row, this.x, this.y, this.score);
  final int row;
  final double x, y, score;
}

/// Select before applying progression gates. A forbidden strongest detection
/// must not turn weak background boxes into apparently stable evidence.
LineEstimate? selectLineEstimate(
  List<dynamic> values, List<ScoreRow> rows, int acceptedRow,
) {
  LineEstimate? best;
  for (var i = 0; i + 4 < values.length; i += 5) {
    final x = ((values[i] as num).toDouble() * 1181 / 416 - 173) / 835;
    final y = (values[i + 1] as num).toDouble() / 416;
    final score = (values[i + 4] as num).toDouble();
    if (!x.isFinite || !y.isFinite || !score.isFinite ||
        score < 0 || score > 1) {
      continue;
    }
    var row = -1;
    for (var j = 0; j < rows.length; j++) {
      if (y >= rows[j].top && y <= rows[j].bottom) {
        row = j;
        break;
      }
    }
    if (best == null || score > best.score) {
      best = LineEstimate(row, x, y, score);
    }
  }
  if (best == null || best.score < 0.25 || best.row < 0 ||
      best.x < 0 || best.x > 1) {
    return null;
  }
  if (acceptedRow < 0) {
    if (best.row != 0 || best.x > 0.3) return null;
  } else if ((best.row - acceptedRow).abs() > 1) {
    return null;
  }
  return best;
}
