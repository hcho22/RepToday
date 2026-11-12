#!/usr/bin/env python3
"""Inspect a built Release app's public configuration contract. Never prints plist values or secrets.

Since M4 (ADR-0017) the Coach runs on the account backend, so a Release build carries no Coach
configuration of its own: no `RepTodayCoach*` Info.plist key, and no code that reaches the retired
Cloudflare Coach route or its staging lane. The other checks are the archive's standing contract: no
server credential in the plist, no bundled local StoreKit fixture, and an archive action that selects
Release without a local StoreKit attachment.
"""
import argparse
import plistlib
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

# Strings only the retired Cloudflare Coach client carried. A Release executable must contain none.
RETIRED_COACH_MARKERS = (
    b'coach.reptoday.app',
    b'reptoday-coach-staging',
    b'X-RepToday-Coach-Assertion-Digest',
    b'app-attest-storekit-v1',
)
SERVER_CREDENTIAL_KEYS = frozenset([
    'OPENAI_API_KEY', 'ANTHROPIC_API_KEY', 'CLIENT_SHARED_SECRET', 'CLERK_SECRET_KEY',
    'APP_STORE_PRIVATE_KEY', 'APP_STORE_KEY_ID', 'APP_STORE_ISSUER_ID', 'CONVEX_DEPLOY_KEY',
])


def inspect(app, configuration, scheme):
    with (app / 'Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    if any(key.upper() in SERVER_CREDENTIAL_KEYS for key in info):
        raise ValueError('server-credential')
    if info.get('RepTodayBuildConfiguration') != configuration:
        raise ValueError('configuration')
    if any(key.startswith('RepTodayCoach') for key in info):
        raise ValueError('retired-coach-configuration')
    if configuration == 'Release':
        if any(app.rglob('*.storekit')):
            raise ValueError('bundled-local-storekit')
        executable = app / str(info.get('CFBundleExecutable', ''))
        if not info.get('CFBundleExecutable') or not executable.is_file():
            raise ValueError('executable')
        binary = executable.read_bytes()
        if any(marker in binary for marker in RETIRED_COACH_MARKERS):
            raise ValueError('retired-coach-code')
        tree = ET.parse(scheme)
        archive = tree.getroot().find('ArchiveAction')
        if archive is None or archive.get('buildConfiguration') != 'Release':
            raise ValueError('archive-configuration')
        if archive.find('.//StoreKitConfigurationFileReference') is not None:
            raise ValueError('archive-local-storekit')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--configuration', required=True, choices=['Debug', 'Release'])
    parser.add_argument('--scheme', type=Path,
                        default=Path('ios/RepToday/RepToday.xcodeproj/xcshareddata/xcschemes/RepToday.xcscheme'))
    args = parser.parse_args()
    try:
        inspect(args.app, args.configuration, args.scheme)
    except Exception:
        print('failed: built app configuration or scheme contract; no values printed', file=sys.stderr)
        return 1
    print('verified: {} carries no Coach configuration and no server credential'.format(args.configuration))
    if args.configuration == 'Release':
        print('verified: no bundled local StoreKit fixture')
        print('verified: archive action selects Release without a local StoreKit attachment')
        print('verified: Release executable carries no retired Cloudflare Coach code')
    print('unverified: signing/profile, physical-device installation, production purchase and backend')
    return 0


if __name__ == '__main__':
    sys.exit(main())
