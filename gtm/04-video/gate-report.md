# Launch Video - Gate Report

**Gate (from the master prompt):** the file exists; ffprobe confirms duration/resolution/audio; frames at 0/25/50/75/100% extracted and viewed; frame strip saved; VO/caption script matches frames and passes the voice rules.

**Verified 2026-07-15 by the orchestrator (not by the producing agent alone):**

- `launch-video.mp4`: 52.4s, 1920x1080, h264 30fps yuv420p, AAC 44.1kHz stereo, 4.2MB, faststart. Full output in [ffprobe-report.txt](ffprobe-report.txt).
- Audio is genuinely present: volumedetect mean -20.8dB / max -5.3dB; all 8 Samantha VO lines placed on the timeline; deliberate silence between lines, no music bed (brand: calm).
- Frames extracted at 0% (0s), 25% (13.1s), 50% (26.2s), 75% (39.3s), 100% (52.3s) - all in [frames/](frames/), strip in [frame-strip.png](frame-strip.png), each viewed:
  - 0%: black (0.6s fade-in) - expected.
  - 25%: scene 3, the Ready Screen product mock + "Your workout is already there." - crisp.
  - 50%: scene 5 pillars emerging from a dip-to-black - clean, no text overlap.
  - 75%: scene 6 forgiveness ("Missing a day never zeroes you out." + day-dots with one hollow dot) - crisp.
  - 100%: end card mid-fade-out (1.2s closing fade) - expected; an additional close-card frame at 48s ([frames/frame-close-48s.png](frames/frame-close-48s.png)) verifies the full end card: wordmark, "Rep Today, Rest Tomorrow", "Coming soon to iOS", and the clearance line, all legible.
- Script ([script.md](script.md)) matches the frames scene for scene; every VO line passes the voice rules (identity-framed, plain, no hype, no health claims, no streak positivity, no em dashes).

**Change made at the gate:** the first render crossfaded text scenes into each other, producing overlapping text mid-transition (visible in the original 50% frame).
Scene-to-scene transitions were switched to dip-through-black (`xfade=fadeblack`) in [build/build.sh](build/build.sh) and the video re-rendered; intra-scene keyframe reveals keep plain fades.

**Changes made after the red team (video rebuilt and re-gated 2026-07-15):**
- VO line 5 dropped the comparative "real" ("bodyweight strength, mobility, and the kind of moving you did when you were seven") per the FTC-minded reviewer.
- The end card's legal line changed from the trademark-clearance caveat to "Screen images simulated. App is pre-release." - the lawyer persona demanded a simulated-screens disclosure, and the cynical-user persona was right that trademark housekeeping in a consumer video's final frame reads as doubt; the trademark caveat lives in every written asset instead. Verified in [frames/frame-close-48s.png](frames/frame-close-48s.png).
- ffprobe and volumedetect re-run after the rebuild: 52.4s, audio mean -20.8dB / max -5.3dB; all five gate frames re-extracted and re-viewed.

**Known limitation carried openly:** the VO is macOS `say` (Samantha) - an animatic-grade voice. The red team's user persona demands a human re-record before publication; that item is on the [pre-publication checklist](../06-redteam/pre-publication-checklist.md).
The video is fully reproducible with `bash build/build.sh` (requires macOS `say`, Chrome, ffmpeg).
