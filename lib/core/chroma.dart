import 'dart:math' as math;
import 'dart:typed_data';

class AudioFeature {
  const AudioFeature(this.chroma, this.rms, this.onset);
  final List<double> chroma;
  final double rms;
  final bool onset;
}

/// PCM16 little-endian, 22050 Hz mono; 4096 sample Hann FFT, 2048 sample hop.
/// Features only: audio is neither saved nor transmitted.
class ChromaExtractor {
  ChromaExtractor(this.onFeature);
  final void Function(AudioFeature) onFeature;
  static const size = 4096, hop = 2048;
  final _samples = <double>[];
  int? _lowByte;
  double _previousRms = 0;
  int _framesSinceOnset = 10;

  void add(Uint8List bytes) {
    for (final byte in bytes) {
      if (_lowByte == null) {
        _lowByte = byte;
        continue;
      }
      var sample = _lowByte! | (byte << 8);
      if (sample >= 32768) sample -= 65536;
      _samples.add(sample / 32768);
      _lowByte = null;
      if (_samples.length == size) {
        _analyze();
        _samples.removeRange(0, hop);
      }
    }
  }

  void _analyze() {
    final real = Float64List(size), imag = Float64List(size);
    var energy = 0.0;
    for (var i = 0; i < size; i++) {
      final x = _samples[i];
      energy += x * x;
      real[i] = x * (0.5 - 0.5 * math.cos(2 * math.pi * i / (size - 1)));
    }
    final rms = math.sqrt(energy / size);
    _framesSinceOnset++;
    final onset =
        rms > 0.008 && rms > _previousRms * 1.7 && _framesSinceOnset >= 3;
    if (onset) _framesSinceOnset = 0;
    _previousRms = rms;
    // In-place radix-2 FFT.
    for (var i = 1, j = 0; i < size; i++) {
      var bit = size >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final t = real[i];
        real[i] = real[j];
        real[j] = t;
      }
    }
    for (var len = 2; len <= size; len <<= 1) {
      final angle = -2 * math.pi / len, wrStep = math.cos(-2 * math.pi / len);
      final wiStep = math.sin(angle);
      for (var start = 0; start < size; start += len) {
        var wr = 1.0, wi = 0.0;
        for (var j = 0; j < len ~/ 2; j++) {
          final a = start + j, b = a + len ~/ 2;
          final vr = real[b] * wr - imag[b] * wi,
              vi = real[b] * wi + imag[b] * wr;
          real[b] = real[a] - vr;
          imag[b] = imag[a] - vi;
          real[a] += vr;
          imag[a] += vi;
          final next = wr * wrStep - wi * wiStep;
          wi = wr * wiStep + wi * wrStep;
          wr = next;
        }
      }
    }
    final magnitudes = List.generate(
      size ~/ 2,
      (i) => math.sqrt(real[i] * real[i] + imag[i] * imag[i]),
    );
    final chroma = List.filled(12, 0.0);
    for (var bin = 6; bin < size ~/ 2 - 1; bin++) {
      final value = magnitudes[bin];
      if (value <= magnitudes[bin - 1] || value < magnitudes[bin + 1]) continue;
      final a = magnitudes[bin - 1], c = magnitudes[bin + 1];
      final denominator = a - 2 * value + c;
      final delta = denominator.abs() > 1e-9
          ? (0.5 * (a - c) / denominator).clamp(-0.5, 0.5)
          : 0.0;
      final frequency = (bin + delta) * 22050 / size;
      final midi = 69 + 12 * math.log(frequency / 440) / math.ln2;
      if (midi < 33 || midi > 96 || (midi - midi.round()).abs() > 0.45) {
        continue;
      }
      chroma[midi.round() % 12] += value;
    }
    onFeature(AudioFeature(chroma, rms, onset));
  }
}
