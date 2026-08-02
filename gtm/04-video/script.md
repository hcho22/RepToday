# Rep Today - launch video script

1920x1080, 30fps, H.264 + AAC.
Total runtime 52.4 seconds.
Night theme throughout (bg `#14181C`, text `#F1EEE8`, secondary `#A7B0B8`, accent `#5FA981`).
Voice: macOS Samantha.
No music bed - silence between lines is deliberate (relief, not aspiration).
Scenes join with 0.8s dip-through-black transitions (D-008) so text never overlaps text; intra-scene keyframe reveals use plain fades; single-frame scenes carry a subtle zoom drift so nothing sits fully static.

## Timeline

"Scene from" is when the scene is fully on screen after its crossfade in.

### Scene 1 - Cold open (0.0 - 5.2s)

- VO (0.9s): "It's nine at night. You have twelve minutes, and no equipment."
- On-screen: **9:12 pm.** / "12 minutes. No equipment."
- Visual: dark frame, big clock line centered, Mist subline. Fades in from black.

### Scene 2 - The turn (5.2 - 9.4s)

- VO (6.4s): "So open the app. The workout is already there."
- On-screen: no text. The Ready Mark (Fern on Night) draws itself in across three keyframes: partial square (5.2s), complete square (~6.8s), then the Start circle lands (~8.2s) as the VO says "already there".

### Scene 3 - Product proof: the Ready Screen (9.4 - 19.1s)

- VO (10.6s): "A full bodyweight session, built on your phone in under one hundred milliseconds. No questions. No account. No internet needed."
- On-screen, left: **The workout is already there.** / "Built on your phone in under 100 milliseconds. No questions. No account. No internet needed."
- On-screen, right: faithful Ready Screen phone mock, Night theme - "Today / 12 min", four session blocks (Push-ups - Strength - 3 min, Hip hinge flow - Mobility - 3 min, Bear crawl - Primal - 3 min, Wall sit - Strength - 3 min), one dominant Fern **Start** button.

### Scene 4 - One tap (19.1 - 25.8s)

- VO (20.3s): "Got twenty minutes instead of ten? One tap. The session rebuilds before your thumb lifts."
- On-screen: **Got 20 minutes instead of 10?** over the duration chip row 5 / 10 / 15 / 20 / 30 / 45 / 60 ("minutes"). The active chip is 10; at ~22.3s it flips to 20 as the VO says "One tap", and the lines **One tap.** / "The session rebuilds before your thumb lifts." appear below.

### Scene 5 - Three pillars (25.8 - 32.5s)

- VO (27.0s): "Bodyweight strength, mobility, and the kind of moving you did when you were seven."
- On-screen: **Strength.** / **Mobility.** / **Primal.** stacked; each word lights up from dim to full Bone in time with the VO (~25.8s, ~28.6s, ~30.4s).

### Scene 6 - Forgiveness (32.5 - 39.7s)

- VO (33.7s): "There are no streaks to lose here. Miss a day, and your score dips. It never resets."
- On-screen: **Missing a day never zeroes you out.** Below, a row of 14 Fern day-dots with one hollow Mist ring in the middle - dented, not erased. Caption: "Your score dips. It never resets."

### Scene 7 - Free (39.7 - 44.4s)

- VO (40.9s): "The workouts are free. All of them. Forever."
- On-screen: **Free means the workouts.** / **All of them. Forever.**

### Scene 8 - Close (44.4 - 52.4s)

- VO (45.7s): "Rep Today. You're someone who moves."
- On-screen: wordmark lockup (Ready Mark + "Rep Today"), then "Opens to a ready workout" (the listing subtitle; the v1 "Rep Today, Rest Tomorrow" line is killed per the v2 naming decision), "Coming soon to iOS", and the disclosure line "Screen images simulated. App is pre-release." at the bottom.
- Visual: holds ~4s after the VO, then fades to black over the final 1.2s.

## VO lines only (for re-recording)

1. It's nine at night. You have twelve minutes, and no equipment.
2. So open the app. The workout is already there.
3. A full bodyweight session, built on your phone in under one hundred milliseconds. No questions. No account. No internet needed.
4. Got twenty minutes instead of ten? One tap. The session rebuilds before your thumb lifts.
5. Bodyweight strength, mobility, and the kind of moving you did when you were seven.
6. There are no streaks to lose here. Miss a day, and your score dips. It never resets.
7. The workouts are free. All of them. Forever.
8. Rep Today. You're someone who moves.

## Rebuild

Run `build/build.sh` (needs macOS `say`, Google Chrome, ffmpeg).
Scene visuals are the `build/scene*.html` files; keyframed scenes take a `?k=N` query parameter.
