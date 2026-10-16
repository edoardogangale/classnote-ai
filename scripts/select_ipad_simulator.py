#!/usr/bin/env python3
"""Choose an installed iPad runtime compatible with the selected Xcode SDK."""
import json
import os
import re
import subprocess


def select(data, sdk):
    supported = tuple(int(n) for n in sdk.split('.')[:2])
    candidates = []
    for runtime, devices in data['devices'].items():
        match = re.search(r'SimRuntime\.iOS-(\d+)-(\d+)', runtime)
        if not match:
            continue
        version = (int(match.group(1)), int(match.group(2)))
        if version[0] != supported[0] or version > supported:
            continue
        for device in devices:
            if device.get('isAvailable') and 'iPad' in device['name']:
                candidates.append((version, device['name'], device['udid']))
    if not candidates:
        raise RuntimeError(f'No available iPad simulator compatible with SDK {sdk}. See runner toolchain log.')
    return sorted(candidates, reverse=True)[0]


if __name__ == '__main__':
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'], text=True).strip()
    data = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], text=True))
    version, name, udid = select(data, sdk)
    with open(os.environ['GITHUB_ENV'], 'a') as environment:
        environment.write('CLASSNOTE_DEVICE_ID=' + udid + '\n')
    print(f'Selected {name}, runtime {version[0]}.{version[1]}, SDK {sdk}.')
