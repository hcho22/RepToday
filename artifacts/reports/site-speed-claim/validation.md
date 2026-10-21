# Site speed claim removed (2026-10-21)

The landing pages no longer state a millisecond speed for building a session.
The "under 100 milliseconds" figure has not been measured on a real iPhone XS on iOS 17, and the pre-publication checklist keeps it out of anything public until it is.
The sentences now say only what is true without that measurement.

## What changed

| Line | Arm | Before | After |
| --- | --- | --- | --- |
| `index.html` meta description | A only | "...built on your phone, offline, in under 100 milliseconds. Coming soon to iOS." | "...built on your phone, offline. Coming soon to iOS." |
| `index.html` hero proof line | A only (B's proof line is different copy) | "Generated on your phone, offline, in under 100ms. Unlimited free workouts, no account required." | "Generated on your phone, offline. Unlimited free workouts, no account required." |
| "1. The engine" card | A (`index.html`) and B (`index-b.html`) | "...from a 76-movement library in under 100 milliseconds, fully offline..." | "...from a 76-movement library, fully offline..." |

Two non-breaking spaces keep the shortened lines from ending on a single word at 390 px: "account&nbsp;required." in the A hero proof line and "a&nbsp;password." in both arms' engine card.
No other word changed.
`privacy.html` still says telemetry may carry "a generation time in milliseconds"; that describes a data field, not a speed claim, and is unchanged.

## Checks

- `grep -rniE '100 *ms|100 milliseconds|millisecond' gtm/03-site/` matches only the `privacy.html` telemetry line above.
- The difference between the two arms is the same before and after except for the two A-only lines.
- Both pages were served from a local `python3 -m http.server` on `127.0.0.1` and viewed with `chrome-devtools-axi` at 390x844 (mobile emulation) and 1440x900.
  `waitlist.js` sends web events only from the production hosts and posts sign-ups only to the local stub on `127.0.0.1`; the form was never submitted.
- `document.documentElement.scrollWidth` equals the viewport width on both pages at both widths, before and after (no horizontal scroll).

## Screenshots

`before-*` and `after-*` pairs, one per page and width:

- `*-a-hero-390.png`, `*-a-hero-1440.png`: the A hero proof line.
- `*-a-engine-390.png`, `*-a-engine-1440.png`, `*-b-engine-390.png`, `*-b-engine-1440.png`: the engine card in each arm.

The "before" 390 px engine card already ended on "password." alone; the "after" shots show it fixed in both arms.
