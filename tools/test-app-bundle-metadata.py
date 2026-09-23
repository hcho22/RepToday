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
    def validate(self, info):
        with tempfile.TemporaryDirectory() as directory:
            plist = Path(directory) / 'Info.plist'
            with plist.open('wb') as stream:
                plistlib.dump(info, stream)
            return subprocess.run(
                [sys.executable, str(VALIDATOR), str(plist)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )

    def assert_rejected(self, info, field):
        result = self.validate(info)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(field, result.stderr)

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
