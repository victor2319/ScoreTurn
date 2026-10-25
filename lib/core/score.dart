import 'dart:convert';

/// A music page is either one page within a PDF, or a standalone photo.
/// The MVP does NOT parse notation automatically. Measure boundaries are
/// provided by the musician and are editable in the UI.
class Score {
  final String id;
  final String title;
  final bool isPdf;
  final List<String> localPaths;
  final int pageCount;
  final int firstMeasure;
  final List<int> lastMeasureByPage;
  final int beatsPerMeasure;
  final double bpm;
  final int advanceMeasures;

  const Score({
    required this.id,
    required this.title,
    required this.isPdf,
    required this.localPaths,
    required this.pageCount,
    required this.firstMeasure,
    required this.lastMeasureByPage,
    required this.beatsPerMeasure,
    required this.bpm,
    required this.advanceMeasures,
  });

  int get lastMeasure => lastMeasureByPage.last;

  int pageForMeasure(int measure) {
    for (var i = 0; i < lastMeasureByPage.length; i++) {
      if (measure <= lastMeasureByPage[i]) return i;
    }
    return pageCount - 1;
  }

  int triggerMeasureForPage(int page) {
    if (page >= pageCount - 1) return lastMeasure + 1;
    final pageFirst = page == 0 ? firstMeasure : lastMeasureByPage[page - 1] + 1;
    // E.g. last measure 19, advanceMeasures 2 -> trigger measure 18.
    return (lastMeasureByPage[page] + 1 - advanceMeasures)
        .clamp(pageFirst, lastMeasureByPage[page]).toInt();
  }

  Score update({
    String? title,
    List<int>? lastMeasureByPage,
    int? beatsPerMeasure,
    double? bpm,
    int? advanceMeasures,
    int? firstMeasure,
  }) => Score(
    id: id,
    title: title ?? this.title,
    isPdf: isPdf,
    localPaths: localPaths,
    pageCount: pageCount,
    firstMeasure: firstMeasure ?? this.firstMeasure,
    lastMeasureByPage: lastMeasureByPage ?? this.lastMeasureByPage,
    beatsPerMeasure: beatsPerMeasure ?? this.beatsPerMeasure,
    bpm: bpm ?? this.bpm,
    advanceMeasures: advanceMeasures ?? this.advanceMeasures,
  );

  void validate() {
    if (id.isEmpty || title.isEmpty) throw const FormatException('Invalid score identity');
    if (pageCount <= 0 || lastMeasureByPage.length != pageCount) {
      throw const FormatException('Page count and measure mapping disagree');
    }
    if (isPdf ? localPaths.length != 1 : localPaths.length != pageCount) {
      throw const FormatException('Invalid local page files');
    }
    if (beatsPerMeasure < 1 || beatsPerMeasure > 12 || bpm < 30 || bpm > 300 ||
        advanceMeasures < 1 || advanceMeasures > 8 || firstMeasure < 1) {
      throw const FormatException('Invalid tempo, meter or advance setting');
    }
    var previous = firstMeasure - 1;
    for (final measure in lastMeasureByPage) {
      if (measure <= previous) {
        throw const FormatException('Last measures must strictly increase');
      }
      previous = measure;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'isPdf': isPdf,
    'localPaths': localPaths,
    'pageCount': pageCount,
    'firstMeasure': firstMeasure,
    'lastMeasureByPage': lastMeasureByPage,
    'beatsPerMeasure': beatsPerMeasure,
    'bpm': bpm,
    'advanceMeasures': advanceMeasures,
  };

  factory Score.fromJson(Map<String, dynamic> json) {
    final score = Score(
      id: json['id'] as String,
      title: json['title'] as String,
      isPdf: json['isPdf'] as bool,
      localPaths: (json['localPaths'] as List).cast<String>(),
      pageCount: json['pageCount'] as int,
      firstMeasure: json['firstMeasure'] as int? ?? 1,
      lastMeasureByPage: (json['lastMeasureByPage'] as List).cast<int>(),
      beatsPerMeasure: json['beatsPerMeasure'] as int,
      bpm: (json['bpm'] as num).toDouble(),
      advanceMeasures: json['advanceMeasures'] as int,
    );
    score.validate();
    return score;
  }

  static List<Score> parseLibrary(String text) => (jsonDecode(text) as List)
      .map((e) => Score.fromJson((e as Map).cast<String, dynamic>())).toList();

  static String encodeLibrary(List<Score> scores) =>
      const JsonEncoder.withIndent('  ').convert(scores.map((s) => s.toJson()).toList());
}
