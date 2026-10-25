import unittest
from recognize import parse_musicxml, parse_sheet, build_document

XML = '''<score-partwise><part id="P1"><measure number="1"><attributes><divisions>2</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes><note><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration></note><note><chord/><pitch><step>E</step><octave>4</octave></pitch><duration>2</duration></note><backup><duration>2</duration></backup><note><pitch><step>C</step><octave>3</octave></pitch><duration>8</duration></note></measure><measure number="2"><note><rest/><duration>8</duration></note><barline><repeat direction="backward"/></barline></measure></part></score-partwise>'''
SHEET = '''<sheet><picture width="1000" height="2000"/><page><system><stack id="1" left="100" right="500"/><stack id="2" left="500" right="900"/><part><staff><lines><line><point x="100" y="200"/><point x="900" y="200"/></line><line><point x="100" y="400"/></line></lines></staff></part></system></page></sheet>'''

class RecognitionTests(unittest.TestCase):
    def test_polyphony_and_repeat(self):
        measures, order, warnings = parse_musicxml(XML)
        self.assertEqual(order, [0, 1, 0, 1])
        self.assertEqual(measures[0]['events'][0]['pitches'], [48, 60, 64])
        self.assertEqual(measures[0]['beats'], 4)
        self.assertEqual(measures[1]['events'], [])
        self.assertEqual(warnings, [])
    def test_coordinates_and_default_trigger(self):
        page, boxes = parse_sheet(SHEET)
        self.assertEqual(boxes[0], [0.1, 0.1, 0.5, 0.2])
        doc = build_document(XML, [(page, boxes)])
        self.assertEqual(doc['measures'][1]['page'], 0)
        self.assertEqual(doc['turnAfter'], [None])
        self.assertFalse(doc['reviewed'])
    def test_count_mismatch_rejected(self):
        page, boxes = parse_sheet(SHEET)
        with self.assertRaises(ValueError):
            build_document(XML, [(page, boxes[:1])])
    def test_missing_geometry_rejected(self):
        with self.assertRaises(ValueError):
            parse_sheet('<sheet><picture width="100" height="100"/><page><system><stack left="0" right="100"/></system></page></sheet>')
    def test_unsupported_navigation_is_explicit(self):
        _, order, warnings = parse_musicxml(XML.replace('<barline>', '<direction><sound dacapo="yes"/></direction><barline>'))
        self.assertEqual(order, [])
        self.assertTrue(warnings)
    def test_invalid_duration_rejected(self):
        with self.assertRaises(ValueError):
            parse_musicxml(XML.replace('<duration>2', '<duration>-2'))
    def test_transposition_not_silently_ignored(self):
        with self.assertRaises(ValueError):
            parse_musicxml(XML.replace('<divisions>', '<transpose><chromatic>2</chromatic></transpose><divisions>'))

if __name__ == '__main__': unittest.main()
