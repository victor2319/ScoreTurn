import 'dart:math' as math;
import 'dart:typed_data';

class LineAudioFrame {
  const LineAudioFrame(this.features, this.rms);
  final Float32List features;
  final double rms;
}

/// Exact CYOLO inference feature convention: PCM16 mono 22050Hz, periodic Hann
/// 2048, hop 1102, magnitude FFT, saved 1025x78 filterbank, log10(energy+1).
class LineSpectrum {
  LineSpectrum(Float32List filterbank, this.onFrame) {
    if (filterbank.length != 1025 * 78) {
      throw const FormatException('Invalid filterbank');
    }
    for (var b = 0; b < 78; b++) {
      final bins = <int>[], weights = <double>[];
      for (var k = 0; k < 1025; k++) {
        final weight = filterbank[k * 78 + b];
        if (weight != 0) {
          bins.add(k);
          weights.add(weight);
        }
      }
      _bins.add(bins);
      _weights.add(weights);
    }
  }
  final void Function(LineAudioFrame) onFrame;
  final _bins = <List<int>>[], _weights = <List<double>>[];
  final _samples = <double>[];
  int? _low;
  void add(Uint8List bytes) {
    for (final byte in bytes) {
      if (_low == null) {
        _low = byte;
        continue;
      }
      var sample = _low! | (byte << 8);
      if (sample >= 32768) sample -= 65536;
      _low = null;
      _samples.add(sample / 32768);
      if (_samples.length == 2048) {
        onFrame(analyze(Float32List.fromList(_samples)));
        _samples.removeRange(0, 1102);
      }
    }
  }

  LineAudioFrame analyze(Float32List samples) {
    if (samples.length != 2048) throw ArgumentError('2048 samples required');
    const n = 2048;
    final re = Float64List(n), im = Float64List(n);
    var energy = 0.0;
    for (var i = 0; i < n; i++) {
      energy += samples[i] * samples[i];
      re[i] = samples[i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / n));
    }
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final value = re[i];
        re[i] = re[j];
        re[j] = value;
      }
    }
    for (var length = 2; length <= n; length <<= 1) {
      final stepR = math.cos(-2 * math.pi / length),
          stepI = math.sin(-2 * math.pi / length);
      for (var start = 0; start < n; start += length) {
        var wr = 1.0, wi = 0.0;
        for (var j = 0; j < length ~/ 2; j++) {
          final a = start + j, b = a + length ~/ 2;
          final vr = re[b] * wr - im[b] * wi, vi = re[b] * wi + im[b] * wr;
          re[b] = re[a] - vr;
          im[b] = im[a] - vi;
          re[a] += vr;
          im[a] += vi;
          final next = wr * stepR - wi * stepI;
          wi = wr * stepI + wi * stepR;
          wr = next;
        }
      }
    }
    final magnitude = List.generate(
      1025,
      (i) => math.sqrt(re[i] * re[i] + im[i] * im[i]),
    );
    final features = Float32List(78);
    for (var b = 0; b < 78; b++) {
      var sum = 0.0;
      for (var j = 0; j < _bins[b].length; j++) {
        sum += magnitude[_bins[b][j]] * _weights[b][j];
      }
      features[b] = math.log(sum + 1) / math.ln10;
    }
    return LineAudioFrame(features, math.sqrt(energy / n));
  }
}
