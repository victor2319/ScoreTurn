import 'dart:math' as math;
import 'dart:typed_data';

/// Works with little-endian, mono, signed 16-bit PCM (from record stream).
/// Simple amplitude-onset detection, NOT a score-matched first-measure recognizer.
/// Starts with 0.6 seconds of ambient calibration, then requires >60ms of
/// sustained signal above floor. Audio from other sources can still trigger.
class AudioStartDetector {
  AudioStartDetector({this.sampleRate = 22050});
  final int sampleRate;
  final List<int> _pending = [];
  int _sampleCount = 0;
  double _noiseEnergy = 0;
  int _noiseFrames = 0;
  int _hotFrames = 0;
  bool _started = false;
  double _lastRms = 0;

  bool get started => _started;
  bool get calibrated => _sampleCount >= sampleRate * 0.6;
  double get rms => _lastRms;
  double get floor => math.sqrt(_noiseEnergy / math.max(1, _noiseFrames));

  void reset() {
    _pending.clear();
    _sampleCount = 0;
    _noiseEnergy = 0;
    _noiseFrames = 0;
    _hotFrames = 0;
    _started = false;
    _lastRms = 0;
  }

  /// Returns true exactly when a start is first detected.
  bool add(Uint8List bytes) {
    if (_started) return false;
    // Streaming backends may deliver odd-length chunks. Preserve alignment.
    _pending.addAll(bytes);
    const frameSamples = 256;
    const frameBytes = frameSamples * 2;
    var fired = false;
    var offset = 0;
    while (offset + frameBytes <= _pending.length && !_started) {
      double energy = 0;
      for (var i = offset; i < offset + frameBytes; i += 2) {
        var x = _pending[i] | (_pending[i + 1] << 8);
        if (x >= 32768) x -= 65536;
        final sample = x / 32768.0;
        energy += sample * sample;
      }
      energy /= frameSamples;
      _lastRms = math.sqrt(energy);
      if (!calibrated) {
        _noiseEnergy += energy;
        _noiseFrames++;
      } else {
        final threshold = math.max(0.018, floor * 4.0);
        _hotFrames = _lastRms > threshold ? _hotFrames + 1 : 0;
        if (_hotFrames >= 6) { // ~70ms at 22050Hz
          _started = true;
          fired = true;
        }
      }
      _sampleCount += frameSamples;
      offset += frameBytes;
    }
    _pending.removeRange(0, offset);
    return fired;
  }
}
