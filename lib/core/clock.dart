/// Musical clock that advances beats at a user-configured BPM.
/// Uses a monotonic stopwatch. Tempo changes preserve musical position.
/// Audio is NOT used to determine the true measure in this MVP.
class BeatClock {
  BeatClock({required double bpm, required this.beatsPerMeasure, required this.firstMeasure})
      : assert(bpm > 0),
        assert(beatsPerMeasure > 0),
        _bpm = bpm;

  final int beatsPerMeasure;
  final int firstMeasure;
  final Stopwatch _stopwatch = Stopwatch();
  double _bpm;
  double _beats = 0;
  int _lastMicros = 0;

  double get bpm => _bpm;
  bool get running => _stopwatch.isRunning;
  double get beats {
    _sync();
    return _beats;
  }
  int get measure => firstMeasure + (beats / beatsPerMeasure).floor();
  double get fractionalMeasure => firstMeasure + beats / beatsPerMeasure;
  double get elapsedMusicalSeconds => beats * 60.0 / _bpm;

  void _sync() {
    if (!_stopwatch.isRunning) return;
    final now = _stopwatch.elapsedMicroseconds;
    final delta = (now - _lastMicros).clamp(0, 1 << 53);
    _beats += delta * _bpm / 60000000.0;
    _lastMicros = now;
  }

  void start() {
    _stopwatch.stop();
    _stopwatch.reset();
    _beats = 0;
    _lastMicros = 0;
    _stopwatch.start();
  }

  void resume() {
    if (_stopwatch.isRunning) return;
    _stopwatch.start();
    _lastMicros = _stopwatch.elapsedMicroseconds;
  }

  void pause() {
    _sync();
    _stopwatch.stop();
  }

  void setTempo(double bpm) {
    assert(bpm > 0);
    _sync();
    _bpm = bpm;
  }

  /// Explicit user correction after stops, repeats or skipped passages.
  void seekMeasure(int measure) {
    _sync();
    _beats = (measure - firstMeasure).clamp(0, 1000000).toDouble() * beatsPerMeasure;
    _lastMicros = _stopwatch.elapsedMicroseconds;
  }

  void reset() {
    _stopwatch.stop();
    _stopwatch.reset();
    _lastMicros = 0;
    _beats = 0;
  }
}
