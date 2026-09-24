#!/usr/bin/env python3
"""Inspect only public Coach configuration. Never print arbitrary plist values or secrets."""
import argparse
import plistlib
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

EXPECTED_ORIGIN = 'https://coach.reptoday.app/coach'
EXPECTED_MODE = 'app-attest-storekit-v1'
SERVER_CREDENTIAL_KEYS = frozenset([
    'OPENAI_API_KEY', 'ANTHROPIC_API_KEY', 'CLIENT_SHARED_SECRET',
    'APP_STORE_PRIVATE_KEY', 'APP_STORE_KEY_ID', 'APP_STORE_ISSUER_ID',
])


def inspect(app, configuration, scheme):
    with (app / 'Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    if any(key.upper() in SERVER_CREDENTIAL_KEYS for key in info):
        raise ValueError('server-credential')
    qa = configuration == 'CoachDeviceQA'
    expected = {
        'RepTodayBuildConfiguration': configuration,
        'RepTodayCoachEndpoint': EXPECTED_ORIGIN if qa or configuration == 'Release' else '',
        'RepTodayCoachSecret': '',
        'RepTodayCoachAuthMode': EXPECTED_MODE,
        'RepTodayCoachSyntheticQA': '1' if qa else '0',
    }
    if any(info.get(key) != value for key, value in expected.items()):
        raise ValueError('configuration')
    if configuration in ('Release', 'CoachDeviceQA') and any(app.rglob('*.storekit')):
        raise ValueError('bundled-local-storekit')
    if configuration == 'Release':
        tree = ET.parse(scheme)
        archive = tree.getroot().find('ArchiveAction')
        if archive is None or archive.get('buildConfiguration') != 'Release':
            raise ValueError('archive-configuration')
        if archive.find('.//StoreKitConfigurationFileReference') is not None:
            raise ValueError('archive-local-storekit')
    if qa:
        if info.get('RepTodayAnalyticsEndpoint') != '' or info.get('RepTodayAnalyticsSecret') != '':
            raise ValueError('qa-telemetry')
        tree = ET.parse(scheme)
        for action in ['LaunchAction', 'TestAction', 'ProfileAction', 'AnalyzeAction', 'ArchiveAction']:
            node = tree.getroot().find(action)
            if node is None or node.get('buildConfiguration') != 'CoachDeviceQA':
                raise ValueError('scheme-configuration')
        if tree.getroot().find('.//StoreKitConfigurationFileReference') is not None:
            raise ValueError('local-storekit')
    return qa


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--configuration', required=True, choices=['Debug', 'Release', 'CoachDeviceQA'])
    parser.add_argument('--scheme', type=Path)
    args = parser.parse_args()
    if args.scheme is None:
        name = 'RepTodayCoachDeviceQA' if args.configuration == 'CoachDeviceQA' else 'RepToday'
        args.scheme = Path('ios/RepToday/RepToday.xcodeproj/xcshareddata/xcschemes') / (name + '.xcscheme')
    try:
        qa = inspect(args.app, args.configuration, args.scheme)
    except Exception:
        print('failed: built Coach configuration or QA scheme contract; no values printed', file=sys.stderr)
        return 1
    print('verified: {} public Coach endpoint {}; binary secret empty; {}; synthetic QA {}'.format(
        args.configuration, 'enabled at approved origin' if qa or args.configuration == 'Release' else 'empty', EXPECTED_MODE, 'enabled' if qa else 'disabled'))
    if args.configuration in ('Release', 'CoachDeviceQA'):
        print('verified: no bundled local StoreKit fixture')
    if args.configuration == 'Release':
        print('verified: archive action selects Release without a local StoreKit attachment')
    print('unverified: signing/profile, effective App Attest entitlement, physical-device installation, production purchase/service and live semantic QA')
    return 0


if __name__ == '__main__':
    sys.exit(main())
