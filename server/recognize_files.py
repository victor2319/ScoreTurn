"""Generate importable JSON locally, without running a web server."""
import argparse
import base64
import json
from pathlib import Path
from recognize import recognize

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('photos', nargs='+', help='Photos in page order')
    parser.add_argument('--out', required=True, help='Output .json filename')
    args = parser.parse_args()
    result = recognize([base64.b64encode(Path(p).read_bytes()).decode() for p in args.photos])
    Path(args.out).write_text(json.dumps(result, ensure_ascii=False), encoding='utf-8')
    print(f'Recognized {len(result["measures"])} measures; review in the app before following.')
