# Landing site, layout B ("the scroll is a session")

Date: 2026-11-23.
Scope: `gtm/03-site/` (both landing variants, the privacy page's styling, one stylesheet, one small script, fonts and two images) and the Waitlist landing-page checker.
Nothing was published: reptoday.app, Cloudflare, DNS and Kit are untouched, and publishing stays a separate approved step.

## What changed

- `index.html` (variant A) and `index-b.html` (variant B) are rebuilt as layout B in the app's dark look: a pinned "time left" timer and step list, a Warm-Up hero, three Rounds (why, how, price), a Cooldown and a Done section that holds the Waitlist form, with purple Rest beats between.
- `site.css` is the one stylesheet for all three pages, written from `ios/RepToday/RepToday/DesignSystem/Theme.swift` (black ground, push orange, sun yellow, rest purple, Bricolage Grotesque and Inter, pill buttons, 24 px cards).
- `session.js` moves the timer, its bar, the step list and the Rest bars as the page scrolls.
  It only reads the scroll position: links are plain anchors, nothing listens to the wheel or to touches, and nothing snaps or locks.
- On screens under 1040 px the rail becomes a slim pinned bar: the timer, the current step, a Waitlist button and the player's segmented progress bar, one segment a step.
- The app screens on the page (Today, the exercise screen, the score card, the completion mark) are HTML and CSS, matched against captures of the running app (iPhone 17 Simulator, iOS 26.5, a fresh account, a 10 minute Push Day).
  The two Trainer poses are the app's own art, converted to WebP.
- The fonts are subsets of the app's bundled faces, served from `/fonts/` with their licenses, so the site still makes no third-party request.
- `privacy.html` keeps its text unchanged (the visible text of `<main>` is identical before and after, 19,713 characters) and reads the shared stylesheet.
- `_headers` gains cache rules for the stylesheet and the fonts; `DEPLOY.md` and `docs/asset-attribution.md` describe the new files.

## Decisions a reviewer should see

1. **One Waitlist placement a page, not two.**
   Layout B keeps the hero to one Start button and puts the form in Done, with "Skip to the waitlist" always pinned.
   The form's markup, field names, wording, script and behavior are unchanged.
   `tools/waitlist/check-site.py` now requires exactly one closing placement a page (a hero placement or a second one fails), and gains a `form-link` rule: the form sits at `#waitlist` and the page links to it.
   Its tests changed only where they pinned the two-placement layout.
2. **Both A/B variants are kept.**
   The repository records the test as running (the funnel PRD and the Waitlist PRD both say not to disturb it) and holds no record that it ended.
   B still differs from A only by its title and description, its hero copy, and the score section, which sits first under the hero.
3. **Without JavaScript** the page is a plain long page: the step list is ordinary links, the timer is hidden, and the form shows "The sign-up form needs JavaScript.", exactly as the current page does.
4. **Reduced motion** switches off smooth scrolling, transitions and the Rest bars' fill; the timer's digits and the step list still follow the scroll, as plain state changes.
5. **The headline "Open the app. The workout is already there." is kept** as the chosen wireframe's hero.
   It is true on a Training Day (the session is built before the app is opened; a cold launch shows a one-tap Welcome Page first).
   The page now says plainly, in the engine card and in a new FAQ entry, that a Rest Day follows each cycle and has no session waiting.

## Claims corrected

Each row is a claim the old page or the wireframe made that is no longer true of the app on `main`, and what the page says now.

| Where | Before | Now | Why |
| --- | --- | --- | --- |
| Hero, A | "No quiz, no picking, no catalog scroll" | "No picking, no planning, no catalog scroll" | Onboarding asks seven setup steps once. |
| Hero, A | "Unlimited free workouts, no account required." | "Built on your phone, with no connection needed. Unlimited free workouts." | Sign-in is required once, at the end of onboarding. |
| Description, A | "A complete session is on screen the moment the app opens" | "Today's session is already built when you open the app" | A cold launch shows the Welcome Page first, and Rest Days have no session. |
| Hero phone | A mock with "Hip hinge flow", "Bear crawl", pillar labels, "Bear crawl rotates back in" and "Consistency 82" | The real Today screen of a new account: Push Day, 10 minutes, Cobra Stretch, Standard Push-Up 4 x 10, Floor Tricep Dips 4 x 10 | Bear Crawl and the other primal movements are retired, and sessions are Training Days now. |
| Hero, B | "opens to a ready session ... and celebrates a comeback after a week away" | "opens to a session that is already built ... and eases you back in after a week away" | A return gets an easier session; there is no celebration screen. |
| Hero and station 4 | "A missed day can dent your Consistency Score. Nothing can ever zero it." | "A short week can dent your Consistency Score. One missed day never zeroes it." | The score is weekly, and eight empty weeks do compute to zero until a return. |
| Station 1 | "Rep Today never asks. The session is on screen when the app opens" | "Rep Today asks a few setup questions once. After that, today's session is already built when you open the app" | Onboarding questions. |
| Station 3 | "Every Rep Today workout is free, forever." | "Every daily session Rep Today builds is free, forever." | A Custom Workout comes from the Premium Coach. |
| How it works, pricing, FAQ | "76-movement library" (four places) | "69-movement bodyweight library" | 83 movements in the catalog, 14 withdrawn, 69 served. |
| How it works | "No server, no login, no quiz. The session is on screen before you could have typed a password." | Removed; "You sign in once when you set the app up." | Accounts. |
| How it works | "adjusts how fast you progress, what gets emphasized, and how much variety you see" | The steps-of-five rule: finish as written and the next session asks for more, "Too hard" steps back, a cleared rung opens the next up to your level | Emphasis no longer reaches the engine; the rule is the real one. |
| How it works | "Optional AI can add a session-description line with an offline fallback." | Removed | No build calls that service. |
| How it works | The Coach "sends their prompt and necessary derived workout context ... can recommend only bounded between-session tuning. It never generates a workout" | It "sends your message and your training records to OpenAI", can suggest a length, a swap, a reminder or a Custom Workout it writes, changes nothing until confirmed, and "never writes the daily session" | The Coach now reads the account's records and can write a Custom Workout. |
| How it works | "It never asks 'how long do you have?'" | "The app opens at the length you usually finish" | Onboarding asks once; the default is then learned. |
| Pricing, Free | "All three pillars, all 76 movements" | "Every Training Day and every movement ladder, the earned Strength Phase included" | Pillars are gone; the Strength Phase is free. |
| Pricing, Free | "Works offline, no account needed" | "Sessions work offline after a one-time sign-in" | Accounts. |
| Pricing, Premium | "14-day trial" | "14-day free trial on the monthly plan" | Only the monthly product has an introductory offer. |
| Pricing, Premium | "Deeper analytics", "The Strength Phase, included", "Until the Strength Phase unlocks, Premium is the analytics" | The AI Coach and deeper analytics; "The Strength Phase is earned, never bought" | The Strength Phase is not a Premium feature; the Coach is. |
| Score | "Miss a day and your score dips. It never resets ... it celebrates the return" | "Fall short one week and your score dips. It does not reset ... it counts the comeback as a full show-up" | Weekly score; no celebration screen. |
| Short facts | "No account. Nothing to sign up for. ... Sign in with Apple is optional and separate from private CloudKit sync." | "One sign-in": Apple, Google or an email code, then your plan and history save to your account | Accounts replaced iCloud sync. |
| Short facts | "The app works the same with the network off as on." | Removed | Sign-in, saving to the account, the Coach and purchases need a connection. |
| Short facts | "requires no workout equipment" | adds "a patch of floor and, for a few movements, a wall" | Four served movements use a wall. |
| Library | "Mobility is a pillar, not a warm-up", mobility "weighted equally", "Primal movement ... a first-class pillar", "Push, hinge, squat, and hold patterns", "Difficulty backs off immediately ... climbs gradually" | Three facts: strength Training Days in rotation, ladders, stretches at both ends | Sessions are strength-first, mobility is the warm-up and cooldown, primal is retired. |
| About | "The session is already on the screen when you open the app", "Every day it lays a complete session out" | "Today's session is already built when you open the app", "Every training day" | Welcome Page and Rest Days. |
| FAQ | "It is not a strength program, not coaching" | "It is not a gym program, not a personal trainer" | Sessions are strength Training Days and Premium has a Coach. |
| FAQ | (none) | "Is there a workout every day?" | Rest Days. |
| FAQ, internet | "The core workout experience does not need internet ... AI-generated session language ... private CloudKit synchronization" | Setup needs a connection once; sessions do not; saving to the account, the Coach, purchases and account deletion do | Accounts; no AI session language. |
| FAQ, own workout | "No." | "Not from scratch", with Different workout and the Coach's Custom Workout | Both exist now. |
| FAQ, account | "No. The app works fully without one." | "Yes, one." | Accounts. |
| FAQ, movements | Push-up ladder from a wall and knee push-up; "three pillars"; a variety window rotating movements; "Your first week is deliberately varied across all three pillars" | Ladder from the standard push-up (wall, incline or knee version offered as its cue) through wide and diamond toward archer and one-arm; the day varies (Push, Pull, Legs, rest); stretches rotate; Different workout | Retired rungs, the fixed rotation. |
| FAQ, free tiers | "instant open, offline, question-free" | "already built, offline after setup, nothing to pick" | Setup questions and sign-in. |
| FAQ, data | "the core loop needs no account: your history lives on your device, with optional sync to your own private iCloud"; "The app plans minimal anonymous usage measurement" | History is stored on the phone first and saved to the account; the app collects that measurement and it can be turned off; the Coach sends records to OpenAI | Accounts; the measurement shipped with an opt-out. |
| Wireframe | "No account required" in the Cooldown strip | "No streaks" | Accounts. |
| Wireframe | "Premium adds the AI Coach · [PLANNED PRICE]" | The site's planned prices, $7.99 a month or $59.99 a year, marked planned | Those are the values in the app's StoreKit test configuration; no other price is recorded. |

No rating, review, user count or price was added.
The four sourced quotes of Round 1 and the three evidence quotes keep their wording, attributions and links.
The footer, the privacy link, the pre-launch status line and the FAQ's Waitlist sentence are kept.

## Checks run

| Check | Result |
| --- | --- |
| `python3 tools/waitlist/test-check-view.py` | pass |
| `python3 tools/waitlist/check-site.py` | pass |
| `python3 tools/waitlist/test-check-site.py` (24 tests) | pass |
| `node tools/waitlist/test-source.cjs` (29 tests; `waitlist.js` is unchanged) | pass |
| `python3 tools/waitlist/test-waitlist.py` | pass |
| `python3 tools/check-no-waitlist-credentials.py`, `python3 tools/test-check-no-waitlist-credentials.py` | pass |
| `python3 tools/check-no-committed-telemetry-secret.py` | pass |

### Local sign-up (stub receiver, no request left the machine)

The page was served with `wrangler pages dev` and signed up against `tools/waitlist/stub-receiver.py` with a synthetic address.

- Arriving by `/tiktok`, `/youtube`, `/reddit` and `/network` (and `/youtube/`), then moving to `/` or `/index-b`, the hidden Source held the tag and the sign-up body carried it; plain `/` and `/index-b` carried `unknown`.
- Every sign-up posted exactly `email_address`, `fields[fit]`, `fields[beta_opt_in]` and `fields[source]`, once.
- Each landing page load sent one `landing_page_view` and each sign-up one `waitlist_signup`, with `referrer_source` set to the tag or `none`, as `text/plain` with no cookie; `/privacy` sent none.
- The same run against the page on `main` produced the same bodies and the same events.
- An empty submit showed both approved error messages and moved focus to the email field.

### Browser checks (Chrome through the DevTools bridge)

- Screenshots at 390, 768 and 1440 px wide at the top, mid-scroll (Round 2) and the form, in three modes: normal, reduced motion (`--force-prefers-reduced-motion`) and site JavaScript blocked.
  They are kept with the task's records outside the repository, with the Simulator captures the app screens were matched against.
- With JavaScript blocked: no `js` class, the timer is not displayed, the six step links are plain anchors, the form is hidden behind its message, and no width overflows.
- With reduced motion: `scroll-behavior` is `auto`, the Rest bars keep their drawn width, and the timer still reads the scroll position.
- Contrast: every text and control color pair in `site.css` clears WCAG AA (lowest text pair 6.55:1, orange on a section; lowest control edge 5.25:1, the email field).
  The idle step segments of the small-screen bar were 1.52:1 in the app's track color, so the site draws them lighter there (3.28:1), since each is a link.
- Keyboard: Tab runs skip link, wordmark, "Skip to the waitlist", the six steps, Start, then the page in reading order, each with a 3 px yellow focus ring.
  On wide screens "Skip to the waitlist" is drawn at the foot of the rail but comes before the step list in the order, as a skip link does.

### Page weight (one landing page load, text gzipped)

| | Requests | Bytes on the wire |
| --- | --- | --- |
| Before (`index.html`, `waitlist.js`) | 2 | 16,731 |
| After (`index.html`, `site.css`, `session.js`, `waitlist.js`, six fonts, two images) | 12 | 116,486 |

The six font files are 71,400 bytes and the two Trainer images 20,202; all are same-origin, shared by the three pages and cached after the first.

## Not tested

- A real submission to the production Kit form was not made, on purpose: it would create a real sign-up, and nothing here is deployed.
  The local run shows the request is the one the current page sends.
- Kit's interactive check was not shown in the new styling; the stub's stand-in is covered by the script tests, and the frame sits on a white panel so Kit's own page stays readable.
- No real phone or Safari was used; Chrome's device emulation stands in for 390 and 768 px.
- The production web events were not sent (a local page sends none unless a test names a sink).

## Left for the owner

- The look and feel, the corrected wording above, and whether the two variants should continue.
- `privacy.html` section 11 says the Waitlist "is separate from the app, which never asks for your email", while section 4 of the same page says the app offers sign-in by an email code.
  The policy's text was out of scope here and is unchanged.

## Recovery

Revert the pull request.
The live site changes only at a separate publish, which can be rolled back to the previous Pages deployment.
