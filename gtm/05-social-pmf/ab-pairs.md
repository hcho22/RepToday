# A/B hook pairs - the isolated variable is the hook, nothing else

Rules that make these pairs valid experiments:
Same angle, same asset body, same format, same platform, same posting time slot.
Only the hook (first 3 seconds of on-screen text plus the first caption line) changes.
Legs post 7 days apart in the same weekday/time slot, because a zero-follower account has no ad-platform split testing; this is sequential A/B, which confounds time.
Honesty rule carried into `read-the-results.md`: only large rank differences between legs count as signal; small deltas at this sample size conclude nothing.
Each leg needs >=200 impressions before its read counts; a leg below the floor is UNREAD, not a loser.

## AB-1: ready-on-open demo (angle P01, TikTok, same cold-open screen record)

- Leg A hook: "Most workout apps open with a question. This one opens with the workout."
- Leg B hook: "Open the app. The workout is already there."
- Belief tested: does the softened category-contrast opener (the defensibility judge's "most" version) out-hold the bare Hero A declarative?
  If B wins, the contrast framing is dead weight and the mechanic carries itself; if A wins, the scroller needs the category named to feel the difference.

## AB-2: forgiveness mechanic (angle P03, YouTube Shorts, same missed-day screen record)

- Leg A hook: "Miss a day and your score dips. It never resets."
- Leg B hook: "Missing a day never zeroes you out."
- Belief tested: does admitting the cost (the dip) make the promise more believable than the pure negation of loss?
  Positioning.md carries both lines; this pair decides which one leads the forgiveness surface.

## AB-3: free-forever wedge (angle P07, TikTok, same founder-on-camera video body)

- Leg A hook: the video opens with the founder reading the verbatim review "you cannot use this app unless you pay for it. You just can't." (source: https://apps.apple.com/us/app/30-day-fitness-workout-at-home/id1099771240), promise second.
- Leg B hook: the video opens with "Free means the workouts. All of them. Forever.", review read second.
- Belief tested: pain-first versus promise-first ordering for the number-one mined pain; everything after the first 3 seconds is identical footage re-cut.

## AB-4: on-device speed (angle P06, YouTube Shorts, same slow-motion asset)

- Leg A hook: "The workout is built before the screen finishes appearing."
- Leg B hook: "Generated on your phone, offline, in under 100 milliseconds."
- Belief tested: does the perceptual claim outperform the technical spec, or does the concrete number ("100 milliseconds") read as more credible than an impression?
  Comment sentiment on B specifically watched for the number being dismissed as marketing.
- Substantiation gate: the number in leg B is a PRD requirement, not yet a device measurement; leg B may not post until the real-hardware benchmark record required by `../08-redteam/pre-publication-checklist.md` exists, even though the hook is frozen here now.

## AB-5: the 5-minute floor (angle P04, TikTok, same timelapse asset)

- Leg A hook: "This whole workout is five minutes. It counts as showing up."
- Leg B hook: "Five minutes on a hotel-room floor still counts."
- Belief tested: abstract permission versus situated scene; does placing the five minutes in a concrete travel context (which also smuggles in zero-equipment) beat the bare claim?

## AB-6: contrarian entry (angle P09, TikTok, same founder-plus-screen-record asset)

- Leg A hook: "I built a workout app with no streaks, on purpose. Watch what happens when I miss a day."
- Leg B hook: "Watch what happens in my app when I miss a day."
- Belief tested: declaration-led versus curiosity-gap-led entry into the same anti-streak demo; A fronts the founder's intent, B withholds it.
  Both legs are founder-on-camera because both contain first-person lines (mandatory per the conversion judge).

## Scheduling note

Four pairs run inside the first 14-day window (AB-1, AB-2, AB-3, AB-6; see `cadence-14-day.md`).
AB-4 and AB-5 are pre-registered here and queue for window 2, so their hooks are frozen now and cannot be quietly rewritten after seeing window-1 results.
