#!/usr/bin/env python3
"""Report Trainer art gaps at build time (US-TP05).

Run by the `Report Trainer art gaps` build phase of the RepToday target (`ios/RepToday/project.yml`):

    python3 tools/check-trainer-art.py <Exercises.json> <Assets.xcassets>

It prints one Xcode `warning:` line per **served** movement (audience not `version2`) and Trainer
that lacks a full start/end pair, and one per Trainer image set whose name maps to no catalog
movement or no valid pose, so a misnamed file drop is visible too.

Gaps never fail the build: a missing pose already degrades on device (a single centered pose, or the
SF-Symbol glyph). The checker exits non-zero only when it cannot read its own inputs, so a broken
check can never pass silently.
"""
import json
import re
import sys
from pathlib import Path

TRAINERS = ('male', 'female')
POSES = ('start', 'end')
IMAGE_SET = re.compile(r'^(?P<id>.+)-(?P<pose>[^-]+)\.imageset$')


def fail(message):
    print(f'error: Trainer art check: {message}', file=sys.stderr)
    return 1


def main(argv):
    if len(argv) != 2:
        return fail('usage: check-trainer-art.py <Exercises.json> <Assets.xcassets>')
    catalog_path, assets_path = Path(argv[0]), Path(argv[1])

    try:
        catalog = json.loads(catalog_path.read_text())
        movements = {entry['id']: entry for entry in catalog}
    except (OSError, ValueError, KeyError, TypeError) as error:
        return fail(f'cannot read the exercise catalog ({error})')
    if not movements:
        return fail('the exercise catalog is empty')

    trainer_root = assets_path / 'Trainer'
    if not trainer_root.is_dir():
        return fail(f'no Trainer folder in the asset catalog ({trainer_root.name} missing)')

    present = {trainer: set() for trainer in TRAINERS}
    warnings = []
    for trainer in TRAINERS:
        folder = trainer_root / trainer
        if not folder.is_dir():
            return fail(f'no Trainer/{trainer} folder in the asset catalog')
        for image_set in sorted(folder.iterdir()):
            if image_set.name == 'Contents.json':
                continue
            match = IMAGE_SET.match(image_set.name)
            stem = image_set.name[:-len('.imageset')] if image_set.name.endswith('.imageset') else image_set.name
            name = f'Trainer/{trainer}/{stem}'
            if not match or match['pose'] not in POSES:
                warnings.append(f'Trainer art {name} is not named <exercise_id>-start or <exercise_id>-end, so no movement shows it')
                continue
            entry = movements.get(match['id'])
            if entry is None:
                warnings.append(f'Trainer art {name} maps to no movement in Exercises.json, so no movement shows it')
                continue
            present[trainer].add((match['id'], match['pose']))

    for entry in catalog:
        if entry.get('audience') == 'version2':
            continue
        for trainer in TRAINERS:
            missing = [pose for pose in POSES if (entry['id'], pose) not in present[trainer]]
            if missing:
                poses = 'start and end poses' if len(missing) == 2 else f'{missing[0]} pose'
                warnings.append(
                    f'Trainer art gap: {entry["id"]} ({entry["displayName"]}) is missing the {trainer} {poses}'
                )

    for warning in warnings:
        print(f'warning: {warning}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
