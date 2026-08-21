#!/usr/bin/env bash
#
# Regenerate every Instagram carousel PNG from its HTML source.
#
#   ./gtm/10-instagram/render.sh            # render all five carousels
#   ./gtm/10-instagram/render.sh carousel-1-already-there   # render one
#
# The HTML is the source of truth; the PNGs under each carousel-*/render/ are
# build output, committed so a reviewer can see the assets without a toolchain.
#
# Tooling is headless Chrome only, matching the package's standing decision
# D-003 (free local tooling only: Chrome headless for capture). No npm install,
# no Puppeteer, no network.
#
# After rendering, fit-check.py enforces brand-guidelines.md section 5's
# "fit before ship" rule: every slide must be exactly 1080x1350 with nothing
# clipped at the canvas edge. A clipped legal line fails the build here rather
# than reaching a reviewer.

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

if [ "$#" -gt 0 ]; then
  CAROUSELS=("$@")
else
  CAROUSELS=()
  for dir in "$HERE"/carousel-*/; do CAROUSELS+=("$(basename "$dir")"); done
fi

RENDERED=()
COUNT=0

for name in "${CAROUSELS[@]}"; do
  dir="$HERE/$name"
  if [ ! -d "$dir" ]; then
    echo "No such carousel: $name" >&2
    exit 1
  fi
  mkdir -p "$dir/render"
  for html in "$dir"/slide-*.html; do
    [ -e "$html" ] || continue
    base="$(basename "$html" .html)"
    out="$dir/render/$base.png"
    # --window-size fixes the capture at the 4:5 canvas; --force-device-scale-factor=1
    # keeps it at exactly 1080x1350 rather than a Retina multiple.
    "$CHROME" \
      --headless \
      --disable-gpu \
      --hide-scrollbars \
      --force-device-scale-factor=1 \
      --window-size=1080,1350 \
      --default-background-color=FAF7F2 \
      --screenshot="$out" \
      "file://$html" >/dev/null 2>&1
    if [ ! -s "$out" ]; then
      echo "Chrome produced no output for $html" >&2
      exit 1
    fi
    RENDERED+=("$out")
    COUNT=$((COUNT + 1))
    echo "rendered  $name/$base.png"
  done
done

echo
echo "Rendered $COUNT slide(s). Checking fit..."
python3 "$HERE/fit-check.py" "${RENDERED[@]}"
