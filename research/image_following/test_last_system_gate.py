import unittest
from last_system_gate import LastSystemGate

class GateTests(unittest.TestCase):
    def test_requires_sequential_rows_and_stability(self):
        gate = LastSystemGate(3, stable_frames=3)
        self.assertFalse(any(gate.add(2, audio_valid=True) for _ in range(10)))
        for row in [0, 1]:
            self.assertFalse(any(gate.add(row, audio_valid=True) for _ in range(3)))
        self.assertFalse(gate.add(2, audio_valid=True))
        self.assertFalse(gate.add(2, audio_valid=True))
        self.assertTrue(gate.add(2, audio_valid=True))
        self.assertFalse(gate.add(2, audio_valid=True))
    def test_silence_and_bad_geometry_break_candidate(self):
        gate = LastSystemGate(2, stable_frames=2)
        gate.add(0, audio_valid=True); gate.add(0, audio_valid=True)
        gate.add(1, audio_valid=True)
        self.assertFalse(gate.add(1, audio_valid=False))
        self.assertFalse(gate.add(1, audio_valid=True))
        self.assertFalse(gate.add(99, audio_valid=True))
        self.assertFalse(gate.add(1, audio_valid=True))
        self.assertTrue(gate.add(1, audio_valid=True))
    def test_starting_in_middle_needs_explicit_seek(self):
        gate = LastSystemGate(3, stable_frames=2)
        self.assertFalse(any(gate.add(1, audio_valid=True) for _ in range(8)))
        gate.seek(1)
        self.assertFalse(gate.add(2, audio_valid=True))
        self.assertTrue(gate.add(2, audio_valid=True))

if __name__ == '__main__': unittest.main()
