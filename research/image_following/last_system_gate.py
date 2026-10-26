"""Research-only line-level trigger; does not turn any application pages.

A row estimator is upstream. Raw neural-network confidence is deliberately not
interpreted as match probability. Audio validity must be supplied independently.
This conservative policy intentionally requires manual seek for skips/repeats.
"""
class LastSystemGate:
    def __init__(self, row_count, stable_frames=10):
        if row_count < 1 or stable_frames < 1:
            raise ValueError('Positive row count and stability duration required')
        self.row_count = row_count
        self.stable_frames = stable_frames
        self.current = -1
        self.candidate = None
        self.count = 0
        self.fired = False

    def seek(self, row):
        if not 0 <= row < self.row_count:
            raise ValueError('Unknown row')
        self.current = row
        self.candidate = None
        self.count = 0
        self.fired = False

    def add(self, row, *, audio_valid):
        if not audio_valid or row not in (self.current, self.current + 1) or not 0 <= row < self.row_count:
            self.candidate = None
            self.count = 0
            return False
        if row == self.candidate:
            self.count += 1
        else:
            self.candidate, self.count = row, 1
        if self.count < self.stable_frames:
            return False
        self.current = row
        if row == self.row_count - 1 and not self.fired:
            self.fired = True
            return True
        return False
