#!/usr/bin/env python3
"""Import the captain's Trainer pose art into the app's asset catalog (US-TP02).

Run it against a *copy* of the art root (the folder holding the six
`RepToday-<family>-exercise-poses` family folders). It only reads that tree.

    python3 tools/import-trainer-art.py <art-root>

What it does, every run, from scratch:

- Rebuilds `Resources/Assets.xcassets/Trainer/` (and nothing else in the catalog).
- Copies each `<trainer>/png/<slug>-<pose>.png` byte-for-byte into one single-scale, universal,
  render-as-original image set named by **exercise id**, Trainer and pose:
  `Trainer/<male|female>/<exercise_id>-<start|end>`. The 600x600 canvas is never trimmed or scaled.
- Maps a file to an exercise id through the explicit `SLUG_TO_ID` table below, keyed by family
  folder *and* slug, so the two "Cossack Squat" entries (leg vs mobility) cannot collide.
- Skips, and names, every file it does not bundle: art that maps to no catalog movement (the
  Prone Y/T/W variants today), art for a `version2` movement (withheld until version 2), and any
  file whose name it cannot read.

Only PNGs are copied. Provenance logs, manifests, prompt files and review images stay where they
are - they are never committed to this repository (asset-attribution decision, US-TP01).
"""
import argparse
import json
import re
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_CATALOG = REPO / 'ios/RepToday/RepToday/Resources/Exercises.json'
DEFAULT_ASSETS = REPO / 'ios/RepToday/RepToday/Resources/Assets.xcassets'

TRAINERS = ('male', 'female')
POSES = ('start', 'end')
FAMILY_FOLDER = re.compile(r'^RepToday-(push|back|leg|core|primal|mobility)-exercise-poses$')
ART_FILE = re.compile(r'^(?P<slug>[a-z0-9-]+)-(?P<pose>start|end)\.png$')

# (family folder, display-name slug) -> exercise id in `Exercises.json`. Explicit on purpose: the
# art is named by display name, the app by id, and a display name is not unique (two Cossack Squats).
SLUG_TO_ID = {
    ('push', 'wall-push-up'): 'push_wall',
    ('push', 'incline-push-up'): 'push_incline',
    ('push', 'knee-push-up'): 'push_knee',
    ('push', 'standard-push-up'): 'push_standard',
    ('push', 'diamond-push-up'): 'push_diamond',
    ('push', 'archer-push-up'): 'push_archer',
    ('push', 'assisted-one-arm-push-up'): 'push_one_arm_assisted',
    ('push', 'one-arm-push-up'): 'push_one_arm',
    ('push', 'floor-tricep-dips'): 'push_floor_dips',
    ('push', 'pike-push-up'): 'push_pike',
    ('back', 'superman-hold'): 'pull_superman',
    ('back', 'reverse-snow-angel'): 'pull_reverse_snow_angel',
    ('back', 'prone-y-t-w-raises'): 'pull_ytw',
    ('back', 'wall-scapular-pull'): 'pull_wall_scapular_pull',
    ('back', 'supine-floor-row'): 'pull_floor_row',
    ('back', 'single-arm-supine-floor-row'): 'pull_floor_row_single_arm',
    ('leg', 'wall-sit'): 'squat_wall_sit',
    ('leg', 'bodyweight-squat'): 'squat_bodyweight',
    ('leg', 'sumo-squat'): 'squat_sumo',
    ('leg', 'cossack-squat'): 'squat_cossack',
    ('leg', 'shrimp-squat'): 'squat_shrimp',
    ('leg', 'assisted-pistol-squat'): 'squat_pistol_assisted',
    ('leg', 'pistol-squat'): 'squat_pistol',
    ('leg', 'reverse-lunge'): 'lunge_reverse',
    ('leg', 'split-squat'): 'lunge_split_squat',
    ('leg', 'glute-bridge'): 'hinge_glute_bridge',
    ('leg', 'single-leg-glute-bridge'): 'hinge_single_leg_bridge',
    ('leg', 'marching-glute-bridge'): 'hinge_bridge_march',
    ('leg', 'long-lever-single-leg-bridge'): 'hinge_long_lever_bridge',
    ('leg', 'assisted-nordic-curl'): 'hinge_nordic_assisted',
    ('leg', 'nordic-curl'): 'hinge_nordic',
    ('leg', 'bodyweight-good-morning'): 'hinge_good_morning',
    ('leg', 'single-leg-romanian-deadlift'): 'hinge_single_leg_rdl',
    ('core', 'forearm-plank'): 'core_forearm_plank',
    ('core', 'side-plank'): 'core_side_plank',
    ('core', 'bird-dog'): 'core_bird_dog',
    ('core', 'dead-bug'): 'core_dead_bug',
    ('core', 'bear-hold'): 'core_bear_hold',
    ('core', 'hollow-hold'): 'core_hollow_hold',
    ('core', 'hollow-rock'): 'core_hollow_rock',
    ('core', 'tuck-l-sit'): 'core_tuck_l_sit',
    ('core', 'one-leg-l-sit'): 'core_one_leg_l_sit',
    ('core', 'l-sit'): 'core_l_sit',
    ('primal', 'bear-crawl'): 'primal_bear_crawl',
    ('primal', 'crab-walk'): 'primal_crab_walk',
    ('primal', 'ground-to-standing-get-up'): 'primal_ground_to_standing',
    ('primal', 'bear-hover-shoulder-tap'): 'primal_bear_shoulder_tap',
    ('primal', 'gorilla-walk'): 'primal_gorilla_walk',
    ('primal', 'lizard-crawl'): 'primal_lizard_crawl',
    ('primal', 'underswitch'): 'primal_underswitch',
    ('mobility', 'deep-squat-hold'): 'mobility_deep_squat_hold',
    ('mobility', '90-90-hip-stretch'): 'mobility_9090_hip',
    ('mobility', 'cat-cow-flow'): 'mobility_cat_cow',
    ('mobility', 'thoracic-rotations'): 'mobility_thoracic_rotation',
    ('mobility', 'worlds-greatest-stretch'): 'mobility_worlds_greatest',
    ('mobility', 'pigeon-pose'): 'mobility_pigeon',
    ('mobility', 'frog-stretch'): 'mobility_frog',
    ('mobility', 'downward-dog'): 'mobility_down_dog',
    ('mobility', 'kneeling-hip-flexor-stretch'): 'mobility_kneeling_hip_flexor',
    ('mobility', 'wall-chest-opener'): 'mobility_wall_chest_opener',
    ('mobility', 'standing-forward-fold'): 'mobility_forward_fold',
    ('mobility', 'childs-pose'): 'mobility_childs_pose',
    ('mobility', 'lizard-lunge'): 'mobility_lizard_lunge',
    ('mobility', 'supine-spinal-twist'): 'mobility_supine_twist',
    ('mobility', 'thread-the-needle'): 'mobility_thread_needle',
    ('mobility', 'standing-quad-stretch'): 'mobility_standing_quad',
    ('mobility', 'figure-four-glute-stretch'): 'mobility_figure_four',
    ('mobility', 'wall-calf-stretch'): 'mobility_wall_calf',
    ('mobility', 'butterfly-stretch'): 'mobility_butterfly',
    ('mobility', 'cobra-stretch'): 'mobility_cobra',
    ('mobility', 'puppy-pose'): 'mobility_puppy_pose',
    ('mobility', 'cossack-squat'): 'mobility_cossack',
    ('mobility', 'hip-circles'): 'mobility_hip_circles',
    ('mobility', 'standing-side-bend'): 'mobility_side_bend',
    ('mobility', 'ankle-rocks'): 'mobility_ankle_rocks',
    ('mobility', 'arm-circles'): 'mobility_arm_circles',
}

