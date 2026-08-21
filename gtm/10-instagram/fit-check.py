#!/usr/bin/env python3
"""Fit check for rendered carousel slides.

brand-guidelines.md section 5 carries a hard rule for fixed-canvas assets:
"Render the asset at final pixel size and check; clipping any required line is
a hard failure." That rule exists because gate-test-asset-v2 shipped with its
proof line and its entire legal line clipped, and only rendering revealed it.

This script is that check, automated. Every slide is 1080x1350 with 80px of
padding, so no ink may ever land within 72px of an edge. If the layout
overflows, .slide's overflow:hidden clips it exactly at the canvas boundary and
the clipped ink paints into that band. Non-Paper pixels in the band therefore
mean either an overflow or a margin violation, and both are build failures.

Pure standard library on purpose: the package's tooling decision (D-003 in
gtm/decisions-log.md) is free local tooling only, and Pillow is not installed.
"""

import struct
import sys
import zlib

PAPER = (0xFA, 0xF7, 0xF2)  # Paper #FAF7F2
TOLERANCE = 2               # per channel, for any PNG colour-management drift
BAND = 72                   # px from each edge that must stay bare Paper
EXPECTED = (1080, 1350)     # Instagram 4:5 portrait


def read_png(path):
    """Return (width, height, rows) where each row is a list of (r, g, b)."""
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")

    pos = 8
    idat = bytearray()
    width = height = depth = colour = interlace = None
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break

    if depth != 8 or interlace != 0 or colour not in (2, 6):
        raise ValueError("expected a non-interlaced 8-bit RGB/RGBA PNG, got "
                         "depth=%s colour=%s interlace=%s" % (depth, colour, interlace))

    channels = 3 if colour == 2 else 4
    stride = width * channels
    raw = zlib.decompress(bytes(idat))

    rows = []
    prev = bytearray(stride)
    at = 0
    for _ in range(height):
        ftype = raw[at]
        line = bytearray(raw[at + 1:at + 1 + stride])
        at += 1 + stride
        # Undo the per-scanline filter (PNG spec section 9).
        for i in range(stride):
            a = line[i - channels] if i >= channels else 0
            b = prev[i]
            c = prev[i - channels] if i >= channels else 0
            if ftype == 0:
                pass
            elif ftype == 1:
                line[i] = (line[i] + a) & 0xFF
            elif ftype == 2:
                line[i] = (line[i] + b) & 0xFF
            elif ftype == 3:
                line[i] = (line[i] + (a + b) // 2) & 0xFF
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
            else:
                raise ValueError("bad filter type %d" % ftype)
        rows.append([tuple(line[x * channels:x * channels + 3]) for x in range(width)])
        prev = line
    return width, height, rows


def is_paper(px):
    return all(abs(px[i] - PAPER[i]) <= TOLERANCE for i in range(3))


def check(path):
    """Return a list of human-readable failures for one rendered slide."""
    width, height, rows = read_png(path)
    problems = []

    if (width, height) != EXPECTED:
        problems.append("size is %dx%d, expected %dx%d" % (width, height, *EXPECTED))
        return problems

    for y in range(height):
        in_vertical_band = y < BAND or y >= height - BAND
        xs = range(width) if in_vertical_band else \
            list(range(BAND)) + list(range(width - BAND, width))
        for x in xs:
            if not is_paper(rows[y][x]):
                edge = ("top" if y < BAND else
                        "bottom" if y >= height - BAND else
                        "left" if x < BAND else "right")
                problems.append(
                    "ink at (%d, %d) is inside the %dpx %s margin band "
                    "(content overflows the canvas or breaks the 80px margin)"
                    % (x, y, BAND, edge))
                return problems
    return problems


def main(paths):
    failures = 0
    for path in paths:
        try:
            problems = check(path)
        except Exception as exc:  # noqa: BLE001 - report and keep going
            problems = ["could not be read: %s" % exc]
        for problem in problems:
            print("FAIL  %s: %s" % (path, problem))
            failures += 1
    if failures:
        print("\n%d slide(s) failed the fit check." % failures)
        return 1
    print("Fit check passed: %d slide(s) are exactly %dx%d with a clean "
          "%dpx margin band." % (len(paths), EXPECTED[0], EXPECTED[1], BAND))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
