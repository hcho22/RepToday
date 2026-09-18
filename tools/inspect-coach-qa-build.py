#!/usr/bin/env python3
"""Inspect only public Coach configuration. Never print arbitrary plist values or secrets."""
import argparse
import plistlib
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

EXPECTED_ORIGIN = 'https://coach.reptoday.app/coach'
EXPECTED_MODE = 'app-attest-storekit-v1'


def inspect(app, configuration, scheme):
    with (app / 'Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    qa = configuration == 'CoachDeviceQA'
    expected = {
        'RepTodayBuildConfiguration': configuration,
        'RepTodayCoachEndpoint': EXPECTED_ORIGIN if qa else '',
        'RepTodayCoachSecret': '',
        'RepTodayCoachAuthMode': EXPECTED_MODE,
        'RepTodayCoachSyntheticQA': '1' if qa else '0',
    }
    if any(info.get(key) != value for key, value in expected.items()):
        raise ValueError('configuration')
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
    parser.add_argument('--scheme', type=Path, default=Path('ios/RepToday/RepToday.xcodeproj/xcshareddata/xcschemes/RepTodayCoachDeviceQA.xcscheme'))
    args = parser.parse_args()
    try:
        qa = inspect(args.app, args.configuration, args.scheme)
    except Exception:
        print('failed: built Coach configuration or QA scheme contract; no values printed', file=sys.stderr)
        return 1
    print('verified: {} public Coach endpoint {}; binary secret empty; {}; synthetic QA {}; no local StoreKit configuration for QA'.format(
        args.configuration, 'enabled at approved origin' if qa else 'empty', EXPECTED_MODE, 'enabled' if qa else 'disabled'))
    print('unverified: signing/profile, effective App Attest entitlement, physical-device installation, production purchase/service and live semantic QA')
    return 0


if __name__ == '__main__':
    sys.exit(main())
