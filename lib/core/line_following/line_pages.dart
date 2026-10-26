import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfx/pdfx.dart';

import '../score.dart';
import 'line_layout.dart';

class PreparedLinePage {
  const PreparedLinePage(this.index, this.path, this.layout);
  final int index;
  final String path;
  final LineLayout layout;
}

class LinePages {
  LinePages(this.score);
  final Score score;
  final _pending = <int, Future<PreparedLinePage>>{};
  Future<PreparedLinePage> get(int page) =>
      _pending.putIfAbsent(page, () => _prepare(page));
  void retain(int current) {
    _pending.removeWhere(
      (index, _) => index < current - 1 || index > current + 1,
    );
  }

  Future<PreparedLinePage> _prepare(int index) async {
    if (index < 0 || index >= score.pageCount) {
      throw RangeError('Page out of range');
    }
    final directory = Directory(
      '${File(score.localPaths.first).parent.path}/line_pages_v1',
    );
    await directory.create(recursive: true);
    final png = File('${directory.path}/$index.png');
    final meta = File('${directory.path}/$index.json');
    final tensor = File('${directory.path}/$index.f32');
    if (await png.exists() && await meta.exists() && await tensor.exists()) {
      try {
        final data =
            jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
        final rows = (data['rows'] as List)
            .map(
              (r) => ScoreRow(
                (r['top'] as num).toDouble(),
                (r['bottom'] as num).toDouble(),
              ),
            )
            .toList();
        final bytes = await tensor.readAsBytes();
        if (rows.isEmpty ||
            rows.any(
              (r) =>
                  !r.top.isFinite ||
                  !r.bottom.isFinite ||
                  r.top < 0 ||
                  r.bottom > 1 ||
                  r.top >= r.bottom,
            ) ||
            bytes.length != 416 * 416 * 4) {
          throw const FormatException('Invalid layout cache');
        }
        final pixels = Float32List.view(
          bytes.buffer,
          bytes.offsetInBytes,
          416 * 416,
        );
        if (pixels.any((v) => !v.isFinite || v < 0 || v > 1)) {
          throw const FormatException('Invalid pixels');
        }
        return PreparedLinePage(index, png.path, LineLayout(rows, pixels));
      } catch (_) {
        /* Regenerate incomplete cache from the immutable local source. */
      }
    }
    Uint8List bytes;
    if (score.isPdf) {
      final document = await PdfDocument.openFile(score.localPaths.first);
      try {
        final page = await document.getPage(index + 1);
        try {
          final rendered = await page.render(
            width: page.width * 1181 / page.height,
            height: 1181,
            format: PdfPageImageFormat.png,
            backgroundColor: '#FFFFFF',
          );
          if (rendered == null) throw const FormatException('PDF 页面渲染失败');
          bytes = rendered.bytes;
        } finally {
          await page.close();
        }
      } finally {
        await document.close();
      }
    } else {
      bytes = await File(score.localPaths[index]).readAsBytes();
    }
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 835,
      targetHeight: 1181,
    );
    ui.Image? normalized;
    try {
      final frame = await codec.getNextFrame();
      try {
        final recorder = ui.PictureRecorder();
        final drawing = ui.Canvas(recorder);
        drawing.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
        drawing.drawImageRect(
          frame.image,
          ui.Rect.fromLTWH(
            0,
            0,
            frame.image.width.toDouble(),
            frame.image.height.toDouble(),
          ),
          const ui.Rect.fromLTWH(0, 0, 835, 1181),
          ui.Paint()..filterQuality = ui.FilterQuality.medium,
        );
        final picture = recorder.endRecording();
        try {
          normalized = await picture.toImage(835, 1181);
        } finally {
          picture.dispose();
        }
      } finally {
        frame.image.dispose();
      }
      final rgba = await normalized!.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (rgba == null) throw const FormatException('无法读取页面像素');
      final raw = rgba.buffer.asUint8List(
        rgba.offsetInBytes,
        rgba.lengthInBytes,
      );
      final gray = Uint8List(835 * 1181);
      for (var i = 0; i < gray.length; i++) {
        gray[i] =
            ((299 * raw[i * 4] + 587 * raw[i * 4 + 1] + 114 * raw[i * 4 + 2]) /
                    1000)
                .round();
      }
      final layout = await Isolate.run(() => LineLayout.prepare(gray));
      final encoded = await normalized!.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (encoded == null) throw const FormatException('无法缓存页面');
      await png.writeAsBytes(
        encoded.buffer.asUint8List(
          encoded.offsetInBytes,
          encoded.lengthInBytes,
        ),
        flush: true,
      );
      await tensor.writeAsBytes(
        layout.pixels.buffer.asUint8List(),
        flush: true,
      );
      final temp = File('${meta.path}.tmp');
      await temp.writeAsString(
        jsonEncode({
          'version': 1,
          'rows': layout.rows.map((r) => r.toJson()).toList(),
        }),
        flush: true,
      );
      await temp.rename(meta.path);
      return PreparedLinePage(index, png.path, layout);
    } finally {
      normalized?.dispose();
      codec.dispose();
    }
  }
}
