import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:autoscore/core/session_log.dart';

void main() {
  test('event-only privacy-safe JSONL with relative timestamps', () {
    final start = DateTime.utc(2026, 10, 25, 10);
    final log = SessionLog(scoreId: 'demo', startedAt: start);
    log.add('manual_start', measure: 1, page: 0, bpm: 155,
      at: start.add(const Duration(milliseconds: 240)));
    log.add('auto_turn', measure: 18, page: 1,
      at: start.add(const Duration(seconds: 26)));
    final rows = log.toJsonLines().trim().split('\n').map(jsonDecode).toList();
    expect(rows.length, 3);
    expect(rows[0]['audioStored'], false);
    expect(rows[1]['atMs'], 240);
    expect(rows[2]['page'], 2);
    expect(log.toJsonLines().contains('PCM'), false);
  });
}
