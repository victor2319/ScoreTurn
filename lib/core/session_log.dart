import 'dart:convert';
import 'dart:io';

/// Event-only diagnostics. Never stores or uploads PCM audio, sheet images,
/// any device identifier, user name or precise location.
class SessionLog {
  SessionLog({required this.scoreId, required this.startedAt});
  final String scoreId;
  final DateTime startedAt;
  final List<Map<String, Object?>> _events = [];
  static const int maximumEvents = 2000;

  int get count => _events.length;

  void add(String event, {int? measure, int? page, double? bpm,
      String? detail, DateTime? at}) {
    if (_events.length >= maximumEvents) return;
    _events.add({
      'atMs': (at ?? DateTime.now()).difference(startedAt).inMilliseconds,
      'event': event,
      if (measure != null) 'measure': measure,
      if (page != null) 'page': page + 1,
      if (bpm != null) 'bpm': bpm,
      if (detail != null) 'detail': detail,
    });
  }

  String toJsonLines() {
    final header = jsonEncode({
      'format': 'autoscore-session-v1', 'scoreId': scoreId,
      'startedAtUtc': startedAt.toUtc().toIso8601String(),
      'audioStored': false,
    });
    return '$header\n${_events.map(jsonEncode).join('\n')}\n';
  }

  Future<File> saveTo(Directory directory) async {
    await directory.create(recursive: true);
    final name = 'session_${startedAt.toUtc().millisecondsSinceEpoch}.jsonl';
    final file = File('${directory.path}/$name');
    return file.writeAsString(toJsonLines(), flush: true);
  }
}
