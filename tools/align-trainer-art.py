#!/usr/bin/env python3
"""Resize and align one generated Trainer start/end pair to the art set's export format.

Run it in the art folder, before `import-trainer-art.py`, on the original-resolution files an
image generator delivered. It needs Pillow, NumPy, `imagequant` and `pyoxipng` (`pip install pillow
numpy imagequant pyoxipng`); the build never runs it.

    python3 tools/align-trainer-art.py <start.png> <end.png> <out-dir> <slug>

It writes `<out-dir>/<slug>-start.png` and `<out-dir>/<slug>-end.png` in the format every shipped
Trainer file has, and prints one JSON record per file (measurements and hashes, for the art
folder's manifest):

- 600x600, 8-bit RGBA, the shipped sRGB ICC profile embedded (taken from a shipped image set, so
  the new files carry byte-for-byte the same profile). Sources with no profile are read as sRGB.
- Background dust (alpha 1-2) cleared, and the near-opaque interior (alpha >= 250) plus any
  partly transparent speck more than two pixels inside the silhouette made opaque, so partial alpha
  stays on the antialiased silhouette edge.
- One scale for both poses, `min(500 / widest pose, 468 / tallest pose)`: a floor pose spans about
  500 px with about 50 px side padding, and a standing figure is at most 468 px tall, like the
  shipped Standard Push-Up and Bodyweight Squat.
- Each pose's lowest ground contact (the lowest row with alpha >= 128: palms, toes or feet, and the
  toes of an airborne pose) moved to y=521; one horizontal offset for the pair, centred on the union
  of both poses, so the two never shift against each other.
- Colours reduced to 256 (as the shipped files are), kept as truecolor RGBA and recompressed with
  oxipng, which brings a file to about 40-80 KB.
"""
import argparse
import hashlib
import io
import json
import sys
from pathlib import Path

import imagequant
import numpy as np
import oxipng
from PIL import Image, ImageFilter

REPO = Path(__file__).resolve().parent.parent
DEFAULT_PROFILE_SOURCE = (
    REPO / 'ios/RepToday/RepToday/Resources/Assets.xcassets/Trainer/male/push_standard-start.imageset/push_standard-start.png'
)

CANVAS = 600
FLOOR_Y = 521
MAX_WIDTH = 500
MAX_HEIGHT = 468
DUST_ALPHA = 2
OPAQUE_ALPHA = 250
CONTACT_ALPHA = 128
COLORS = 256


def cleaned(pixels):
    alpha = pixels[:, :, 3]
    alpha[alpha <= DUST_ALPHA] = 0
    alpha[alpha >= OPAQUE_ALPHA] = 255
    # A pixel whose 5x5 neighbourhood is all figure is interior, not edge, however the generator left it.
    inside = np.array(Image.fromarray(alpha).filter(ImageFilter.MinFilter(5))) >= CONTACT_ALPHA
    alpha[inside] = 255
    pixels[alpha == 0] = 0
    return pixels


def clean_alpha(image):
    return Image.fromarray(cleaned(np.array(image.convert('RGBA'))), 'RGBA')


def figure_box(image, threshold=1):
    alpha = np.array(image)[:, :, 3]
    rows = np.where((alpha >= threshold).any(axis=1))[0]
    cols = np.where((alpha >= threshold).any(axis=0))[0]
    return cols[0], rows[0], cols[-1] + 1, rows[-1] + 1


def lowest_contact(image):
    alpha = np.array(image)[:, :, 3]
    return np.where((alpha >= CONTACT_ALPHA).any(axis=1))[0][-1]


def resized(image, scale):
    size = (round(image.width * scale), round(image.height * scale))
    # Premultiplied while resampling, so the transparent background's colour cannot bleed into edges.
    return image.convert('RGBa').resize(size, Image.LANCZOS).convert('RGBA')


