#!/usr/bin/env python3
"""Checks packaging invariants; does not compile or run any Apple framework."""
from pathlib import Path
import plistlib
from prepare_ipad import APP_FOLDERS, DEST, ROOT


def check():
    manifest = (DEST / 'Package.swift').read_text()
    assert '// swift-tools-version: 5.9' in manifest
    assert '.iOSApplication(' in manifest and 'canImport(AppleProductTypes)' in manifest
    assert '.iOS(.v17)' in manifest
    assert 'https://' not in manifest and '.package(' not in manifest
    assert '.linkedLibrary("sqlite3")' in manifest
    for capability in ('microphone', 'speechRecognition', 'camera'):
        assert f'.{capability}(purposeString:' in manifest
    info = plistlib.loads((DEST / 'AppInfo.plist').read_bytes())
    assert info['UIBackgroundModes'] == ['audio']
    assert info['UIRequiresFullScreen'] is False
    assert all('$(' not in str(value) for value in info.values())
    assert 'UIApplicationSceneManifest' not in info
    originals = [p for folder in APP_FOLDERS for p in (ROOT / folder).glob('*.swift')]
    for source in originals:
        copy = DEST / 'App' / source.relative_to(ROOT)
        assert source.read_bytes() == copy.read_bytes(), f'Outdated app source: {copy}'
    for source in (ROOT / 'Packages/ClassNoteCore/Sources/ClassNoteCore').glob('*.swift'):
        assert source.read_bytes() == (DEST / 'Core' / source.name).read_bytes()
    for source in (ROOT / 'Packages/ClassNoteCore/Tests/ClassNoteCoreTests').glob('*.swift'):
        assert source.read_bytes() == (DEST / 'CoreTests' / source.name).read_bytes()
    assert sum('@main ' in p.read_text() for p in (DEST / 'App').rglob('*.swift')) == 1
    formula = (DEST / 'App/Notebook/FormulaEditor.swift').read_text()
    assert 'let resources = Bundle.module' not in formula
    assert 'MathResources.htmlURL' in formula
    for source in (ROOT / 'Resources/Math').rglob('*'):
        if source.is_file():
            assert source.read_bytes() == (DEST / 'App/Resources/Math' / source.relative_to(ROOT / 'Resources/Math')).read_bytes()
    privacy = plistlib.loads((DEST / 'App/Resources/PrivacyInfo.xcprivacy').read_bytes())
    assert not privacy['NSPrivacyTracking']
    assert (DEST.parent / 'LEGGIMI_IPAD.txt').stat().st_size > 1000
    print(f'PASS: app playground structure, {len(originals)} identical app sources, core/tests, permissions, plist, local resources.')
    print('NOT TESTED: Apple SDK type checking, Swift Playground launch, microphone, Pencil, Goodnotes, background.')


if __name__ == '__main__':
    check()
