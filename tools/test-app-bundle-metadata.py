#!/usr/bin/env python3
"""Fixture-level regression coverage for processed app bundle metadata validation."""

from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
VALIDATOR = ROOT / 'tools/validate-app-bundle-metadata.py'


def passing_info():
    return {
        'RepTodayClerkPublishableKey': 'pk_test_ZXhhbXBsZS5jbGVyay5hY2NvdW50cy5kZXYk',
        'RepTodayConvexURL': 'https://example-dev-123.convex.cloud',
        'NSHealthShareUsageDescription': 'Checks prior Rep Today workouts to avoid duplicates.',
        'NSHealthUpdateUsageDescription': 'Saves completed Rep Today workouts.',
        'UIDeviceFamily': [1, 2],
        'UISupportedInterfaceOrientations~iphone': ['UIInterfaceOrientationPortrait'],
        'UISupportedInterfaceOrientations~ipad': [
            'UIInterfaceOrientationPortrait',
            'UIInterfaceOrientationPortraitUpsideDown',
            'UIInterfaceOrientationLandscapeLeft',
            'UIInterfaceOrientationLandscapeRight',
        ],
    }


class AppBundleMetadataValidationTests(unittest.TestCase):
    def validate(self, info, release=False):
        with tempfile.TemporaryDirectory() as directory:
            plist = Path(directory) / 'Info.plist'
            with plist.open('wb') as stream:
                plistlib.dump(info, stream)
            return subprocess.run(
                [sys.executable, str(VALIDATOR), str(plist)] + (['--release'] if release else []),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )

    def assert_rejected(self, info, field):
        result = self.validate(info)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(field, result.stderr)

    def test_missing_or_unexpanded_account_configuration_is_rejected(self):
        for key in ['RepTodayClerkPublishableKey', 'RepTodayConvexURL']:
            info = passing_info()
            del info[key]
            self.assert_rejected(info, key)
            info[key] = ''
            self.assert_rejected(info, key)
            info[key] = '$(REPTODAY_CLERK_PUBLISHABLE_KEY)'
            self.assert_rejected(info, key)

    def test_a_secret_key_or_a_wrong_backend_is_rejected(self):
        info = passing_info()
        info['RepTodayClerkPublishableKey'] = 'sk_test_never_ship_this'
        self.assert_rejected(info, 'RepTodayClerkPublishableKey')
        info = passing_info()
        info['RepTodayConvexURL'] = 'https://example-dev-123.convex.site'
        self.assert_rejected(info, 'RepTodayConvexURL')

    def test_a_release_requires_the_production_clerk_instance(self):
        result = self.validate(passing_info(), release=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('production instance key', result.stderr)
        info = passing_info()
        info['RepTodayClerkPublishableKey'] = 'pk_live_Y2xlcmsucmVwdG9kYXkuYXBwJA'
        result = self.validate(info, release=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('the production account configuration', result.stdout)

    def test_passing_universal_bundle_metadata_is_accepted(self):
        result = self.validate(passing_info())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('verified: processed app plist', result.stdout)

    def test_original_missing_health_share_shape_is_rejected(self):
        info = passing_info()
        del info['NSHealthShareUsageDescription']
        self.assert_rejected(info, 'NSHealthShareUsageDescription')

    def test_original_missing_ipad_orientations_shape_is_rejected(self):
        info = passing_info()
        del info['UISupportedInterfaceOrientations~ipad']
        self.assert_rejected(info, 'UISupportedInterfaceOrientations~ipad')

    def test_missing_or_blank_health_descriptions_are_rejected(self):
        for key in ['NSHealthShareUsageDescription', 'NSHealthUpdateUsageDescription']:
            for value in [None, '', '   ']:
                with self.subTest(key=key, value=value):
                    info = passing_info()
                    if value is None:
                        del info[key]
                    else:
                        info[key] = value
                    self.assert_rejected(info, key)

    def test_ipad_orientations_must_be_exactly_the_required_four(self):
        for orientations in [
            ['UIInterfaceOrientationPortrait'],
            passing_info()['UISupportedInterfaceOrientations~ipad'] + ['unexpected'],
            ['UIInterfaceOrientationPortrait'] * 4,
        ]:
            with self.subTest(orientations=orientations):
                info = passing_info()
                info['UISupportedInterfaceOrientations~ipad'] = orientations
                self.assert_rejected(info, 'UISupportedInterfaceOrientations~ipad')

    def test_iphone_orientation_device_family_and_multitasking_posture_are_guarded(self):
        mutations = [
            ('UISupportedInterfaceOrientations~iphone', [
                'UIInterfaceOrientationPortrait',
                'UIInterfaceOrientationLandscapeLeft',
            ]),
            ('UIDeviceFamily', [1]),
            ('UIRequiresFullScreen', True),
        ]
        for key, value in mutations:
            with self.subTest(key=key):
                info = passing_info()
                info[key] = value
                self.assert_rejected(info, key)


if __name__ == '__main__':
    unittest.main()
