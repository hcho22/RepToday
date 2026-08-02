# 14-day posting calendar (window 1)

One asset per day, posted to BOTH platforms the same day (identical content per `platform-assignment.md`); the listed platform is the primary whose metrics adjudicate.
A/B pair legs post exactly 7 days apart in the same weekday and time slot, so day N and day N+7 are each other's controls to the extent a sequential test allows.
[ASSUMPTION] One asset per day is a solo-founder production ceiling; sustaining the calendar matters more than density because the signal is relative rank across posts.
Posting time: pick one consistent local-evening slot on day 1 and never vary it during the window, so time-of-day is held constant.
Nothing posts until the pre-publication checklist at the bottom passes for that asset.

## The calendar

| Day | Asset | Angle / pair leg | Primary platform | Notes |
|---|---|---|---|---|
| 1 | Cold-open demo, hook A | P01 / AB-1 leg A | TikTok | The core demo asset; recorded once, reused across the kit |
| 2 | Founder reads paywall review, pain-first cut | P07 / AB-3 leg A | TikTok | Founder on camera |
| 3 | Missed-day score record | P03 / AB-2 leg A | YouTube Shorts | Silent mechanic demo |
| 4 | Founder comeback story | P02 | TikTok | Founder on camera; Hero B hook |
| 5 | Airplane-mode demo | P11 | YouTube Shorts | |
| 6 | No-streaks contrarian, declaration-led | P09 / AB-6 leg A | TikTok | Founder on camera |
| 7 | 5-minute timelapse | P04 (single leg this window; AB-5 queued) | TikTok | Evening: DAY-7 MIDPOINT REVIEW (below) |
| 8 | Cold-open demo, hook B | P01 / AB-1 leg B | TikTok | Same asset as day 1, only the hook changes |
| 9 | Founder reads paywall review, promise-first cut | P07 / AB-3 leg B | TikTok | Same footage as day 2, re-cut opening |
| 10 | Missed-day score record, negation hook | P03 / AB-2 leg B | YouTube Shorts | Same asset as day 3 |
| 11 | Mobility-as-relief session scroll | P08 | YouTube Shorts | |
| 12 | Discipline inversion | P10 | TikTok | The ONE sanctioned inversion test; founder on camera |
| 13 | No-streaks contrarian, curiosity-led | P09 / AB-6 leg B | TikTok | Same asset as day 6, re-cut opening |
| 14 | Flex slot | Double-down re-cut of the day-7 review's top angle; if nothing qualifies under the rules below, post P14 (no-signup demo) | TikTok | |

Pairs running this window: AB-1, AB-2, AB-3, AB-6.
Pre-registered but queued for window 2: AB-4, AB-5, and angles P05, P06, P12, P13, P15, P16.
Their hooks are frozen in `ab-pairs.md` and `creative-log.json` now, before any results exist.

## Day-7 midpoint review gate

Run on the evening of day 7, on days 1-5 posts only (days 6-7 are too fresh to read).

Decision rules, in order:

1. Impression floor check: any post under 200 impressions on its primary platform is UNREAD; it enters no ranking and triggers no decision.
2. If ALL of days 1-5 are unread on both platforms: this is a distribution problem, not a message problem.
   Continue the calendar unchanged (the experiment needs its full n), but check for mechanical causes only: posting-slot consistency, caption length, hashtag hygiene, video resolution.
   Do not rewrite any hook mid-window.
3. If >=3 posts are readable: rank them on each post's own pre-registered signal (bank-relative rank as defined in `angles.md`).
   The top post's angle earns the day-14 flex slot as a double-down re-cut (same angle, new footage, same hook) IF it also cleared its signal threshold, not merely ranked first among weak posts.
4. Kill checks fire only on the criteria pre-registered in `angles.md`, which all require two consecutive weekly reads; nothing can be killed at day 7.
   Day 7 may only flag "at risk" status in `creative-log.json`.
5. Comment handling is part of the experiment: the founder replies to every substantive comment within 24 hours; comment language gets logged as hook-mining input.

## Kill and double-down rules (window level)

- Kill: an angle retires when its pre-registered kill criterion in `angles.md` is met (two consecutive weekly reads at or under the criterion, both reads above the impression floor).
  A killed angle's status flips to "killed" in `creative-log.json` with the two read dates; the hook is never quietly recycled into another angle.
- Double-down: an angle that ranks top quartile on its pre-registered signal across two consecutive reads earns two extra production slots in the next window (new footage, hook variations become a new pre-registered A/B pair first).
- A/B adjudication: a pair resolves only if both legs are readable and the rank gap is large (see `read-the-results.md`); otherwise the pair reposts in window 2 before any hook is declared the winner.
- P10 special rule (from positioning.md): the discipline inversion gets this single test.
  Whatever the numbers, any drill-sergeant misreading in the comments retires it permanently to the essay layer; there is no window-2 rerun for P10.
- The calendar never adds mechanics the product refuses: no countdowns, no challenges, no streak-style "day N of posting" framing in captions.

## Pre-publication checklist (every asset, every day)

- Status lines are true on the day of posting (pre-launch, no listing, no invented numbers).
- Name is "Rep Today" in prose; no trademark or registration claim or implication.
- Any post that says "AI" carries the disclosure in the same post or its pinned first comment: at launch the policy tuner is deterministic on-device logic, and the app's only AI-generated text is one optional line with an offline fallback.
- No em dash characters, no health claims, no competitor-motive claims, no engagement-machinery language.
- Founder is on camera for every first-person line.
- Screen recordings are real device, real time, cuts only where the shot list declares them.
