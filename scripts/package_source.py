#!/usr/bin/env python3
"""Package only deliverable source/resources/docs, excluding build products and user data."""
from pathlib import Path
import argparse
import zipfile
import hashlib
from prepare_ipad import prepare

ROOT=Path(__file__).resolve().parents[1]
EXCLUDED={'.git','.build','DerivedData','xcuserdata','__pycache__','verification-local'}

def files():
    return sorted(p for p in ROOT.rglob('*') if p.is_file() and not any(x in EXCLUDED for x in p.relative_to(ROOT).parts)
                  and p.name != '.DS_Store' and not p.name.endswith(('.zip','.xcuserstate','.pyc')))

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('output',type=Path)
    destination=parser.parse_args().output.resolve()
    prepare()
    selected=files()
    assert not any(p.suffix in ('.caf','.m4a','.sqlite','.drawing') for p in selected),'User data cannot be packaged'
    with zipfile.ZipFile(destination,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for path in selected:
            relative = path.relative_to(ROOT)
            # The first item to open on iPad is visible immediately after extraction.
            archive_path = Path(*relative.parts[1:]) if relative.parts[0] == 'iPad' else Path('ClassNoteAI')/relative
            z.write(path, archive_path)
    with zipfile.ZipFile(destination) as z:
        assert z.testzip() is None
        assert 'ClassNoteAI/README.md' in z.namelist()
        assert 'ClassNoteAI/ClassNoteAI.xcodeproj/project.pbxproj' in z.namelist()
        assert 'ClassNoteAI/ClassNoteAIWhisper.xcodeproj/project.pbxproj' in z.namelist()
        assert 'ClassNoteAI.swiftpm/Package.swift' in z.namelist()
        assert 'ClassNoteAI.swiftpm/AppInfo.plist' in z.namelist()
        assert 'LEGGIMI_IPAD.txt' in z.namelist()
    print(f'{destination.name}: {len(selected)} files, {destination.stat().st_size} bytes')
    print('SHA-256:',hashlib.sha256(destination.read_bytes()).hexdigest())

if __name__=='__main__': main()
