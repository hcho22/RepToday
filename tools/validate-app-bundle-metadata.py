#!/usr/bin/env python3
"""Validate App Store-sensitive metadata in a processed RepToday.app Info.plist."""

import argparse
from pathlib import Path
import plistlib
import re
import sys


EXPECTED_IPAD_ORIENTATIONS = frozenset([
    'UIInterfaceOrientationPortrait',
    'UIInterfaceOrientationPortraitUpsideDown',
    'UIInterfaceOrientationLandscapeLeft',
    'UIInterfaceOrientationLandscapeRight',
])
EXPECTED_IPHONE_ORIENTATIONS = ['UIInterfaceOrientationPortrait']
EXPECTED_DEVICE_FAMILIES = frozenset([1, 2])

# The account backend (M3, ADR-0016). Sign-in is required, so a build without a usable Clerk key cannot
# be used at all; a release must sign in against the production Clerk instance (`pk_live_`), while a
# development build uses the development instance (`pk_test_`). The Convex URL is the `.convex.cloud`
# origin the app syncs to.
CLERK_KEY_PATTERN = re.compile(r'^pk_(test|live)_[A-Za-z0-9+/=_-]+$')
CONVEX_URL_PATTERN = re.compile(r'^https://[a-z0-9-]+\.convex\.cloud/?$')


def account_errors(info, release):
    errors = []
    key = info.get('RepTodayClerkPublishableKey')
    if not isinstance(key, str) or not CLERK_KEY_PATTERN.match(key.strip()):
        errors.append('RepTodayClerkPublishableKey must be a Clerk publishable key (pk_test_... or pk_live_...)')
    elif release and not key.strip().startswith('pk_live_'):
        errors.append('RepTodayClerkPublishableKey must be the production instance key (pk_live_...) in a release')
    url = info.get('RepTodayConvexURL')
    if not isinstance(url, str) or not CONVEX_URL_PATTERN.match(url.strip()):
        errors.append('RepTodayConvexURL must be a https://<deployment>.convex.cloud origin')
    return errors


def validation_errors(info, release=False):
    errors = account_errors(info, release)

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
    parser.add_argument(
        '--release',
        action='store_true',
        help='also require the production Clerk instance (pk_live_) for a distributable archive',
    )
    args = parser.parse_args()

    try:
        with args.plist.open('rb') as stream:
            info = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as error:
        print(f'error: cannot read processed app plist: {error}', file=sys.stderr)
        return 1

    errors = validation_errors(info, release=args.release)
    if errors:
        for error in errors:
            print(f'error: {error}', file=sys.stderr)
        return 1

    print(
        'verified: processed app plist has both Health usage descriptions, portrait-only iPhone '
        'orientation, all four iPad orientations, universal device support, iPad multitasking, and '
        + ('the production account configuration' if args.release else 'a well-formed account configuration')
    )
    return 0


if __name__ == '__main__':
    sys.exit(main())
