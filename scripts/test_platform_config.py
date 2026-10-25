"""Runs without Flutter to verify platform permission config is idempotent and XML-valid."""
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
import plistlib
import xml.etree.ElementTree as ET
sys.path.insert(0, str(Path(__file__).resolve().parent))
from configure_platforms import configure_android, configure_ios

with TemporaryDirectory() as d:
    a = Path(d) / 'AndroidManifest.xml'
    a.write_text('''<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:label="autoscore" /></manifest>''')
    i = Path(d) / 'Info.plist'
    i.write_bytes(plistlib.dumps({'CFBundleIdentifier': 'app.autoscore.autoscore'}))
    configure_android(a)
    configure_android(a)
    configure_ios(i)
    configure_ios(i)
    ar = ET.parse(a).getroot()
    assert len(ar.findall('uses-permission')) == 1
    assert ar.find('uses-permission').attrib['{http://schemas.android.com/apk/res/android}name'] == 'android.permission.RECORD_AUDIO'
    assert 'INTERNET' not in a.read_text()
    plist = plistlib.loads(i.read_bytes())
    assert plist['NSMicrophoneUsageDescription']
    assert plist['CFBundleDisplayName'] == 'AutoScore'
    print('PASS: platform permissions idempotent, XML/plist valid, no Android release INTERNET.')
