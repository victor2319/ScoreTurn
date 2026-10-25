"""Local OMR adapter. Audiveris is a separately installed, AGPL-licensed engine."""
import base64
import hmac
import io
import json
import math
import os
from pathlib import Path
import re
import subprocess
import tempfile
import threading
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from xml.etree import ElementTree as ET

MAX_BODY = 60 * 1024 * 1024
MAX_XML = 32 * 1024 * 1024
LOCK = threading.Lock()


def xml_root(text):
    if len(text) > MAX_XML or '<!ENTITY' in text.upper():
        raise ValueError('XML size/entity limit exceeded')
    root = ET.fromstring(text)
    for element in root.iter():
        element.tag = element.tag.split('}')[-1]
    return root


def positive(text):
    value = float(text)
    if not math.isfinite(value) or value <= 0:
        raise ValueError('Invalid duration or divisions')
    return value


def parse_musicxml(text):
    root = xml_root(text)
    if root.tag != 'score-partwise' or root.find('.//transpose') is not None:
        raise ValueError('Only concert-pitch score-partwise MusicXML is supported')
    parts = root.findall('part')
    if not parts:
        raise ValueError('No musical parts')
    count = len(parts[0].findall('measure'))
    if not 0 < count <= 10000:
        raise ValueError('Invalid measure count')
    measures = [dict(label=m.get('number', str(i+1)), beats=0., events=[])
                for i, m in enumerate(parts[0].findall('measure'))]
    note_spans = [[] for _ in measures]
    for part in parts:
        if len(part.findall('measure')) != count:
            raise ValueError('Parts have inconsistent measure counts')
        divisions, nominal = 1., 4.
        for index, measure in enumerate(part.findall('measure')):
            cursor, last_onset, length = 0., 0., 0.
            for item in measure:
                if item.tag == 'attributes':
                    if item.find('divisions') is not None:
                        divisions = positive(item.findtext('divisions'))
                    time = item.find('time')
                    if time is not None:
                        nominal = positive(time.findtext('beats')) * 4 / positive(time.findtext('beat-type'))
                elif item.tag in ('backup', 'forward'):
                    delta = positive(item.findtext('duration')) / divisions
                    cursor += delta if item.tag == 'forward' else -delta
                    if cursor < -1e-6:
                        raise ValueError('Negative voice position')
                elif item.tag == 'note':
                    if item.find('grace') is not None:
                        continue
                    duration = positive(item.findtext('duration')) / divisions
                    onset = last_onset if item.find('chord') is not None else cursor
                    if item.find('chord') is None:
                        last_onset = cursor
                        cursor += duration
                    length = max(length, onset + duration)
                    pitch = item.find('pitch')
                    if pitch is not None:
                        step = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}[pitch.findtext('step')]
                        midi = (int(pitch.findtext('octave'))+1)*12 + step + float(pitch.findtext('alter', '0'))
                        if midi != int(midi) or not 0 <= midi <= 127:
                            raise ValueError('Unsupported pitch')
                        note_spans[index].append((onset, duration, int(midi)))
                    elif item.find('rest') is None:
                        raise ValueError('Unpitched notes are not supported')
            measures[index]['beats'] = max(measures[index]['beats'], length or nominal)
    for measure, spans in zip(measures, note_spans):
        onsets = sorted(set(s[0] for s in spans))
        for i, onset in enumerate(onsets):
            # Include still-sounding voices at each onset, for piano chords/polyphony.
            pitches = sorted({p for start, duration, p in spans if start <= onset < start + duration})
            end = onsets[i+1] if i+1 < len(onsets) else max(s+d for s,d,_ in spans)
            measure['events'].append(dict(beat=onset, duration=end-onset, pitches=pitches))
    warnings = []
    sounds = root.findall('.//sound')
    complex_navigation = root.find('.//ending') is not None or any(
        any(k in s.attrib for k in ('dacapo', 'dalsegno', 'tocoda', 'fine')) for s in sounds)
    order, start = [], 0
    repeat_open = False
    for index, measure in enumerate(parts[0].findall('measure')):
        repeats = measure.findall('.//repeat')
        if any(r.get('direction') == 'forward' for r in repeats):
            if repeat_open:
                complex_navigation = True
            repeat_open = True
            start = index
        order.append(index)
        for repeat in repeats:
            if repeat.get('direction') == 'backward':
                repeat_open = False
                times = int(repeat.get('times', '2'))
                if not 2 <= times <= 4:
                    complex_navigation = True
                else:
                    order.extend(list(range(start, index+1)) * (times-1))
                start = index+1
    if complex_navigation:
        warnings.append('包含跳房子或复杂反复，请填写实际演奏的小节顺序后再启用跟随。')
        order = []
    return measures, order, warnings


