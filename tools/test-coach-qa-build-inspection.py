#!/usr/bin/env python3
"""Behavioral rejection checks over built public plist and generated scheme output contracts."""
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('inspect_coach_qa', ROOT / 'tools/inspect-coach-qa-build.py')
inspector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inspector)
APP = ROOT / 'build/coach-iphone-qa/device/Build/Products/CoachDeviceQA-iphoneos/RepToday.app'
SCHEME = ROOT / 'ios/RepToday/RepToday.xcodeproj/xcshareddata/xcschemes/RepTodayCoachDeviceQA.xcscheme'


class BuildInspectionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(dir=ROOT / 'build/coach-iphone-qa')
        self.app = Path(self.directory.name)
        with (APP / 'Info.plist').open('rb') as stream:
            self.info = plistlib.load(stream)
        self.scheme = self.app / 'qa.xcscheme'
        self.scheme.write_bytes(SCHEME.read_bytes())
        self.write_info()

    def tearDown(self):
        self.directory.cleanup()

    def write_info(self):
        with (self.app / 'Info.plist').open('wb') as stream:
            plistlib.dump(self.info, stream)

    def inspect(self):
        return inspector.inspect(self.app, 'CoachDeviceQA', self.scheme)

    def test_actual_built_qa_contract_is_accepted(self):
        self.assertTrue(self.inspect())

    def test_endpoint_mode_secret_flag_and_configuration_mismatches_fail(self):
        for key, value in [('RepTodayCoachEndpoint', ''),
                           ('RepTodayCoachEndpoint', 'https://fixture.invalid/coach'),
                           ('RepTodayCoachAuthMode', 'bearer'),
                           ('RepTodayCoachSecret', 'NONSECRET_TEST_FIXTURE'),
                           ('RepTodayCoachSyntheticQA', '0'),
                           ('RepTodayBuildConfiguration', 'Release'),
                           ('RepTodayAnalyticsEndpoint', 'https://fixture.invalid')]:
            original = self.info[key]
            self.info[key] = value
            self.write_info()
            with self.assertRaises(ValueError):
                self.inspect()
            self.info[key] = original

    def test_ordinary_configuration_cannot_accept_enabled_qa_output(self):
        with self.assertRaises(ValueError):
            inspector.inspect(self.app, 'Debug', self.scheme)

    def test_local_storekit_attachment_is_rejected(self):
        tree = ET.parse(self.scheme)
        ET.SubElement(tree.getroot().find('LaunchAction'), 'StoreKitConfigurationFileReference', identifier='fixture.storekit')
        tree.write(self.scheme)
        with self.assertRaises(ValueError):
            self.inspect()

    def test_run_configuration_mismatch_is_rejected(self):
        tree = ET.parse(self.scheme)
        tree.getroot().find('LaunchAction').set('buildConfiguration', 'Debug')
        tree.write(self.scheme)
        with self.assertRaises(ValueError):
            self.inspect()


if __name__ == '__main__':
    unittest.main()
