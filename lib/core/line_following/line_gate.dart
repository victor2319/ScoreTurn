/// Conservative final-system trigger. A manual seek is required after skips.
class LineGate {
  LineGate(this.rowCount, {this.stableFrames = 10}) {
    if (rowCount < 1 || stableFrames < 1) {
      throw ArgumentError('Invalid row gate');
    }
  }
  final int rowCount, stableFrames;
  int current = -1, _candidate = -1, _count = 0;
  bool _fired = false;
  void seek(int row) {
    if (row < 0 || row >= rowCount) {
      throw RangeError.range(row, 0, rowCount - 1);
    }
    current = row;
    _candidate = -1;
    _count = 0;
    _fired = false;
  }

  void breakEvidence() {
    _candidate = -1;
    _count = 0;
  }

  bool add(int row, {required bool audioValid}) {
    if (!audioValid ||
        row < 0 ||
        row >= rowCount ||
        (row != current && row != current + 1)) {
      breakEvidence();
      return false;
    }
    if (row == _candidate) {
      _count++;
    } else {
      _candidate = row;
      _count = 1;
    }
    if (_count < stableFrames) return false;
    current = row;
    if (row == rowCount - 1 && !_fired) {
      _fired = true;
      return true;
    }
    return false;
  }
}
