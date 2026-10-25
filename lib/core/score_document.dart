/// Parsed music plus normalized original-image positions. IDs refer to printed
/// measures; order entries refer to separate occurrences during performance.
class ScoreDocument {
  ScoreDocument({
    required this.pages,
    required this.measures,
    required this.order,
    required this.turnAfter,
    required this.warnings,
    required this.musicXml,
    this.reviewed = false,
  });
  final List<PageGeometry> pages;
  final List<RecognizedMeasure> measures;
  List<int> order;
  final List<int?> turnAfter;
  final List<String> warnings;
  final String musicXml;
  bool reviewed;
  bool get ready =>
      reviewed &&
      order.isNotEmpty &&
      order.every((id) => id >= 0 && id < measures.length) &&
      measures.any((m) => m.events.isNotEmpty);

  void validate() {
    void require(bool valid) {
      if (!valid) throw const FormatException('识谱数据不完整或格式不正确');
    }

    require(
      pages.isNotEmpty &&
          pages.length <= 30 &&
          measures.isNotEmpty &&
          measures.length <= 10000,
    );
    require(turnAfter.length == pages.length && order.length <= 50000);
    for (final p in pages) {
      require(p.width > 0 && p.height > 0 && p.width * p.height <= 30000000);
    }
    var previousPage = 0;
    for (var i = 0; i < measures.length; i++) {
      final m = measures[i];
      require(m.id == i && m.page >= previousPage && m.page < pages.length);
      previousPage = m.page;
      require(m.beats.isFinite && m.beats > 0 && m.beats <= 128);
      require(
        m.box.length == 4 && m.box.every((v) => v.isFinite && v >= 0 && v <= 1),
      );
      require(m.box[0] < m.box[2] && m.box[1] < m.box[3]);
      var previousBeat = -1.0;
      for (final e in m.events) {
        require(
          e.beat.isFinite &&
              e.duration.isFinite &&
              e.beat >= 0 &&
              e.beat > previousBeat &&
              e.duration > 0 &&
              e.beat + e.duration <= m.beats + 0.001,
        );
        require(
          e.pitches.isNotEmpty && e.pitches.every((p) => p >= 0 && p <= 127),
        );
        previousBeat = e.beat;
      }
    }
    for (var page = 0; page < pages.length; page++) {
      require(measures.any((m) => m.page == page));
      final trigger = turnAfter[page];
      require(
        trigger == null ||
            (trigger >= 0 &&
                trigger < measures.length &&
                measures[trigger].page == page),
      );
    }
    require(order.every((id) => id >= 0 && id < measures.length));
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'reviewed': reviewed,
    'pages': pages.map((p) => {'width': p.width, 'height': p.height}).toList(),
    'measures': measures.map((m) => m.toJson()).toList(),
    'order': order,
    'turnAfter': turnAfter,
    'warnings': warnings,
    'musicXml': musicXml,
  };
  factory ScoreDocument.fromJson(Map<String, dynamic> json) {
    try {
      if (json['version'] != 1) throw const FormatException('不支持的识谱数据版本');
      final document = ScoreDocument(
        pages: (json['pages'] as List)
            .map((p) => PageGeometry(p['width'] as int, p['height'] as int))
            .toList(),
        measures: (json['measures'] as List)
            .map(
              (m) => RecognizedMeasure.fromJson(Map<String, dynamic>.from(m)),
            )
            .toList(),
        order: (json['order'] as List).cast<int>().toList(),
        turnAfter: (json['turnAfter'] as List).cast<int?>().toList(),
        warnings: (json['warnings'] as List).cast<String>().toList(),
        musicXml: json['musicXml'] as String,
        reviewed: json['reviewed'] == true,
      );
      document.validate();
      return document;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('无法读取识谱数据');
    }
  }
}

class PageGeometry {
  const PageGeometry(this.width, this.height);
  final int width, height;
}

class RecognizedMeasure {
  RecognizedMeasure({
    required this.id,
    required this.label,
    required this.page,
    required this.beats,
    required this.box,
    required this.events,
  });
  final int id, page;
  final String label;
  final double beats;
  List<double> box;
  final List<ScoreEvent> events;
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'page': page,
    'beats': beats,
    'box': box,
    'events': events.map((e) => e.toJson()).toList(),
  };
  factory RecognizedMeasure.fromJson(Map<String, dynamic> j) =>
      RecognizedMeasure(
        id: j['id'] as int,
        label: j['label'] as String,
        page: j['page'] as int,
        beats: (j['beats'] as num).toDouble(),
        box: (j['box'] as List).map((v) => (v as num).toDouble()).toList(),
        events: (j['events'] as List)
            .map(
              (e) => ScoreEvent(
                (e['beat'] as num).toDouble(),
                (e['duration'] as num).toDouble(),
                (e['pitches'] as List).cast<int>(),
              ),
            )
            .toList(),
      );
}

class ScoreEvent {
  const ScoreEvent(this.beat, this.duration, this.pitches);
  final double beat, duration;
  final List<int> pitches;
  Map<String, dynamic> toJson() => {
    'beat': beat,
    'duration': duration,
    'pitches': pitches,
  };
}
