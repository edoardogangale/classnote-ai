#!/usr/bin/env python3
"""Export repository-root sources for upload to GitHub, without generated iPad packages."""
import argparse
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED = {'.git', '.build', 'build', 'iPad', 'DerivedData', 'xcuserdata', '__pycache__', 'verification-local'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    destination = parser.parse_args().output.resolve()
    selected = sorted(p for p in ROOT.rglob('*') if p.is_file()
                      and not any(part in EXCLUDED for part in p.relative_to(ROOT).parts)
                      and p.suffix not in {'.zip', '.ipa', '.caf', '.m4a', '.sqlite', '.drawing', '.pyc'}
                      and p.name != '.DS_Store')
    with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in selected:
            archive.write(path, path.relative_to(ROOT).as_posix())
    with zipfile.ZipFile(destination) as archive:
        assert archive.testzip() is None
        assert '.github/workflows/build-ipad.yml' in archive.namelist()
        assert 'ClassNoteAI.xcodeproj/project.pbxproj' in archive.namelist()
        assert 'INIZIA_QUI_WINDOWS.md' in archive.namelist()
        assert len(archive.namelist()) == len(set(archive.namelist()))
    batches = {
        'First upload (everything except Resources and .github)': [p for p in selected if p.relative_to(ROOT).parts[0] not in {'Resources', '.github'}],
        'Second upload (Resources)': [p for p in selected if p.relative_to(ROOT).parts[0] == 'Resources'],
        'Third upload (.github)': [p for p in selected if p.relative_to(ROOT).parts[0] == '.github']
    }
    for label, paths in batches.items():
        assert len(paths) <= 100, 'Split browser uploads further before delivering.'
        print(f'{label}: {len(paths)} files')
    print(f'Packaged {destination.name}: {len(selected)} files, {destination.stat().st_size} bytes.')


if __name__ == '__main__':
    main()