def parse_sheet(text):
    root = xml_root(text)
    picture = root.find('picture')
    if picture is None:
        raise ValueError('Missing Audiveris picture geometry')
    width, height = positive(picture.get('width')), positive(picture.get('height'))
    boxes = []
    for system in root.findall('.//system'):
        ys = [float(p.get('y')) for p in system.findall('.//staff/lines/line/point')]
        if not ys or not all(math.isfinite(y) for y in ys) or min(ys) >= max(ys):
            raise ValueError('Missing staff coordinates; manual review required')
        for stack in system.findall('stack'):
            if stack.get('special') == 'CAUTIONARY':
                continue
            left, right = float(stack.get('left')), float(stack.get('right'))
            box = [left/width, min(ys)/height, right/width, max(ys)/height]
            if not all(math.isfinite(v) and 0 <= v <= 1 for v in box) or left >= right:
                raise ValueError('Invalid measure bounds')
            boxes.append(box)
    if not boxes:
        raise ValueError('No measures recognized')
    return dict(width=int(width), height=int(height)), boxes


def build_document(musicxml, sheets):
    measures, order, warnings = parse_musicxml(musicxml)
    boxes = [(page, box) for page, (_, bounds) in enumerate(sheets) for box in bounds]
    if len(boxes) != len(measures):
        raise ValueError('MusicXML / image measure counts disagree; review in Audiveris')
    turns = []
    for index, (measure, (page, box)) in enumerate(zip(measures, boxes)):
        measure.update(id=index, page=page, box=box)
    for page in range(len(sheets)):
        indices = [m['id'] for m in measures if m['page'] == page]
        turns.append(indices[max(0, len(indices)-2)] if page < len(sheets)-1 else None)
    return dict(version=1, reviewed=False, pages=[s[0] for s in sheets],
                measures=measures, order=order, turnAfter=turns, warnings=warnings,
                musicXml=musicxml)


def read_member(archive, name):
    info = archive.getinfo(name)
    if info.file_size > MAX_XML:
        raise ValueError('Expanded XML too large')
    return archive.read(name).decode('utf-8')


def recognize(pages):
    from PIL import Image, ImageOps
    Image.MAX_IMAGE_PIXELS = 30_000_000
    if not isinstance(pages, list) or not 1 <= len(pages) <= 30:
        raise ValueError('Select 1 to 30 photos')
    with tempfile.TemporaryDirectory(prefix='scoreturn-') as temp:
        directory = Path(temp)
        images = []
        for encoded in pages:
            raw = base64.b64decode(encoded, validate=True)
            image = ImageOps.exif_transpose(Image.open(io.BytesIO(raw))).convert('RGB')
            if image.width * image.height > 30_000_000:
                raise ValueError('Photo exceeds 30 megapixels')
            images.append(image)
        source = directory / 'score.tiff'
        images[0].save(source, save_all=True, append_images=images[1:], compression='tiff_deflate')
        command = os.environ.get('AUDIVERIS_BIN', 'audiveris')
        # No shell expansion and no user-controlled filenames or command arguments.
        with (directory / 'engine.log').open('wb') as log:
            result = subprocess.run([command, '-batch', '-transcribe', '-export', '-save',
                '-output', str(directory / 'out'), '--', str(source)],
                stdout=log, stderr=subprocess.STDOUT, timeout=600, check=False)
        if result.returncode:
            raise ValueError('Audiveris recognition failed; inspect the score in Audiveris')
        mxls, omrs = list(directory.rglob('*.mxl')), list(directory.rglob('*.omr'))
        if len(mxls) != 1 or len(omrs) != 1:
            raise ValueError('Expected one movement; split movements before importing')
        with zipfile.ZipFile(mxls[0]) as archive:
            container = xml_root(read_member(archive, 'META-INF/container.xml'))
            filename = container.find('.//rootfile').get('full-path')
            musicxml = read_member(archive, filename)
        with zipfile.ZipFile(omrs[0]) as archive:
            names = [n for n in archive.namelist() if re.fullmatch(r'sheet\d+/sheet\d+\.xml', n)]
            names.sort(key=lambda n: int(re.search(r'\d+', n).group()))
            if len(names) != len(images):
                raise ValueError('Some pages were not recognized')
            sheets = [parse_sheet(read_member(archive, name)) for name in names]
        return build_document(musicxml, sheets)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Do not log tokens, score names or score contents.

    def reply(self, status, body):
        payload = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_POST(self):
        if self.path != '/recognize':
            return self.reply(404, {'error': 'Not found'})
        token = os.environ.get('SCORETURN_TOKEN', '')
        if not token or not hmac.compare_digest(self.headers.get('Authorization', ''), 'Bearer '+token):
            return self.reply(401, {'error': 'Invalid service token'})
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= MAX_BODY:
                return self.reply(413, {'error': 'Upload limit: 60 MB'})
            if not LOCK.acquire(blocking=False):
                return self.reply(503, {'error': 'Recognition busy; retry later'})
            try:
                self.connection.settimeout(60)
                request = json.loads(self.rfile.read(size))
                result = recognize(request['pages'])
                self.reply(200, result)
            finally:
                LOCK.release()
        except (ValueError, KeyError, ET.ParseError, OSError, subprocess.TimeoutExpired) as exc:
            self.reply(422, {'error': str(exc)[:300]})


if __name__ == '__main__':
    if not os.environ.get('SCORETURN_TOKEN'):
        raise SystemExit('Set SCORETURN_TOKEN before starting the service')
    # Use an HTTPS reverse proxy; intentionally never expose this port publicly.
    ThreadingHTTPServer(('127.0.0.1', 8765), Handler).serve_forever()
