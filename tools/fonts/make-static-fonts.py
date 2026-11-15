#!/usr/bin/env python3
"""Cut the app's static font files from the official variable fonts.

The app bundles Bricolage Grotesque and Inter (both SIL Open Font License 1.1) as static
instances rather than the variable files: SwiftUI's `Font.custom(_:size:relativeTo:)` keeps
Dynamic Type scaling but cannot set a variation axis, and Core Text does not apply optical size
on its own to a custom font, so each optical size and weight the design uses is its own file.

Only the weights DESIGN.md names are cut:
- Bricolage Grotesque ExtraBold (800) at optical sizes 96 (timer, score, the largest display),
  48 (display and screen titles) and 24 (card titles and values), and Bold (700) at 24 for values
  in lists. Width is the default 100.
- Inter Regular, Medium, SemiBold, Bold and ExtraBold (400-800) at optical size 14, Inter's text cut.

Usage (needs `fonttools`): python3 tools/fonts/make-static-fonts.py <out dir>
The sources are downloaded from google/fonts at the pinned commits below.
"""

import sys
import tempfile
import urllib.request
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

GOOGLE_FONTS = "https://raw.githubusercontent.com/google/fonts"
BRICOLAGE = (
    "6ce172f74aa355ea43eb964fa4a91570a4d3064d",
    "ofl/bricolagegrotesque/BricolageGrotesque%5Bopsz,wdth,wght%5D.ttf",
)
INTER = ("0b58fb370093f9a9f4ff785d94405710b79de67c", "ofl/inter/Inter%5Bopsz,wght%5D.ttf")
INTER_WEIGHTS = {400: "Regular", 500: "Medium", 600: "SemiBold", 700: "Bold", 800: "ExtraBold"}
NAME_IDS_TO_REPLACE = (1, 2, 3, 4, 6, 16, 17, 21, 22, 25)
VARIATION_TABLES = ("STAT", "fvar", "avar", "gvar", "HVAR", "MVAR", "cvar")


def fetch(source, directory):
    commit, path = source
    target = Path(directory) / Path(path).name.replace("%5B", "[").replace("%5D", "]")
    urllib.request.urlretrieve(f"{GOOGLE_FONTS}/{commit}/{path}", target)
    return target


def instance(source, axes, family, style, postscript_name, out_dir):
    font = instancer.instantiateVariableFont(
        TTFont(source), axes, inplace=False, overlap=instancer.OverlapMode.KEEP_AND_SET_FLAGS
    )
    names = font["name"]
    for record in list(names.names):
        if record.nameID in NAME_IDS_TO_REPLACE:
            names.removeNames(nameID=record.nameID)
    legacy_style = style if style in ("Regular", "Bold") else "Regular"
    for platform, encoding, language in ((3, 1, 0x409), (1, 0, 0)):
        names.setName(family, 1, platform, encoding, language)
        names.setName(legacy_style, 2, platform, encoding, language)
        names.setName(f"{postscript_name};instance", 3, platform, encoding, language)
        names.setName(f"{family} {style}", 4, platform, encoding, language)
        names.setName(postscript_name, 6, platform, encoding, language)
        names.setName(family, 16, platform, encoding, language)
        names.setName(style, 17, platform, encoding, language)
    for table in VARIATION_TABLES:
        if table in font:
            del font[table]
    font["OS/2"].usWeightClass = axes["wght"]
    # Keep the source's timestamps so a rerun reproduces the committed files byte for byte.
    font.recalcTimestamp = False
    out = Path(out_dir) / f"{postscript_name}.ttf"
    font.save(out)
    print(out)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    out_dir = Path(sys.argv[1])
    out_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as directory:
        bricolage = fetch(BRICOLAGE, directory)
        inter = fetch(INTER, directory)
        for optical_size in (96, 48, 24):
            instance(
                bricolage, {"opsz": optical_size, "wdth": 100, "wght": 800},
                f"Bricolage Grotesque {optical_size}pt", "ExtraBold",
                f"BricolageGrotesque-{optical_size}ptExtraBold", out_dir,
            )
        instance(
            bricolage, {"opsz": 24, "wdth": 100, "wght": 700},
            "Bricolage Grotesque 24pt", "Bold", "BricolageGrotesque-24ptBold", out_dir,
        )
        for weight, style in INTER_WEIGHTS.items():
            instance(inter, {"opsz": 14, "wght": weight}, "Inter", style, f"Inter-{style}", out_dir)


if __name__ == "__main__":
    main()
