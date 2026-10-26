import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'line_pages.dart';
import 'line_spectrum.dart';

class LineEstimate {
  const LineEstimate(this.row, this.x, this.y, this.score);
  final int row;
  final double x, y, score;
}

/// All methods are called serially by the reader pump. Stop/seek waits for the
/// pump before resetting or closing native sessions and tensors.
class LineModel {
  OrtSession? _image, _context;
  OrtValue? _h, _c, _pageValue;
  String? _pagePath;
  late List<double> _initialH, _initialC;
  late Float32List filterbank;
  final _history = Float32List(40 * 78);
  int _step = 0;
  Future<void> initialize() async {
    final metadata = jsonDecode(
      await rootBundle.loadString('assets/line_model/metadata.json'),
    ) as Map<String, dynamic>;
    _initialH = (metadata['initialH'] as List)
        .map((v) => (v as num).toDouble())
        .toList();
    _initialC = (metadata['initialC'] as List)
        .map((v) => (v as num).toDouble())
        .toList();
    final bytes = await rootBundle.load('assets/line_model/filterbank.f32');
    filterbank = Float32List(1025 * 78);
    for (var i = 0; i < filterbank.length; i++) {
      filterbank[i] = bytes.getFloat32(i * 4, Endian.little);
    }
    final runtime = OnnxRuntime();
    final options = OrtSessionOptions(
      intraOpNumThreads: 2,
      interOpNumThreads: 1,
      providers: [OrtProvider.CPU],
    );
    try {
      _context = await runtime.createSessionFromAsset(
        'assets/line_model/context.onnx',
        options: options,
      );
      _image = await runtime.createSessionFromAsset(
        'assets/line_model/image.onnx',
        options: options,
      );
      await reset();
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<void> reset() async {
    await _h?.dispose();
    await _c?.dispose();
    _h = await OrtValue.fromList(Float32List.fromList(_initialH), [1, 1, 64]);
    _c = await OrtValue.fromList(Float32List.fromList(_initialC), [1, 1, 64]);
    _history.fillRange(0, _history.length, 0);
    _step = 0;
  }

  Future<LineEstimate?> predict(
    LineAudioFrame frame,
    PreparedLinePage page,
    int acceptedRow,
  ) async {
    _history.setRange(0, 39 * 78, _history, 78);
    _history.setRange(39 * 78, 40 * 78, frame.features);
    OrtValue? history;
    Map<String, OrtValue>? audioOut, imageOut;
    try {
      history = await OrtValue.fromList(_history, [1, 1, 40, 78]);
      audioOut = await _context!.run({'history': history, 'h': _h!, 'c': _c!});
      _step++;
      if (_step % 40 == 0) {
        await _h!.dispose();
        await _c!.dispose();
        _h = audioOut.remove('next_h');
        _c = audioOut.remove('next_c');
      }
      // Context still consumes every 50ms frame; image localization is 10Hz.
      if (_step.isOdd || frame.rms < 0.008) return null;
      if (_pagePath != page.path) {
        await _pageValue?.dispose();
        _pageValue = await OrtValue.fromList(page.layout.pixels, [
          1,
          1,
          416,
          416,
        ]);
        _pagePath = page.path;
      }
      imageOut = await _image!.run({
        'image': _pageValue!,
        'audio_context': audioOut['audio_context']!,
      });
      final values = await imageOut['boxes']!.asFlattenedList();
      LineEstimate? best;
      for (var i = 0; i + 4 < values.length; i += 5) {
        final x = ((values[i] as num).toDouble() * 1181 / 416 - 173) / 835;
        final y = (values[i + 1] as num).toDouble() / 416;
        final score = (values[i + 4] as num).toDouble();
        if (!x.isFinite ||
            !y.isFinite ||
            !score.isFinite ||
            x < 0 ||
            x > 1 ||
            score < 0 ||
            score > 1) {
          continue;
        }
        var row = -1;
        for (var j = 0; j < page.layout.rows.length; j++) {
          final r = page.layout.rows[j];
          if (y >= r.top && y <= r.bottom) {
            row = j;
            break;
          }
        }
        if (row < 0) continue;
        if (acceptedRow < 0) {
          if (row != 0 || x > 0.3) continue;
        } else if ((row - acceptedRow).abs() > 1) {
          continue;
        }
        if (best == null || score > best.score) {
          best = LineEstimate(row, x, y, score);
        }
      }
      return best;
    } finally {
      await history?.dispose();
      if (audioOut != null) {
        for (final value in audioOut.values) {
          await value.dispose();
        }
      }
      if (imageOut != null) {
        for (final value in imageOut.values) {
          await value.dispose();
        }
      }
    }
  }

  Future<void> close() async {
    await _h?.dispose();
    await _c?.dispose();
    await _pageValue?.dispose();
    _h = null;
    _c = null;
    _pageValue = null;
    _pagePath = null;
    await _context?.close();
    await _image?.close();
    _context = null;
    _image = null;
  }
}
