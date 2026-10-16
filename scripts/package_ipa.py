#!/usr/bin/env python3
"""Package a real, unsigned iPad device build. This does not compile or sign an app."""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import stat
import zipfile


def package(app: Path, destination: Path):
    app = app.resolve()
    if not app.is_dir() or app.suffix != '.app':
        raise ValueError('Missing .app directory: the device build must succeed first.')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    executable = info.get('CFBundleExecutable', '')
    if not executable or Path(executable).name != executable or not (app / executable).is_file():
        raise ValueError('Missing or invalid CFBundleExecutable in device build.')
    if 'iPhoneOS' not in info.get('CFBundleSupportedPlatforms', []):
        raise ValueError('Not an iPhoneOS device build. Simulator binaries cannot be installed on an iPad.')
    if not info.get('CFBundleIdentifier'):
        raise ValueError('Missing bundle identifier.')
    destination = destination.resolve()
    if app == destination or app in destination.parents:
        raise ValueError('Place output outside the .app directory.')
    destination.parent.mkdir(parents=True, exist_ok=True)
    prefix = Path('Payload') / app.name
    with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        # Preserve native permissions and symlinks, including any embedded Swift libraries.
        for directory, folders, files in os.walk(app, followlinks=False):
            for name in sorted(folders + files):
                path = Path(directory) / name
                relative = prefix / path.relative_to(app)
                if path.is_symlink():
                    entry = zipfile.ZipInfo(relative.as_posix())
                    entry.create_system = 3
                    entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                    archive.writestr(entry, os.readlink(path))
                elif path.is_file():
                    archive.write(path, relative.as_posix())
    with zipfile.ZipFile(destination) as archive:
        if archive.testzip() is not None:
            raise ValueError('ZIP verification failed.')
        if (prefix / executable).as_posix() not in archive.namelist():
            raise ValueError('Executable not present inside Payload.')
    print('Packaged:', destination.name)
    print('Bundle:', info['CFBundleIdentifier'])
    print('SHA256:', hashlib.sha256(destination.read_bytes()).hexdigest())
    print('Unsigned: local signing is required. No physical iPad test has been performed by this script.')
    return destination


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    arguments = parser.parse_args()
    package(arguments.app, arguments.output)
