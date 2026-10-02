#!/usr/bin/env python3
"""Regression coverage for the build-time Trainer art gap report (US-TP05, `check-trainer-art.py`)."""

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
CHECKER = ROOT / 'tools/check-trainer-art.py'
CATALOG = ROOT / 'ios/RepToday/RepToday/Resources/Exercises.json'
TRAINER_ART = ROOT / 'ios/RepToday/RepToday/Resources/Assets.xcassets/Trainer'

TODAY = [
    'warning: Trainer art gap: pull_reverse_snow_angel (Reverse Snow Angel) is missing the male start pose',
    'warning: Trainer art gap: pull_reverse_snow_angel (Reverse Snow Angel) is missing the female start pose',
    'warning: Trainer art gap: pull_ytw (Prone Y-T-W Raises) is missing the male start and end poses',
    'warning: Trainer art gap: pull_ytw (Prone Y-T-W Raises) is missing the female start and end poses',
    'warning: Trainer art gap: pull_wall_scapular_pull (Wall Scapular Pull) is missing the male start pose',
    'warning: Trainer art gap: pull_wall_scapular_pull (Wall Scapular Pull) is missing the female start pose',
]


def run(catalog, assets):
    return subprocess.run(
        [sys.executable, str(CHECKER), str(catalog), str(assets)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, check=False,
    )


class TrainerArtGapReportTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.assets = Path(self.directory.name) / 'Assets.xcassets'
        # Image-set folders and their Contents.json only: the checker never reads the PNGs.
        shutil.copytree(TRAINER_ART, self.assets / 'Trainer', ignore=shutil.ignore_patterns('*.png'))

    def tearDown(self):
        self.directory.cleanup()

    def test_todays_art_reports_exactly_the_six_known_gaps_and_passes(self):
        result = run(CATALOG, self.assets)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), TODAY)

    def test_a_removed_pose_adds_a_warning(self):
        shutil.rmtree(self.assets / 'Trainer/female/hinge_glute_bridge-start.imageset')
        result = run(CATALOG, self.assets)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            'warning: Trainer art gap: hinge_glute_bridge (Glute Bridge) is missing the female start pose',
            result.stdout.splitlines(),
        )
        self.assertEqual(len(result.stdout.splitlines()), len(TODAY) + 1)

    def test_a_misnamed_drop_is_reported(self):
        for name in ('not_a_movement-start', 'push_wall-middle'):
            (self.assets / f'Trainer/male/{name}.imageset').mkdir()
        lines = run(CATALOG, self.assets).stdout.splitlines()
        self.assertIn(
            'warning: Trainer art Trainer/male/not_a_movement-start maps to no movement in Exercises.json, so no movement shows it',
            lines,
        )
        self.assertIn(
            'warning: Trainer art Trainer/male/push_wall-middle is not named <exercise_id>-start or <exercise_id>-end, so no movement shows it',
            lines,
        )

    def test_version2_movements_are_never_reported(self):
        for line in run(CATALOG, self.assets).stdout.splitlines():
            for withheld in ('primal_gorilla_walk', 'primal_lizard_crawl', 'primal_underswitch'):
                self.assertNotIn(withheld, line)

    def test_unreadable_inputs_fail_the_build(self):
        missing = Path(self.directory.name) / 'missing.json'
        self.assertNotEqual(run(missing, self.assets).returncode, 0)
        self.assertNotEqual(run(CATALOG, Path(self.directory.name) / 'NoCatalog.xcassets').returncode, 0)
        broken = Path(self.directory.name) / 'broken.json'
        broken.write_text('{not json')
        self.assertNotEqual(run(broken, self.assets).returncode, 0)


if __name__ == '__main__':
    unittest.main()
