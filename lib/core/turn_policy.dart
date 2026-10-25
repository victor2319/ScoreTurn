import 'score.dart';

/// A deterministic, score-measure-based page-turn policy.
///
/// It is deliberately NOT a score-following or harmonic-confirmation system.
/// Crucially it only accepts a natural progression across the trigger position.
/// Explicit manual seeks, time jumps and interruptions never authorize a turn.
class TurnDecision {
  const TurnDecision({required this.previewNext, required this.turnPage});
  final bool previewNext;
  final bool turnPage;
}

class TurnPolicy {
  TurnPolicy(this.score);
  final Score score;
  int? _previous;
  int? _page;

  void reset({int? currentMeasure, int? currentPage}) {
    _previous = currentMeasure;
    _page = currentPage;
  }

  /// Call this after user seeks, resumes automatic mode or manually flips.
  /// A seek cannot be mistaken for a musical passage through a boundary.
  void reposition({required int measure, required int page}) {
    _previous = measure;
    _page = page;
  }

  TurnDecision update({
    required int measure,
    required int page,
    required bool running,
    required bool automaticEnabled,
  }) {
    final last = _previous;
    final samePage = _page == page;
    _previous = measure;
    _page = page;
    if (page >= score.pageCount - 1 || !running || !automaticEnabled) {
      return const TurnDecision(previewNext: false, turnPage: false);
    }
    final trigger = score.triggerMeasureForPage(page);
    final preview = measure >= trigger - 1 &&
        measure <= score.lastMeasureByPage[page];
    final crossed = samePage && last != null &&
        last < trigger && measure >= trigger &&
        // Never fast-forward over a boundary after missed timer ticks or seeks.
        measure - last <= 1;
    return TurnDecision(previewNext: preview, turnPage: crossed);
  }
}
