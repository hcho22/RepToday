#!/bin/bash
# Rep Today launch video - reproducible build.
# Requires: macOS `say` (Samantha), Google Chrome, ffmpeg 7.x.
# Output: ../launch-video.mp4 (1920x1080, 30fps, H.264 + AAC, ~52s).
#
# Timeline (seconds, on the final timeline; 0.8s crossfades between scenes):
#   scene  dur    visible-from   VO starts   VO line
#   1      6.0    0.0            0.9         vo1 (3.49s)
#   2      5.0    5.2            6.4         vo2 (2.75s)
#   3     10.5    9.4           10.6         vo3 (7.66s)
#   4      7.5   19.1           20.3         vo4 (5.23s)
#   5      7.5   25.8           27.0         vo5 (4.76s)
#   6      8.0   32.5           33.7         vo6 (5.08s)
#   7      5.5   39.7           40.9         vo7 (2.74s)
#   8      8.0   44.4           45.7         vo8 (2.20s)
#   total 52.4
set -euo pipefail

BUILD="$(cd "$(dirname "$0")" && pwd)"
OUT="$BUILD/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
cd "$BUILD"

# ---------------------------------------------------------------- 1. Voiceover
say -v Samantha -o vo1.aiff "It's nine at night. You have twelve minutes, and no equipment."
say -v Samantha -o vo2.aiff "So open the app. The workout is already there."
say -v Samantha -o vo3.aiff "A full bodyweight session, built on your phone in under one hundred milliseconds. No questions. No account. No internet needed."
say -v Samantha -o vo4.aiff "Got twenty minutes instead of ten? One tap. The session rebuilds before your thumb lifts."
say -v Samantha -o vo5.aiff "Bodyweight strength, mobility, and the kind of moving you did when you were seven."
say -v Samantha -o vo6.aiff "There are no streaks to lose here. Miss a day, and your score dips. It never resets."
say -v Samantha -o vo7.aiff "The workouts are free. All of them. Forever."
say -v Samantha -o vo8.aiff "Rep Today. You're someone who moves."

# ------------------------------------------------------------- 2. Scene frames
# Chrome 150 headless can hang after writing the screenshot, so run it in the
# background, wait for the PNG, then kill it. --allow-file-access-from-files
# lets the scenes @font-face the system SF Rounded (file:// -> file://).
shot() { # shot <output.png> <url>
  local out="$BUILD/$1" pid i=0
  rm -f "$out"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --allow-file-access-from-files \
    --user-data-dir="$(mktemp -d /tmp/reptoday-chrome.XXXXXX)" \
    --window-size=1920,1080 --screenshot="$out" "$2" >/dev/null 2>&1 &
  pid=$!
  while [ ! -s "$out" ] && [ $i -lt 150 ]; do sleep 0.2; i=$((i+1)); done
  sleep 0.4
  kill "$pid" >/dev/null 2>&1 || true
  wait "$pid" 2>/dev/null || true
  [ -s "$out" ] || { echo "screenshot failed: $1" >&2; exit 1; }
}
shot scene1.png  "file://$BUILD/scene1.html"
shot scene2a.png "file://$BUILD/scene2.html?k=1"
shot scene2b.png "file://$BUILD/scene2.html?k=2"
shot scene2c.png "file://$BUILD/scene2.html?k=3"
shot scene3.png  "file://$BUILD/scene3.html"
shot scene4a.png "file://$BUILD/scene4.html?k=1"
shot scene4b.png "file://$BUILD/scene4.html?k=2"
shot scene5a.png "file://$BUILD/scene5.html?k=1"
shot scene5b.png "file://$BUILD/scene5.html?k=2"
shot scene5c.png "file://$BUILD/scene5.html?k=3"
shot scene6.png  "file://$BUILD/scene6.html"
shot scene7.png  "file://$BUILD/scene7.html"
shot scene8.png  "file://$BUILD/scene8.html"

# --------------------------------------------------- 3. Per-scene video segments
ENC="-c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -r 30"

# Single-frame scenes get a very subtle zoompan drift (to ~1.04 over the scene).
drift() { # drift <in.png> <out.mp4> <frames>
  local Z; Z=$(python3 -c "print(f'{0.04/$3:.7f}')")
  ffmpeg -y -framerate 30 -i "$1" -vf \
    "scale=3840:2160:flags=lanczos,zoompan=z='1+$Z*on':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=$3:s=1920x1080:fps=30" \
    $ENC -t "$(python3 -c "print($3/30)")" "$2"
}
drift scene1.png seg1.mp4 180   # 6.0s
drift scene3.png seg3.mp4 315   # 10.5s
drift scene6.png seg6.mp4 240   # 8.0s
drift scene7.png seg7.mp4 165   # 5.5s
drift scene8.png seg8.mp4 240   # 8.0s

