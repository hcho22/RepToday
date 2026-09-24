#!/usr/bin/env python3
"""Check the actual Release archive's public plist/scheme contracts and early override denial.

Build a configuration-validation archive at build/coach-testflight/RepToday.xcarchive first.
The test reads only its public configuration; it uses no credential helper, production service,
signing account or model. Signing and production telemetry are separate release gates.
"""
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('coach_inspector', ROOT / 'tools/inspect-coach-qa-build.py')
inspector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inspector)
ARCHIVE = ROOT / 'build/coach-testflight/RepToday.xcarchive'
APP = ARCHIVE / 'Products/Applications/RepToday.app'
SCHEME = ROOT / 'ios/RepToday/RepToday.xcodeproj/xcshareddata/xcschemes/RepToday.xcscheme'


class ReleaseInspectionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(dir=ROOT / 'build/coach-testflight')
        self.app = Path(self.directory.name)
        with (APP / 'Info.plist').open('rb') as stream:
            self.info = plistlib.load(stream)
        self.scheme = self.app / 'release.xcscheme'
        self.scheme.write_bytes(SCHEME.read_bytes())
        self.write_info()

    def tearDown(self):
        self.directory.cleanup()

    def write_info(self):
        with (self.app / 'Info.plist').open('wb') as stream:
            plistlib.dump(self.info, stream)

    def inspect(self):
        return inspector.inspect(self.app, 'Release', self.scheme)

    def test_actual_archive_contract_is_accepted(self):
        self.assertFalse(self.inspect())  # Synthetic QA is disabled in the ordinary archive.

    def test_embedded_gate_wrong_mode_configuration_and_qa_fail_closed(self):
        for key, value in [('RepTodayCoachSecret', 'NONSECRET_TEST_FIXTURE'),
                           ('RepTodayCoachAuthMode', 'bearer'),
                           ('RepTodayBuildConfiguration', 'CoachDeviceQA'),
                           ('RepTodayCoachEndpoint', 'https://fixture.invalid/coach'),
                           ('RepTodayCoachEndpoint', ''),
                           ('RepTodayCoachSyntheticQA', '1')]:
            original = self.info[key]
            self.info[key] = value
            self.write_info()
            with self.assertRaises(ValueError):
                self.inspect()
            self.info[key] = original

    def test_missing_coach_configuration_is_rejected(self):
        del self.info['RepTodayCoachAuthMode']
        self.write_info()
        with self.assertRaises(ValueError):
            self.inspect()

    def test_server_credentials_are_not_a_binary_configuration(self):
        for key in inspector.SERVER_CREDENTIAL_KEYS:
            self.info[key] = 'NONSECRET_TEST_FIXTURE'
            self.write_info()
            with self.assertRaises(ValueError):
                self.inspect()
            del self.info[key]

    def test_local_storekit_file_cannot_ship_in_release(self):
        (self.app / "RepToday.storekit").write_text("{}")
        with self.assertRaises(ValueError):
            self.inspect()

    def test_archive_action_must_select_release(self):
        tree = ET.parse(self.scheme)
        tree.getroot().find('ArchiveAction').set('buildConfiguration', 'Debug')
        tree.write(self.scheme)
        with self.assertRaises(ValueError):
            self.inspect()

    def test_archive_action_cannot_attach_local_storekit(self):
        tree = ET.parse(self.scheme)
        ET.SubElement(tree.getroot().find('ArchiveAction'), 'StoreKitConfigurationFileReference', identifier='fixture.storekit')
        tree.write(self.scheme)
        with self.assertRaises(ValueError):
            self.inspect()


class ArchiveOverrideTests(unittest.TestCase):
    def test_coach_overrides_stop_before_any_credential_or_external_operation(self):
        for argument in ['REPTODAY_COACH_SECRET=NONSECRET_TEST_FIXTURE',
                         'REPTODAY_COACH_SECRET[sdk=iphoneos*]=NONSECRET_TEST_FIXTURE',
                         'REPTODAY_COACH_ENDPOINT=https://fixture.invalid/coach',
                         'REPTODAY_COACH_AUTH_MODE=bearer',
                         'REPTODAY_COACH_SYNTHETIC_QA=1',
                         'INFOPLIST_KEY_RepTodayCoachSecret=NONSECRET_TEST_FIXTURE',
                         'INFOPLIST_KEY_RepTodayBuildConfiguration=Debug']:
            result = subprocess.run(['bash', str(ROOT / 'tools/archive-release.sh'),
                                     str(ARCHIVE), argument], cwd=ROOT,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
            self.assertEqual(result.returncode, 64)
            self.assertEqual(result.stdout, b'')
            self.assertEqual(result.stderr, b'error: additional arguments cannot override the archive, telemetry or Coach configuration\n')


if __name__ == '__main__':
    unittest.main()
