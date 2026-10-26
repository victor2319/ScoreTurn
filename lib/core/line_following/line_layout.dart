import 'dart:math' as math;
import 'dart:typed_data';

class ScoreRow {
  const ScoreRow(this.top, this.bottom);
  final double top, bottom;
  Map<String, double> toJson() => {'top': top, 'bottom': bottom};
}

class LineLayout {
  LineLayout(this.rows, this.pixels);
  final List<ScoreRow> rows;
  final Float32List pixels;
  static const width = 835, height = 1181, size = 416;

  /// Piano-layout prototype: adaptive Gaussian threshold then pair adjacent
  /// five-line staves. Reject unclear/odd staff counts instead of guessing.
  static LineLayout prepare(Uint8List gray) {
    if (gray.length != width * height) {
      throw const FormatException('Invalid page raster');
    }
    final weights = List.generate(11, (i) => math.exp(-(i - 5) * (i - 5) / 8));
    final norm = weights.reduce((a, b) => a + b);
    for (var i = 0; i < 11; i++) {
      weights[i] /= norm;
    }
    final horizontal = Float32List(gray.length), ink = Uint8List(gray.length);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var value = 0.0;
        for (var k = 0; k < 11; k++) {
          value +=
              gray[y * width + (x + k - 5).clamp(0, width - 1)] * weights[k];
        }
        horizontal[y * width + x] = value;
      }
    }
    final projection = List.filled(height, 0);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var mean = 0.0;
        for (var k = 0; k < 11; k++) {
          mean +=
              horizontal[(y + k - 5).clamp(0, height - 1) * width + x] *
              weights[k];
        }
        if (gray[y * width + x] <= mean.round() - 5) {
          ink[y * width + x] = 1;
          projection[y]++;
        }
      }
    }
    final maxInk = projection.reduce(math.max);
    if (maxInk < width * 0.2) {
      throw const FormatException('未检测到清晰五线谱，请使用更清晰的谱面');
    }
    final peaks = List.generate(height, (i) => projection[i] > maxInk / 2);
    final expanded = List.generate(height, (i) {
      for (var k = math.max(0, i - 5); k < math.min(height, i + 5); k++) {
        if (peaks[k]) return true;
      }
      return false;
    });
    final staffs = <List<int>>[];
    var start = -1;
    for (var y = 0; y <= height; y++) {
      if (y < height && expanded[y]) {
        if (start < 0) start = y;
        continue;
      }
      if (start < 0) continue;
      final linePeaks = <int>[];
      for (var k = start; k < y; k++) {
        if (peaks[k]) linePeaks.add(k);
      }
      if (linePeaks.length >= 3 && linePeaks.last - linePeaks.first >= 15) {
        staffs.add([linePeaks.first, linePeaks.last]);
      }
      start = -1;
    }
    if (staffs.length < 2 || staffs.length.isOdd || staffs.length > 24) {
      throw const FormatException('谱行布局不确定，当前原型支持清晰的钢琴双谱表');
    }
    final rows = <ScoreRow>[];
    for (var i = 0; i < staffs.length; i += 2) {
      if (staffs[i + 1][1] - staffs[i][0] < 30) {
        throw const FormatException('谱表间距不确定');
      }
      rows.add(ScoreRow(staffs[i][0] / height, staffs[i + 1][1] / height));
    }
    // Area resize of white-padded square; coordinates use this exact geometry.
    const pad = (height - width) ~/ 2;
    const scale = height / size;
    final pixels = Float32List(size * size);
    for (var oy = 0; oy < size; oy++) {
      final y0 = oy * scale, y1 = (oy + 1) * scale;
      for (var ox = 0; ox < size; ox++) {
        final x0 = ox * scale, x1 = (ox + 1) * scale;
        var sum = 0.0;
        for (var y = y0.floor(); y < y1.ceil() && y < height; y++) {
          final wy = math.min(y + 1.0, y1) - math.max(y.toDouble(), y0);
          for (var sx = x0.floor(); sx < x1.ceil(); sx++) {
            final x = sx - pad;
            if (x < 0 || x >= width) continue;
            final wx = math.min(sx + 1.0, x1) - math.max(sx.toDouble(), x0);
            sum += ink[y * width + x] * wx * wy;
          }
        }
        pixels[oy * size + ox] = sum / (scale * scale);
      }
    }
    return LineLayout(rows, pixels);
  }
}