NAMESPACE_CONTENTS = {'info': {'author': 'xcode', 'version': 1}, 'properties': {'provides-namespace': True}}


def image_set_contents(filename):
    # No `scale` key: a single-scale image set. `original` keeps the art in color rather than tinted.
    return {
        'images': [{'filename': filename, 'idiom': 'universal'}],
        'info': {'author': 'xcode', 'version': 1},
        'properties': {'template-rendering-intent': 'original'},
    }


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def load_catalog(path):
    entries = json.loads(path.read_text())
    return {entry['id']: entry for entry in entries}


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('art_root', type=Path)
    parser.add_argument('--catalog', type=Path, default=DEFAULT_CATALOG)
    parser.add_argument('--assets', type=Path, default=DEFAULT_ASSETS)
    args = parser.parse_args(argv)

    catalog = load_catalog(args.catalog)
    unknown_ids = sorted({i for i in SLUG_TO_ID.values() if i not in catalog})
    if unknown_ids:
        print(f'error: SLUG_TO_ID names ids missing from the catalog: {", ".join(unknown_ids)}', file=sys.stderr)
        return 1

    families = sorted(p for p in args.art_root.iterdir() if p.is_dir() and FAMILY_FOLDER.match(p.name))
    if not families:
        print(f'error: no RepToday-<family>-exercise-poses folders under the art root', file=sys.stderr)
        return 1

    trainer_root = args.assets / 'Trainer'
    if trainer_root.exists():
        shutil.rmtree(trainer_root)
    trainer_root.mkdir(parents=True)
    write_json(trainer_root / 'Contents.json', NAMESPACE_CONTENTS)
    for trainer in TRAINERS:
        (trainer_root / trainer).mkdir()
        write_json(trainer_root / trainer / 'Contents.json', NAMESPACE_CONTENTS)

    imported, skipped, total_bytes = 0, [], 0
    for family_dir in families:
        family = FAMILY_FOLDER.match(family_dir.name).group(1)
        for trainer_dir in sorted(p for p in family_dir.iterdir() if p.is_dir()):
            trainer = trainer_dir.name.lower()
            if trainer not in TRAINERS:
                continue
            for png in sorted((trainer_dir / 'png').glob('*.png')):
                label = f'{family}/{trainer}/{png.name}'
                match = ART_FILE.match(png.name)
                if not match:
                    skipped.append((label, 'unreadable file name'))
                    continue
                exercise_id = SLUG_TO_ID.get((family, match['slug']))
                if exercise_id is None:
                    skipped.append((label, 'maps to no catalog movement'))
                    continue
                if catalog[exercise_id].get('audience') == 'version2':
                    skipped.append((label, f'{exercise_id} is a version2 movement (not served)'))
                    continue
                name = f'{exercise_id}-{match["pose"]}'
                image_set = trainer_root / trainer / f'{name}.imageset'
                if image_set.exists():
                    skipped.append((label, f'duplicate art for {trainer}/{name}'))
                    continue
                image_set.mkdir()
                shutil.copyfile(png, image_set / f'{name}.png')
                write_json(image_set / 'Contents.json', image_set_contents(f'{name}.png'))
                imported += 1
                total_bytes += png.stat().st_size

    print(f'imported {imported} image sets ({total_bytes} bytes of PNG)')
    for label, reason in skipped:
        print(f'skipped {label}: {reason}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
