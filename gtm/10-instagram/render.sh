#!/usr/bin/env bash
#
# Regenerate every Instagram carousel PNG from its HTML source.
#
#   ./gtm/10-instagram/render.sh            # render all five carousels
#   ./gtm/10-instagram/render.sh carousel-1-you-do-not-pick   # render one
#
# The HTML is the source of truth; the PNGs under each carousel-*/render/ are
# build output, committed so a reviewer can see the assets without a toolchain.
#
# Tooling is headless Chrome only, matching the package's standing decision
# D-003 (free local tooling only: Chrome headless for capture). No npm install,
# no Puppeteer, no network.
#
# After rendering, all four guards run, so a regenerate is the folder's build:
# fit-check.py enforces brand-guidelines.md section 5's "fit before ship" rule
# (every slide exactly 1080x1350 with nothing clipped at the canvas edge, so a
# clipped legal line fails here rather than reaching a reviewer), widow-check.py
# measures the headline line boxes, claim-audit.py checks the copy against the
# banned claims and the frozen hooks in ../05-social-pmf/, and alt-text-check.py
# confirms every slide's copy is still quoted verbatim in its own alt text.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CHROME="${CHROME:-}"
if [ -z "$CHROME" ]; then
  for candidate in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium" \
    "$(command -v google-chrome || true)" \
    "$(command -v chromium || true)"
  do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then CHROME="$candidate"; break; fi
  done
fi

if [ -z "$CHROME" ] || [ ! -x "$CHROME" ]; then
  echo "Could not find Chrome or Chromium." >&2
  echo "Set CHROME=/path/to/chrome and re-run." >&2
  exit 1
fi

# Each carousel argument is reduced to a bare directory name here, before
# anything is built from it, so every consumer below sees the same normalized
# form: the render loop, the scratch filename, and the two guards that are
# handed this array verbatim at the end.
#
# Tab completion in both bash and zsh appends a trailing slash, and a
# path-qualified argument is the other natural way to type one. Either reaches
# the scratch filename as a path separator, naming a subdirectory that does not
# exist; Chrome then cannot write there and still exits 0, so the run died
# reporting "Chrome produced no output" - blaming Chrome for a path this script
# built. basename strips both forms, which makes that failure unreachable rather
# than merely better reported.
if [ "$#" -gt 0 ]; then
  CAROUSELS=()
  for arg in "$@"; do CAROUSELS+=("$(basename -- "$arg")"); done
else
  CAROUSELS=()
  for dir in "$HERE"/carousel-*/; do CAROUSELS+=("$(basename "$dir")"); done
fi

# Every name is resolved to a real carousel directory here, before the scratch
# directory or any render/ directory is created, so a bad argument costs the
# worktree nothing. A bare -d test is not enough on its own: basename maps a
# degenerate argument back onto this folder ("" and "." both do), which passes
# -d and would create a stray gtm/10-instagram/render/ that outlives the run's
# own correct "Rendered no slides." failure. Requiring the carousel- prefix is
# what makes that unreachable.
for name in "${CAROUSELS[@]}"; do
  case "$name" in
    carousel-*) ;;
    *) echo "Not a carousel: ${name:-(empty argument)}" >&2; exit 1 ;;
  esac
  if [ ! -d "$HERE/$name" ]; then
    echo "No such carousel: $name" >&2
    exit 1
  fi
done

RENDERED=()
COUNT=0

# Chrome captures into a scratch directory this run alone owns, and each capture
# is renamed over its committed PNG only once it is known good. So the check
# below still reads "this run produced it" rather than "a file is there" - a
# stale render can never be mistaken for a fresh one - while a failed capture
# leaves the committed artifact untouched instead of deleting it out of the
# worktree and making the operator restore it. It also closes the window where a
# half-written screenshot sat at the committed path.
#
# The name is unique per run rather than fixed, for the same two reasons
# widow-check.py picks mkstemp over a fixed name: a fixed name is clobbered by a
# concurrent run over the same slide, and a run killed outright leaves it behind
# in the tree as a stray artifact someone can commit. It lives under $HERE so
# the rename stays on one filesystem and is therefore atomic; the trap removes
# it on any exit, and .gitignore carries the pattern as the backstop for a run
# killed before the trap can fire.
SCRATCH="$(mktemp -d "$HERE/.render-scratch-XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

for name in "${CAROUSELS[@]}"; do
  dir="$HERE/$name"
  mkdir -p "$dir/render"
  for html in "$dir"/slide-*.html; do
    [ -e "$html" ] || continue
    base="$(basename "$html" .html)"
    out="$dir/render/$base.png"
    # The scratch name keeps the .png extension because Chrome picks the image
    # format from it and refuses anything else ("Unsupported screenshot image
    # file type"). It is qualified by carousel as well as slide because two
    # carousels have a slide-01.html each and this run renders into one
    # directory.
    tmp="$SCRATCH/$name-$base.png"
    rm -f "$tmp"
    # --window-size fixes the capture at the 4:5 canvas; --force-device-scale-factor=1
    # keeps it at exactly 1080x1350 rather than a Retina multiple.
    #
    # Chrome's own diagnostics are captured rather than discarded, and its exit
    # status is caught rather than left to `set -e`, which aborted the script
    # before the check below could say which slide died or why. Both a non-zero
    # exit and a missing capture are failures here, and both print what Chrome
    # said, so a render that dies says so instead of exiting bare.
    chrome_status=0
    chrome_log="$("$CHROME" \
      --headless \
      --disable-gpu \
      --hide-scrollbars \
      --force-device-scale-factor=1 \
      --window-size=1080,1350 \
      --default-background-color=FAF7F2 \
      --screenshot="$tmp" \
      "file://$html" 2>&1 >/dev/null)" || chrome_status=$?
    if [ "$chrome_status" -ne 0 ] || [ ! -s "$tmp" ]; then
      rm -f "$tmp"
      if [ "$chrome_status" -ne 0 ]; then
        echo "Chrome exited $chrome_status rendering $html" >&2
      else
        echo "Chrome produced no output for $html" >&2
      fi
      if [ -n "$chrome_log" ]; then
        echo "Chrome said:" >&2
        echo "$chrome_log" >&2
      fi
      exit 1
    fi
    mv -f "$tmp" "$out"
    RENDERED+=("$out")
    COUNT=$((COUNT + 1))
    echo "rendered  $name/$base.png"
  done
done

echo
# A named carousel directory holding no slide-*.html would otherwise hand the
# checks an empty list, and "Fit check passed: 0 slide(s)" exiting 0 is a green
# run that verified nothing. Fail instead of reporting a vacuous pass.
if [ "$COUNT" -eq 0 ]; then
  echo "Rendered no slides. Nothing was checked, so nothing is verified." >&2
  exit 1
fi

echo "Rendered $COUNT slide(s). Checking fit..."
python3 "$HERE/fit-check.py" "${RENDERED[@]}"

echo
echo "Checking headline line breaks..."
CHROME="$CHROME" python3 "$HERE/widow-check.py" "${CAROUSELS[@]}"

echo
echo "Checking alt text against slide copy..."
python3 "$HERE/alt-text-check.py" "${CAROUSELS[@]}"

# The claim audit always covers the whole folder, whichever carousel was
# rendered: it reads the frozen files in ../05-social-pmf/ and a copy edit that
# collides with one of them is a publication blocker, not a layout detail.
echo
echo "Auditing claims and experiment integrity..."
python3 "$HERE/claim-audit.py"
