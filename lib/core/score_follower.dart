import 'dart:math' as math;

import 'score_document.dart';

class FollowEvent {
  FollowEvent(this.occurrence, this.measureId, this.chroma);
  final int occurrence, measureId;
  final List<double> chroma;
}

/// Conservative local sequence follower. It never advances from elapsed time.
/// Only searches the current event and two following events; manual seek handles
/// large skips. Repeated identical chords require a newly detected attack.
class ScoreFollower {
  ScoreFollower(this.document) {
    document.validate();
    for (var o = 0; o < document.order.length; o++) {
      final id = document.order[o];
      for (final event in document.measures[id].events) {
        final c = List.filled(12, 0.0);
        for (final pitch in event.pitches) {
          c[pitch % 12] = 1;
        }
        final norm = math.sqrt(c.fold(0.0, (a, b) => a + b * b));
        events.add(FollowEvent(o, id, c.map((v) => v / norm).toList()));
      }
    }
    if (events.isEmpty) throw const FormatException('没有可供跟随的音符');
  }
  final ScoreDocument document;
  final List<FollowEvent> events = [];
  int _index = 0, _candidate = -1, _stable = 0, _frame = 0;
  int _lastAttack = -100, _lastAdvance = -100;
  bool locked = false;
  bool _acquired = false;
  double confidence = 0;
  int get measureId => events[_index].measureId;
  int get occurrence => events[_index].occurrence;

  void seek(int occurrence) {
    final next = events.indexWhere((e) => e.occurrence >= occurrence);
    if (next < 0) throw const FormatException('该位置之后没有可跟随的音符');
    _index = next;
    _candidate = -1;
    _stable = 0;
    locked = false;
    _acquired = false;
    _lastAttack = -100;
    _lastAdvance = _frame;
    confidence = 0;
  }

  void add(List<double> chroma, {required double rms, bool onset = false}) {
    _frame++;
    if (onset) _lastAttack = _frame;
    if (chroma.length != 12 ||
        !rms.isFinite ||
        rms < 0.008 ||
        chroma.any((v) => !v.isFinite || v < 0)) {
      locked = false;
      confidence = 0;
      _stable = 0;
      return;
    }
    final norm = math.sqrt(chroma.fold(0.0, (a, b) => a + b * b));
    if (norm < 0.0001) {
      locked = false;
      _stable = 0;
      confidence = 0;
      return;
    }
    double similarity(List<double> ref) {
      var dot = 0.0;
      for (var i = 0; i < 12; i++) {
        dot += chroma[i] / norm * ref[i];
      }
      return dot;
    }

    final current = similarity(events[_index].chroma);
    var best = _index, score = current;
    if (_acquired) {
      for (var i = _index + 1; i < math.min(events.length, _index + 3); i++) {
        var same = 0.0;
        for (var j = 0; j < 12; j++) {
          same += events[_index].chroma[j] * events[i].chroma[j];
        }
        final s = similarity(events[i].chroma);
        if (same > 0.98) {
          // One new attack may advance one identical event, never skip a chain.
          if (i == _index + 1 &&
              _lastAttack > _lastAdvance &&
              _frame - _lastAttack < 6 &&
              s > 0.78) {
            best = i;
            score = s;
            break;
          }
        } else if (s > score + 0.08) {
          best = i;
          score = s;
        }
      }
    }
    confidence = score.clamp(0, 1);
    if (score < 0.78) {
      locked = false;
      _stable = 0;
      return;
    }
    if (best != _candidate) {
      _candidate = best;
      _stable = 1;
    } else {
      _stable++;
    }
    locked = _stable >= 3;
    if (locked) {
      if (best != _index || !_acquired) _lastAdvance = _frame;
      _index = best;
      _acquired = true;
    }
  }

  /// Returns the next distinct page on the actual performance path. Avoid an
  /// early turn if this occurrence repeats within the current page first.
  int? get turnTarget {
    if (!locked) return null;
    final page = document.measures[measureId].page;
    final trigger = document.turnAfter[page];
    if (trigger == null || measureId < trigger) return null;
    var previous = measureId;
    for (var i = occurrence + 1; i < document.order.length; i++) {
      final id = document.order[i];
      final nextPage = document.measures[id].page;
      if (nextPage != page) return nextPage;
      if (id <= previous) return null;
      previous = id;
    }
    return null;
  }
}
