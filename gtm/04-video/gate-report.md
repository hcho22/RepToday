# Launch Video - Gate Report

**Gate (from the master prompt):** the file exists; ffprobe confirms duration/resolution/audio; frames at 0/25/50/75/100% extracted and viewed; frame strip saved; VO/caption script matches frames and passes the voice rules.

## v2 rebuild - verified 2026-08-01

The video was audited against the locked v2 positioning and rebuilt from source with `bash build/build.sh`.

**v2 audit findings and fixes (this is an update, not a re-imagining; v1's structure passed its gates):**

- **D-106 violation (fixed):** the end card carried the killed listing name "Rep Today, Rest Tomorrow".
  Replaced with the listing subtitle "Opens to a ready workout" in `build/scene8.html` and `script.md`.
- **Hero A wording drift (fixed):** VO line 2 and the scene 3 headline said "Your workout is already there"; v2 Hero A is "Open the app. The workout is already there."
  VO line 2 is now "So open the app. The workout is already there." (the "So" is the narrative bridge from scene 1) and the scene 3 headline is "The workout is already there." (`build/build.sh`, `build/scene3.html`, `script.md`).
- **Claims hygiene:** audited every VO line and on-screen string; no unqualified "every workout app" absolutes exist (the script states only our own mechanics), no health/medical claims, no em dashes.
- **§4 discipline register:** all lines pass (friction is the enemy, never character; no grind register; the miss-a-day scene states the mechanic without shaming; close is identity-framed: "You're someone who moves").
- **Doc accuracy (fixed):** `script.md` still described scene joins as "crossfades"; corrected to the dip-through-black transitions the build actually uses (kept per D-008).

**ffprobe (full output in [ffprobe-report.txt](ffprobe-report.txt)):**

- `launch-video.mp4`: 52.4s, 1920x1080, h264 30fps yuv420p, AAC 44.1kHz stereo, 4.16MB, faststart.
- Audio genuinely present: volumedetect mean -20.9dB / max -5.3dB; all 8 Samantha VO lines placed on the timeline; deliberate silence between lines, no music bed (brand: calm).

**Frames extracted at 0% (0s), 25% (13.1s), 50% (26.2s), 75% (39.3s), 100% (52.3s), all in [frames/](frames/), strip rebuilt in [frame-strip.png](frame-strip.png), each viewed with my own eyes this rebuild:**

- 0%: black (0.6s fade-in) - expected.
- 25%: scene 3, the Ready Screen product mock (Today / 12 min, four blocks, one dominant Fern Start) beside the corrected v2 headline **"The workout is already there."** - crisp, no artifacts.
- 50%: scene 5 pillars emerging from the dip-through-black ("Strength." lit, "Mobility." and "Primal." still dim) - clean, no text overlap.
- 75%: scene 6 forgiveness ("Missing a day never zeroes you out." + 14 day-dots with one hollow Mist ring, caption "Your score dips. It never resets.") - crisp.
- 100%: end card mid-fade-out (1.2s closing fade) showing the NEW end card - "Rest Tomorrow" confirmed gone even in the fading frame.
- Additional close-card frame at 48s ([frames/frame-close-48s.png](frames/frame-close-48s.png)) verifies the full end card at full brightness: Ready Mark + "Rep Today" wordmark, **"Opens to a ready workout"**, "Coming soon to iOS", and the disclosure "Screen images simulated. App is pre-release." - all legible, no "Rest Tomorrow" anywhere.

**Script ([script.md](script.md)) matches the frames scene for scene; every VO line passes the voice rules (identity-framed, plain, no hype, no health claims, no streak positivity, no em dashes).**

## Carried from the v1 gate (2026-07-15)

- Scene-to-scene transitions are dip-through-black (`xfade=fadeblack`) so text never overlaps text (the v1 gate caught overlapping text with plain crossfades); intra-scene keyframe reveals keep plain fades. Preserved in this rebuild per D-008.
- VO line 5 keeps the red-team edit (no comparative "real").
- The end card's legal line stays "Screen images simulated. App is pre-release." (red-team: simulated-screens disclosure in the video; trademark caveat lives in the written assets).

**Known limitation carried openly:** the VO is macOS `say` (Samantha) - an animatic-grade voice. A human re-record before publication remains on the [pre-publication checklist](../06-redteam/pre-publication-checklist.md).
The video is fully reproducible with `bash build/build.sh` (requires macOS `say`, Chrome, ffmpeg).
