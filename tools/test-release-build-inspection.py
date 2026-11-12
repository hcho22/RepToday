#!/usr/bin/env python3
"""Self-contained tests for tools/inspect-release-build.py over synthetic app bundles.

No archive, signing account, credential or network is needed: each case writes a minimal
Info.plist, executable and scheme into a temporary directory and checks the inspector accepts the
Release contract and refuses each way of breaking it.
"""
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('release_inspector', ROOT / 'tools/inspect-release-build.py')
inspector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inspector)

SCHEME = '''<?xml version="1.0" encoding="UTF-8"?>
<Scheme>
   <LaunchAction buildConfiguration="Debug"><StoreKitConfigurationFileReference identifier="x"/></LaunchAction>
   <ArchiveAction buildConfiguration="{config}">{storekit}</ArchiveAction>
</Scheme>
'''


class ReleaseInspectionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.app = Path(self.directory.name) / 'RepToday.app'
        self.app.mkdir()
        self.info = {
            'CFBundleExecutable': 'RepToday',
            'RepTodayBuildConfiguration': 'Release',
            'RepTodayConvexURL': 'https://example.convex.cloud',
            'RepTodayAnalyticsEndpoint': 'https://example.convex.site',
        }
        self.binary = b'\x00ordinary app code\x00coachProductionAppAttestKeyV1\x00'
        self.scheme = Path(self.directory.name) / 'RepToday.xcscheme'
        self.write(config='Release', storekit='')

    def tearDown(self):
        self.directory.cleanup()

    def write(self, config='Release', storekit=''):
        with (self.app / 'Info.plist').open('wb') as stream:
            plistlib.dump(self.info, stream)
        (self.app / 'RepToday').write_bytes(self.binary)
        self.scheme.write_text(SCHEME.format(config=config, storekit=storekit))

    def inspect(self):
        inspector.inspect(self.app, 'Release', self.scheme)

    def test_an_ordinary_release_is_accepted(self):
        # The leftover-key cleanup string AppState carries is not Coach client code.
        self.inspect()

    def test_any_coach_key_is_refused(self):
        for key in ['RepTodayCoachEndpoint', 'RepTodayCoachSecret', 'RepTodayCoachAuthMode', 'RepTodayCoachSyntheticQA']:
            self.info[key] = ''
            self.write()
            with self.assertRaises(ValueError, msg=key):
                self.inspect()
            del self.info[key]

    def test_retired_coach_code_is_refused(self):
        for marker in inspector.RETIRED_COACH_MARKERS:
            self.binary = b'\x00' + marker + b'\x00'
            self.write()
            with self.assertRaises(ValueError, msg=marker):
                self.inspect()

    def test_a_server_credential_or_wrong_configuration_is_refused(self):
        self.info['OPENAI_API_KEY'] = 'NONSECRET_TEST_FIXTURE'
        self.write()
        with self.assertRaises(ValueError):
            self.inspect()
        del self.info['OPENAI_API_KEY']
        self.info['RepTodayBuildConfiguration'] = 'Debug'
        self.write()
        with self.assertRaises(ValueError):
            self.inspect()

    def test_a_bundled_storekit_file_or_archive_attachment_is_refused(self):
        (self.app / 'RepToday.storekit').write_text('{}')
        with self.assertRaises(ValueError):
            self.inspect()
        (self.app / 'RepToday.storekit').unlink()
        self.write(storekit='<StoreKitConfigurationFileReference identifier="x"/>')
        with self.assertRaises(ValueError):
            self.inspect()
        self.write(config='Debug')
        with self.assertRaises(ValueError):
            self.inspect()


if __name__ == '__main__':
    unittest.main()
