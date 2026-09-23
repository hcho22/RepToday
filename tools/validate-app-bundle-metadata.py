#!/usr/bin/env python3
"""Validate App Store-sensitive metadata in a processed RepToday.app Info.plist."""

import argparse
from pathlib import Path
import plistlib
import sys


EXPECTED_IPAD_ORIENTATIONS = frozenset([
    'UIInterfaceOrientationPortrait',
    'UIInterfaceOrientationPortraitUpsideDown',
    'UIInterfaceOrientationLandscapeLeft',
    'UIInterfaceOrientationLandscapeRight',
])
EXPECTED_IPHONE_ORIENTATIONS = ['UIInterfaceOrientationPortrait']
EXPECTED_DEVICE_FAMILIES = frozenset([1, 2])


def validation_errors(info):
    errors = []

    for key in ['NSHealthShareUsageDescription', 'NSHealthUpdateUsageDescription']:
        value = info.get(key)
        if not isinstance(value, str) or not value.strip():
            errors.append(f'{key} must be a nonblank string')

    ipad_orientations = info.get('UISupportedInterfaceOrientations~ipad')
    if (
        not isinstance(ipad_orientations, list)
        or len(ipad_orientations) != len(EXPECTED_IPAD_ORIENTATIONS)
        or not all(isinstance(orientation, str) for orientation in ipad_orientations)
        or set(ipad_orientations) != EXPECTED_IPAD_ORIENTATIONS
    ):
        errors.append(
            'UISupportedInterfaceOrientations~ipad must contain exactly portrait, '
            'portrait-upside-down, landscape-left, and landscape-right'
        )

    if info.get('UISupportedInterfaceOrientations~iphone') != EXPECTED_IPHONE_ORIENTATIONS:
        errors.append('UISupportedInterfaceOrientations~iphone must remain portrait-only')

    device_families = info.get('UIDeviceFamily')
    if (
        not isinstance(device_families, list)
        or len(device_families) != len(EXPECTED_DEVICE_FAMILIES)
        or not all(isinstance(family, int) and not isinstance(family, bool) for family in device_families)
        or set(device_families) != EXPECTED_DEVICE_FAMILIES
    ):
        errors.append('UIDeviceFamily must remain the universal [1, 2] family')

    requires_full_screen = info.get('UIRequiresFullScreen')
    if requires_full_screen not in (None, False, 0, 'NO', 'false', '0'):
        errors.append('UIRequiresFullScreen must not opt the universal app out of iPad multitasking')

    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('plist', type=Path, help='processed RepToday.app/Info.plist')
    args = parser.parse_args()

    try:
        with args.plist.open('rb') as stream:
            info = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as error:
        print(f'error: cannot read processed app plist: {error}', file=sys.stderr)
        return 1

    errors = validation_errors(info)
    if errors:
        for error in errors:
            print(f'error: {error}', file=sys.stderr)
        return 1

    print(
        'verified: processed app plist has both Health usage descriptions, portrait-only iPhone '
        'orientation, all four iPad orientations, universal device support, and iPad multitasking'
    )
    return 0


if __name__ == '__main__':
    sys.exit(main())