# Keyframed scenes: static stills crossfaded internally (the motion is the reveal).
# Scene 2 (5.0s): the Ready Mark draws in; the Start circle lands on "already there".
ffmpeg -y -loop 1 -t 2.1 -framerate 30 -i scene2a.png \
          -loop 1 -t 1.9 -framerate 30 -i scene2b.png \
          -loop 1 -t 2.0 -framerate 30 -i scene2c.png -filter_complex \
  "[0][1]xfade=transition=fade:duration=0.5:offset=1.6[a];[a][2]xfade=transition=fade:duration=0.5:offset=3.0,format=yuv420p[v]" \
  -map "[v]" $ENC seg2.mp4
# Scene 4 (7.5s): the duration chip flips 10 -> 20 as the VO says "One tap".
ffmpeg -y -loop 1 -t 3.6 -framerate 30 -i scene4a.png \
          -loop 1 -t 4.3 -framerate 30 -i scene4b.png -filter_complex \
  "[0][1]xfade=transition=fade:duration=0.4:offset=3.2,format=yuv420p[v]" \
  -map "[v]" $ENC seg4.mp4
# Scene 5 (7.5s): Strength / Mobility / Primal light up one by one.
ffmpeg -y -loop 1 -t 3.2 -framerate 30 -i scene5a.png \
          -loop 1 -t 2.2 -framerate 30 -i scene5b.png \
          -loop 1 -t 2.9 -framerate 30 -i scene5c.png -filter_complex \
  "[0][1]xfade=transition=fade:duration=0.4:offset=2.8[a];[a][2]xfade=transition=fade:duration=0.4:offset=4.6,format=yuv420p[v]" \
  -map "[v]" $ENC seg5.mp4

# ------------------------------------------- 4. Assemble scenes: slow crossfades
# xfade offsets: cumulative duration minus 0.8s per transition (see header table).
# Scene-to-scene transitions dip through black (fadeblack) so text never overlaps text;
# intra-scene keyframe reveals above keep plain fade.
ffmpeg -y -i seg1.mp4 -i seg2.mp4 -i seg3.mp4 -i seg4.mp4 \
          -i seg5.mp4 -i seg6.mp4 -i seg7.mp4 -i seg8.mp4 -filter_complex "
  [0][1]xfade=transition=fadeblack:duration=0.8:offset=5.2[x1];
  [x1][2]xfade=transition=fadeblack:duration=0.8:offset=9.4[x2];
  [x2][3]xfade=transition=fadeblack:duration=0.8:offset=19.1[x3];
  [x3][4]xfade=transition=fadeblack:duration=0.8:offset=25.8[x4];
  [x4][5]xfade=transition=fadeblack:duration=0.8:offset=32.5[x5];
  [x5][6]xfade=transition=fadeblack:duration=0.8:offset=39.7[x6];
  [x6][7]xfade=transition=fadeblack:duration=0.8:offset=44.4,
  fade=t=in:st=0:d=0.6,fade=t=out:st=51.2:d=1.2,format=yuv420p[v]" \
  -map "[v]" $ENC video.mp4

# ------------------------------------- 5. Audio: VO lines placed on the timeline
# Silence between lines is deliberate (brand: calm; no music bed).
ffmpeg -y -f lavfi -t 52.4 -i anullsrc=r=44100:cl=stereo \
  -i vo1.aiff -i vo2.aiff -i vo3.aiff -i vo4.aiff \
  -i vo5.aiff -i vo6.aiff -i vo7.aiff -i vo8.aiff -filter_complex "
  [1]aresample=44100,aformat=channel_layouts=stereo,adelay=900|900[a1];
  [2]aresample=44100,aformat=channel_layouts=stereo,adelay=6400|6400[a2];
  [3]aresample=44100,aformat=channel_layouts=stereo,adelay=10600|10600[a3];
  [4]aresample=44100,aformat=channel_layouts=stereo,adelay=20300|20300[a4];
  [5]aresample=44100,aformat=channel_layouts=stereo,adelay=27000|27000[a5];
  [6]aresample=44100,aformat=channel_layouts=stereo,adelay=33700|33700[a6];
  [7]aresample=44100,aformat=channel_layouts=stereo,adelay=40900|40900[a7];
  [8]aresample=44100,aformat=channel_layouts=stereo,adelay=45700|45700[a8];
  [0][a1][a2][a3][a4][a5][a6][a7][a8]amix=inputs=9:duration=first:normalize=0[mix]" \
  -map "[mix]" -c:a pcm_s16le audio.wav

# ----------------------------------------------------------------- 6. Final mux
ffmpeg -y -i video.mp4 -i audio.wav \
  -c:v copy -c:a aac -b:a 192k -ar 44100 -shortest -movflags +faststart \
  "$OUT/launch-video.mp4"

echo "Done: $OUT/launch-video.mp4"
