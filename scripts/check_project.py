#!/usr/bin/env python3
"""Portable structural checks. This does not compile Apple frameworks or test iPad behavior."""
import hashlib
import json
import plistlib
import re
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]

def check():
    checked = 0
    info = plistlib.loads((ROOT/'Resources/Info.plist').read_bytes())
    privacy = plistlib.loads((ROOT/'Resources/PrivacyInfo.xcprivacy').read_bytes())
    assert info['UIBackgroundModes'] == ['audio']
    assert not info['UIRequiresFullScreen']
    assert info['NSSpeechRecognitionUsageDescription']
    assert not privacy['NSPrivacyTracking']
    checked += 2
    app_sources = sorted(p.relative_to(ROOT).as_posix() for d in ('App','Audio','Transcription','Storage','Notebook','Documents','Study','Views') for p in (ROOT/d).glob('*.swift'))
    for project in ROOT.glob('*.xcodeproj'):
        text = (project/'project.pbxproj').read_text()
        objects = re.findall(r'^\s*([A-F0-9]{24}) = \{',text,re.M)
        assert len(objects) == len(set(objects)), f'Duplicate object in {project}'
        refs = re.findall(r'\b[A-F0-9]{24}\b',text)
        assert set(refs) <= set(objects), 'Unknown project object'
        for source in app_sources:
            assert text.count('path = "'+source+'";') == 1, f'Missing or duplicate source {source}'
        assert 'relativePath = Packages/ClassNoteCore' in text
        if project.stem == 'ClassNoteAI': assert 'XCRemoteSwiftPackageReference' not in text
        else: assert 'version = 0.9.0' in text
        ElementTree.parse(project/'project.xcworkspace/contents.xcworkspacedata')
        for scheme in (project/'xcshareddata/xcschemes').glob('*.xcscheme'): ElementTree.parse(scheme)
        checked += 1
    icon = json.loads((ROOT/'Resources/Assets.xcassets/AppIcon.appiconset/Contents.json').read_text())
    assert (ROOT/'Resources/Assets.xcassets/AppIcon.appiconset'/icon['images'][0]['filename']).exists()
    for path in ('katex.min.js','katex.min.css','math.html','KATEX-LICENSE.txt'):
        assert (ROOT/'Resources/Math'/path).stat().st_size > 10
    html = (ROOT/'Resources/Math/math.html').read_text()
    assert "connect-src 'none'" in html and 'trust:false' in html
    assert 'https://' not in html
    speech = (ROOT/'Transcription/AppleSpeechTranscriber.swift').read_text()
    assert 'request.requiresOnDeviceRecognition = true' in speech
    assert 'recognizer.supportsOnDeviceRecognition' in speech
    assert 'URLSession' not in (ROOT/'Audio/AudioCapture.swift').read_text()
    checked += 3
    print(f'PASS: {checked} structural groups, {len(app_sources)} app Swift sources, 2 Xcode projects.')
    return checked

if __name__ == '__main__': check()
