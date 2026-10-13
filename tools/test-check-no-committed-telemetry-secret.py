#!/usr/bin/env python3
"""Tests for check-no-committed-telemetry-secret.py. Every value here is plainly fake."""

import importlib.util
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHECK = ROOT / 'tools/check-no-committed-telemetry-secret.py'
PLANTED = 'plainly-fake-planted-value'

spec = importlib.util.spec_from_file_location('check', CHECK)
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class CommittedSecretCheckTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name).resolve()
        subprocess.run(['git', '-C', str(self.root), 'init', '-q'], check=True)
        self.write('.gitignore', 'ios/RepToday/Config/DebugTelemetry.local.xcconfig\n')

    def tearDown(self):
        self.directory.cleanup()

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def run_check(self):
        return subprocess.run(['python3', str(CHECK), str(self.root)],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def assert_flagged(self, name, text):
        self.write(name, text)
        result = self.run_check()
        self.assertEqual(result.returncode, 1, f'{name} was not flagged')
        self.assertIn(f'{name}:', result.stdout)
        self.assertNotIn(PLANTED, result.stdout + result.stderr)
        (self.root / name).unlink()

    def test_this_repository_commits_no_value(self):
        self.assertEqual(check.findings_in(ROOT), [])

    def test_empty_placeholder_and_reference_values_pass(self):
        self.write('ios/RepToday/project.yml',
                   '          REPTODAY_ANALYTICS_SECRET: ""\n      # sets no `REPTODAY_ANALYTICS_SECRET` below\n')
        self.write('ios/RepToday/RepToday.xcodeproj/project.pbxproj', '\t\t\t\tREPTODAY_ANALYTICS_SECRET = "";\n')
        self.write('ios/RepToday/Config/DebugTelemetry.xcconfig',
                   '//   REPTODAY_ANALYTICS_SECRET = <value>\nREPTODAY_ANALYTICS_SECRET =\n'
                   'REPTODAY_ANALYTICS_SECRET = $(inherited)\n')
        self.write('.github/workflows/ci.yml',
                   '  REPTODAY_ANALYTICS_ENDPOINT= REPTODAY_ANALYTICS_SECRET= \\\n')
        self.write('ios/RepToday/RepToday/Info.plist',
                   plistlib.dumps({'RepTodayAnalyticsSecret': '$(REPTODAY_ANALYTICS_SECRET)'}).decode())
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_a_value_in_the_project_spec_is_flagged(self):
        self.assert_flagged('ios/RepToday/project.yml', f'          REPTODAY_ANALYTICS_SECRET: {PLANTED}\n')
        self.assert_flagged('ios/RepToday/project.yml', f'          REPTODAY_ANALYTICS_SECRET: "{PLANTED}"\n')

    def test_a_value_in_the_generated_project_is_flagged(self):
        self.assert_flagged('ios/RepToday/RepToday.xcodeproj/project.pbxproj',
                            f'\t\t\t\tREPTODAY_ANALYTICS_SECRET = {PLANTED};\n')
        self.assert_flagged('ios/RepToday/RepToday.xcodeproj/project.pbxproj',
                            f'\t\t\t\t"REPTODAY_ANALYTICS_SECRET[sdk=iphoneos*]" = {PLANTED};\n')

    def test_a_value_in_a_tracked_xcconfig_scheme_or_workflow_is_flagged(self):
        self.assert_flagged('ios/RepToday/Config/DebugTelemetry.xcconfig', f'REPTODAY_ANALYTICS_SECRET = {PLANTED}\n')
        self.assert_flagged('ios/RepToday/Config/DebugTelemetry.xcconfig', f'// REPTODAY_ANALYTICS_SECRET = {PLANTED}\n')
        self.assert_flagged('ios/RepToday/RepToday.xcodeproj/xcshareddata/xcschemes/RepToday.xcscheme',
                            f'<arg value="REPTODAY_ANALYTICS_SECRET={PLANTED}"/>\n')
        self.assert_flagged('.github/workflows/ci.yml', f'            REPTODAY_ANALYTICS_SECRET={PLANTED} \\\n')

    def test_a_literal_info_plist_value_is_flagged(self):
        self.write('ios/RepToday/RepToday/Info.plist', plistlib.dumps({'RepTodayAnalyticsSecret': PLANTED}).decode())
        result = self.run_check()
        self.assertEqual(result.returncode, 1)
        self.assertNotIn(PLANTED, result.stdout + result.stderr)

    def test_a_debug_target_level_key_that_would_override_the_xcconfig_is_flagged(self):
        block = ('\t\t0000 /* Debug */ = {\n\t\t\tisa = XCBuildConfiguration;\n'
                 '\t\t\tbaseConfigurationReference = 1111 /* DebugTelemetry.xcconfig */;\n'
                 '\t\t\tbuildSettings = {\n\t\t\t\tREPTODAY_ANALYTICS_ENDPOINT = "https://example.invalid";\n'
                 '%s\t\t\t};\n\t\t\tname = Debug;\n\t\t};\n')
        name = 'ios/RepToday/RepToday.xcodeproj/project.pbxproj'
        self.write(name, block % '')
        self.assertEqual(self.run_check().returncode, 0)
        self.write(name, block % '\t\t\t\tREPTODAY_ANALYTICS_SECRET = "";\n')
        result = self.run_check()
        self.assertEqual(result.returncode, 1)
        self.assertIn('overrides the xcconfig', result.stdout)

    def test_the_ignored_private_xcconfig_is_not_read(self):
        self.write('ios/RepToday/Config/DebugTelemetry.local.xcconfig', f'REPTODAY_ANALYTICS_SECRET = {PLANTED}\n')
        self.assertEqual(self.run_check().returncode, 0)


if __name__ == '__main__':
    unittest.main()
