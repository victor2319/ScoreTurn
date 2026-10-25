import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'score.dart';

class ScoreLibrary {
  late Directory root;
  List<Score> _scores = [];
  List<Score> get scores => List.unmodifiable(_scores);

  Future<void> initialize() async {
    final docs = await getApplicationDocumentsDirectory();
    root = Directory('${docs.path}/autoscore');
    await root.create(recursive: true);
    final catalog = File('${root.path}/catalog.json');
    if (await catalog.exists()) {
      _scores = Score.parseLibrary(await catalog.readAsString());
    }
    // Provide a real, user-supplied two-page demo immediately on first launch.
    if (_scores.isEmpty) {
      await createDemo();
    }
  }

  Future<void> _save() async {
    final dest = File('${root.path}/catalog.json');
    final temp = File('${root.path}/catalog.json.tmp');
    await temp.writeAsString(Score.encodeLibrary(_scores), flush: true);
    if (await dest.exists()) await dest.delete();
    await temp.rename(dest.path);
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}';

  Future<Score> createDemo() async {
    final id = _newId();
    final dir = Directory('${root.path}/$id');
    await dir.create(recursive: true);
    final paths = <String>[];
    for (var i = 0; i < 2; i++) {
      final bytes = await rootBundle.load(i == 0
          ? 'assets/demo/page_88.jpg' : 'assets/demo/page_89.jpg');
      final path = '${dir.path}/page_$i.jpg';
      await File(path).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      paths.add(path);
    }
    final score = Score(id: id, title: '示例 · 贝多芬《黎明》Op.53',
      isPdf: false, localPaths: paths, pageCount: 2, firstMeasure: 1,
      lastMeasureByPage: const [19, 40], beatsPerMeasure: 4,
      bpm: 155, advanceMeasures: 2);
    score.validate();
    _scores.insert(0, score);
    await _save();
    return score;
  }

  Future<Score> importImages(String title, List<List<int>> bytes, List<String> extensions) async {
    if (bytes.isEmpty || bytes.length != extensions.length) {
      throw ArgumentError('Invalid photo selection');
    }
    final id = _newId();
    final dir = Directory('${root.path}/$id');
    await dir.create(recursive: true);
    final paths = <String>[];
    try {
      for (var i = 0; i < bytes.length; i++) {
        final ext = extensions[i].toLowerCase();
        if (!{'jpg', 'jpeg', 'png', 'webp'}.contains(ext)) {
          throw const FormatException('Unsupported image format');
        }
        final path = '${dir.path}/page_$i.$ext';
        await File(path).writeAsBytes(bytes[i], flush: true);
        paths.add(path);
      }
      final score = Score(id: id, title: title, isPdf: false,
        localPaths: paths, pageCount: paths.length, firstMeasure: 1,
        lastMeasureByPage: List.generate(paths.length, (i) => (i + 1) * 8),
        beatsPerMeasure: 4, bpm: 120, advanceMeasures: 1);
      score.validate();
      _scores.insert(0, score);
      await _save();
      return score;
    } catch (_) {
      await dir.delete(recursive: true);
      rethrow;
    }
  }

  Future<Score> importPdf(String title, List<int> bytes) async {
    final id = _newId();
    final dir = Directory('${root.path}/$id');
    await dir.create(recursive: true);
    final path = '${dir.path}/score.pdf';
    try {
      await File(path).writeAsBytes(bytes, flush: true);
      final document = await PdfDocument.openFile(path);
      final count = document.pagesCount;
      await document.close();
      final score = Score(id: id, title: title, isPdf: true,
        localPaths: [path], pageCount: count, firstMeasure: 1,
        lastMeasureByPage: List.generate(count, (i) => (i + 1) * 8),
        beatsPerMeasure: 4, bpm: 120, advanceMeasures: 1);
      score.validate();
      _scores.insert(0, score);
      await _save();
      return score;
    } catch (_) {
      await dir.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> replace(Score updated) async {
    updated.validate();
    final index = _scores.indexWhere((item) => item.id == updated.id);
    if (index < 0) throw StateError('Score not found');
    _scores[index] = updated;
    await _save();
  }

  Future<void> delete(Score score) async {
    _scores.removeWhere((item) => item.id == score.id);
    await _save();
    final dir = Directory('${root.path}/${score.id}');
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
