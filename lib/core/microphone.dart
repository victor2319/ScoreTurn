import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'start_detector.dart';

/// On-device PCM capture for onset *amplitude*, not music recognition.
/// The generation check prevents a late microphone-permission response from
/// silently re-arming recording after the user canceled listening.
class MicrophoneGate {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioStartDetector detector = AudioStartDetector();
  StreamSubscription<Uint8List>? _subscription;
  bool _active = false;
  bool get active => _active;
  int _meterCount = 0;
  int _generation = 0;
  int receivedChunks = 0;
  int receivedBytes = 0;

  Future<void> arm({
    required void Function() onStart,
    required void Function(double, bool) onMeter,
    required void Function(Object) onError,
    void Function(Uint8List)? onPcm,
  }) async {
    await stop();
    final generation = ++_generation;
    if (!await _recorder.hasPermission()) {
      if (generation != _generation) return;
      throw StateError('需要麦克风权限才能监听演奏开始。');
    }
    if (generation != _generation) return;
    detector.reset();
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 22050,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );
    if (generation != _generation) {
      if (await _recorder.isRecording()) await _recorder.stop();
      return;
    }
    _active = true;
    _meterCount = 0;
    receivedChunks = 0;
    receivedBytes = 0;
    _subscription = stream.listen(
      (chunk) {
        if (generation != _generation || !_active) return;
        receivedChunks++;
        receivedBytes += chunk.length;
        onPcm?.call(chunk);
        final triggered = detector.add(chunk);
        _meterCount++;
        if (_meterCount % 8 == 0 || triggered) {
          onMeter(detector.rms, detector.calibrated);
        }
        if (triggered) {
          onStart();
          // Do not cancel native audio recording from inside its own callback.
          if (onPcm == null) scheduleMicrotask(() => stop());
        }
      },
      onError: (Object e) {
        if (generation != _generation) return;
        _active = false;
        onError(e);
        scheduleMicrotask(() => stop());
      },
      onDone: () {
        if (generation != _generation || !_active) return;
        _active = false;
        onError(StateError('麦克风流已中断，请重新开始'));
        scheduleMicrotask(() => stop());
      },
      cancelOnError: true,
    );
  }

  Future<void> stop() async {
    ++_generation;
    _active = false;
    final sub = _subscription;
    _subscription = null;
    await sub?.cancel();
    if (await _recorder.isRecording()) await _recorder.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }
}