def finished(image, profile):
    pixels = cleaned(np.array(image))
    reduced = imagequant.quantize_pil_image(Image.fromarray(pixels, 'RGBA'), dithering_level=1.0, max_colors=COLORS)
    # The quantizer may merge opaque pixels into a palette entry of alpha 253-254.
    reduced = np.array(reduced.convert('RGBA'))
    reduced[reduced[:, :, 3] >= OPAQUE_ALPHA, 3] = 255
    out = io.BytesIO()
    Image.fromarray(reduced, 'RGBA').save(out, 'PNG', compress_level=1, icc_profile=profile)
    # Lossless recompression that keeps the RGBA colour type and the profile.
    return oxipng.optimize_from_memory(
        out.getvalue(), level=4, optimize_alpha=True, color_type_reduction=False,
        bit_depth_reduction=False, palette_reduction=False, grayscale_reduction=False,
    )


def describe(data, slug, pose, scale, source):
    image = Image.open(io.BytesIO(data))
    pixels = np.array(image)
    alpha = pixels[:, :, 3]
    x0, y0, x1, y1 = figure_box(image)
    return {
        'exercise': slug,
        'pose': pose,
        'file': f'png/{slug}-{pose}.png',
        'source': source.name,
        'sourceSize': dict(zip(('width', 'height'), Image.open(source).size)),
        'width': image.width,
        'height': image.height,
        'mode': image.mode,
        'bitDepth': 8,
        'hasIcc': bool(image.info.get('icc_profile')),
        'bytes': len(data),
        'sharedScale': scale,
        'bounds': {'x0': int(x0), 'y0': int(y0), 'x1': int(x1) - 1, 'y1': int(y1) - 1},
        'lowestContactY': int(lowest_contact(image)),
        'colors': int(len(np.unique(pixels.reshape(-1, 4), axis=0))),
        'opaque': int((alpha == 255).sum()),
        'transparent': int((alpha == 0).sum()),
        'sha256': hashlib.sha256(data).hexdigest(),
    }


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('start', type=Path)
    parser.add_argument('end', type=Path)
    parser.add_argument('out_dir', type=Path)
    parser.add_argument('slug')
    parser.add_argument('--profile-from', type=Path, default=DEFAULT_PROFILE_SOURCE)
    args = parser.parse_args(argv)

    profile = Image.open(args.profile_from).info.get('icc_profile')
    if not profile:
        print(f'error: {args.profile_from} carries no ICC profile', file=sys.stderr)
        return 1

    sources = {'start': args.start, 'end': args.end}
    poses = {pose: clean_alpha(Image.open(path)) for pose, path in sources.items()}
    boxes = {pose: figure_box(image) for pose, image in poses.items()}
    widest = max(x1 - x0 for x0, _, x1, _ in boxes.values())
    tallest = max(y1 - y0 for _, y0, _, y1 in boxes.values())
    scale = min(MAX_WIDTH / widest, MAX_HEIGHT / tallest)

    scaled = {pose: resized(image, scale) for pose, image in poses.items()}
    scaled_boxes = {pose: figure_box(image) for pose, image in scaled.items()}
    left = min(box[0] for box in scaled_boxes.values())
    right = max(box[2] for box in scaled_boxes.values())
    dx = round((CANVAS - (right - left)) / 2) - left

    args.out_dir.mkdir(parents=True, exist_ok=True)
    for pose, image in scaled.items():
        dy = FLOOR_Y - lowest_contact(image)
        _, top, _, _ = scaled_boxes[pose]
        if top + dy < 0 or left + dx < 0 or right + dx > CANVAS:
            print(f'error: {args.slug} {pose} does not fit the {CANVAS}px canvas', file=sys.stderr)
            return 1
        canvas = Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 0))
        canvas.paste(image, (dx, dy))
        data = finished(canvas, profile)
        (args.out_dir / f'{args.slug}-{pose}.png').write_bytes(data)
        print(json.dumps(describe(data, args.slug, pose, scale, sources[pose])))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
