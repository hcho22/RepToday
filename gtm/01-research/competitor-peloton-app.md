# Competitor Teardown: Peloton App (app subscription, not the bike)

Research date: 2026-07-15 (all fetches between 04:18Z and 04:21Z).
All claims below are backed by pages actually fetched during this run; see Sources.

## TL;DR

Peloton App is a subscription library of instructor-led classes ("Work out, your way" / "Thousands of classes, no equipment needed") priced at $15.99/mo (App One) or $28.99/mo (App+) per the App Store page fetched 2026-07-15 (https://apps.apple.com/us/app/peloton-fitness-workouts/id792750948).
Its free tier was closed to new signups in April 2024 (https://www.pelobuddy.com/free-app-tier-ending/).
The core loop is choosing a class from a large catalog, and standard classes require an internet connection to begin playback (https://www.pelobuddy.com/just-work-out-offline/).
Gamification is heavy: milestone badges, daily and weekly streak badges, challenges, leaderboards, and a Bronze-to-Legend points/levels system called Club Peloton (https://www.onepeloton.com/blog/milestones, https://www.onepeloton.com/blog/what-is-club-peloton).
It is a 4.9-star, 813K-rating, Editors' Choice juggernaut whose strengths (instructors, community, production) and mechanics (streaks, class browsing, connectivity) are almost the photographic negative of Rep Today's wedge.

## 1. What it is and positioning

The App Store listing is "Peloton: Fitness & Workouts", subtitled "Yoga, Cardio & Gym Training", with the hero message "Work out where you want, when you want" and classes spanning strength, meditation, outdoor running, and yoga (https://apps.apple.com/us/app/peloton-fitness-workouts/id792750948, fetched 2026-07-15).
The website's app page leads with "Work out, your way" and "Thousands of classes, no equipment needed" (https://www.onepeloton.com/app, fetched 2026-07-15).
The listing carries an Apple Editors' Choice award and a 4.9/5 rating from 813K ratings as of the fetch (https://apps.apple.com/us/app/peloton-fitness-workouts/id792750948).
Positioning is instructor- and community-led content: the Editors' Choice note on the page says "each on-demand workout class is a community affair with a leaderboard" (https://apps.apple.com/us/app/peloton-fitness-workouts/id792750948?see-all=reviews).

## 2. Pricing and free-tier shape

In-app purchases listed on the App Store page, fetched 2026-07-15: Peloton App One $15.99/mo or $159/yr; Peloton App+ $28.99/mo or $289/yr (https://apps.apple.com/us/app/peloton-fitness-workouts/id792750948).
The website promotes a "30-day free trial" with "Credit card required"; its price fields rendered as "$0/mo" placeholders in the fetched HTML, so site pricing could not be read directly (https://www.onepeloton.com/app, fetched 2026-07-15).
Peloton launched a free tier in May 2023 but ended new free-tier signups in April 2024, keeping existing free members; CFO Liz Coddington said the free tier was "cannibalizing" efforts to convert free-trial members to paid subscribers, and the default trial shrank from 30 days to 7 at that time (https://www.pelobuddy.com/free-app-tier-ending/, article dated 2024-04-16).
That same article listed App One at $12.99/mo and App+ at $24/mo in April 2024, versus $15.99/$28.99 on the App Store today, indicating prices have risen since (https://www.pelobuddy.com/free-app-tier-ending/ vs https://apps.apple.com/us/app/peloton-fitness-workouts/id792750948).
Per the same article, App One caps hardware-based (Bike/Tread) classes at three per month (https://www.pelobuddy.com/free-app-tier-ending/).
Net: today the app is effectively trial-then-pay, with no free workout tier for new users.

## 3. Onboarding and session-start friction

The product model is a catalog: "thousands of classes" that the user browses and picks from, with features for scheduling, stacking, and bookmarking classes (https://www.onepeloton.com/app; https://apps.apple.com/us/app/peloton-fitness-workouts/id792750948).
Those scheduling/stacking/bookmarking features exist because selecting the session is the user's job; nothing on the fetched pages describes the app opening to an already-assembled, ready-to-start workout.
[ASSUMPTION] Whether onboarding asks goal/equipment questions before the first class could not be verified from fetched pages (Peloton's support articles returned 401/404 to anonymous fetches), so I make no claim about a signup quiz.
The closest thing to an instant start is "Just Work Out", a self-directed activity-tracking mode without an instructor-led class (https://www.pelobuddy.com/just-work-out-offline/).

## 4. Equipment assumptions and offline capability

No equipment is required for most classes, and the app pitches workouts "on any exercise bike, treadmill, or rower" at the App+ tier (https://apps.apple.com/us/app/peloton-fitness-workouts/id792750948; https://www.onepeloton.com/app).
Peloton hardware owners are pushed to a separate All-Access Membership: "Have Peloton equipment? You need an All-Access Membership instead" (https://www.onepeloton.com/app).
Offline: as of a March 15, 2024 report, only Just Work Out runs fully offline ("No connection? No problem. You can still track an activity while offline."), syncing when reconnected; standard instructor-led classes still require preloading, which "demands an active connection to begin playback" (https://www.pelobuddy.com/just-work-out-offline/).
The same article notes users were unsure whether an offline workout that syncs the next day still earns the activity credit ("blue dot") for the day it was done (https://www.pelobuddy.com/just-work-out-offline/).

## 5. Gamification

Heavy and central.
Milestone badges at 1, 10, 25, 50, 75, and 100 classes per discipline, "plus continue racking them up for every 50 classes you take after that", plus special-event badges, all shown in a profile Achievements tab (https://www.onepeloton.com/blog/milestones).
Streaks: "both daily and weekly streaks have badges" (https://www.onepeloton.com/blog/milestones).
Club Peloton is a points-and-levels system, "built to recognize Members for staying active", with 11 levels from Bronze through Legend, points for workouts, streaks, milestones, challenges, and community engagement, and unlockable badges and partner rewards (https://www.onepeloton.com/blog/what-is-club-peloton).
Leaderboards and challenges are core to the class experience per the App Store listing (https://apps.apple.com/us/app/peloton-fitness-workouts/id792750948).

## 6. Review themes (from fetched App Store pages only)

Strengths praised: instructor quality and workout fun, portability beyond the bike, and low activation energy for short sessions.
"Great all around workout app. We do have the bike but the app is great to workout anywhere." (review titled "Always improving" by Sprnutrifitmom, https://apps.apple.com/us/app/peloton-fitness-workouts/id792750948?see-all=reviews).
"...it's easy to talk myself into a 20 minute workout" (review by URMomFromCollege, same page).
Complaints: outdoor GPS tracking accuracy, app crashes during outdoor workouts, phone overheating, a removed multi-view casting feature, and hardware customer support.
"The app still crashes with outdoor workouts sometimes right away sometimes in the middle" (review by D M A 12, https://apps.apple.com/us/app/peloton-fitness-workouts/id792750948?see-all=reviews).
Caveat: these are the handful of reviews Apple surfaces on the web listing, not a statistical sample; a third-party review aggregator (justuseapp.com) returned 403 and could not be used.

## 7. Wedge contrast: Rep Today vs Peloton App

- Ready-on-open vs pick-a-class: Peloton's model is browsing "thousands of classes" with scheduling/stacking tools (https://www.onepeloton.com/app); Rep Today opens to one pre-generated session with a single Start button and never asks questions before Start.
- Offline by construction vs online-first: Peloton's instructor-led classes need a connection to begin playback, with offline limited to the self-directed Just Work Out mode (https://www.pelobuddy.com/just-work-out-offline/); Rep Today generates every session on-device, deterministically, fully offline.
- Forgiving consistency vs streak-and-badge stack: Peloton runs daily/weekly streak badges, milestones, challenges, leaderboards, and a Bronze-to-Legend level system (https://www.onepeloton.com/blog/milestones; https://www.onepeloton.com/blog/what-is-club-peloton); Rep Today's Consistency Score is rolling and never zeroes, and has no XP, levels, badges, or leaderboards anywhere.
- Free core loop vs trial-then-pay: Peloton closed its free tier to new users in April 2024 and now converts via a credit-card trial into $15.99-$28.99/mo (https://www.pelobuddy.com/free-app-tier-ending/; https://apps.apple.com/us/app/peloton-fitness-workouts/id792750948); Rep Today's unlimited workouts are free forever, with ~$7.99/mo premium gating only depth.
- Content library vs generated micro-sessions: Peloton sells instructor personality, community, and production value, including equipment-tier upsells (https://www.onepeloton.com/app); Rep Today sells a 5-60 minute bodyweight session that passes the "hotel room test" - no instructor video, no equipment, no community layer to maintain.

## Sources

All fetched with WebFetch on 2026-07-15 (UTC, minute precision).

- https://apps.apple.com/us/app/peloton-fitness-workouts/id792750948 - 04:18Z - name, subtitle, hero message, IAP prices ($15.99/$28.99 monthly; $159/$289 annual), 4.9/813K rating, Editors' Choice, leaderboards/challenges, no-equipment claim.
- https://www.onepeloton.com/app - 04:19Z - "Work out, your way", "Thousands of classes, no equipment needed", 30-day trial with credit card, $0/mo price placeholders, All-Access redirect for hardware owners.
- https://apps.apple.com/us/app/peloton-fitness-workouts/id792750948?see-all=reviews - 04:19Z and 04:21Z - verbatim review snippets (Sprnutrifitmom, URMomFromCollege, D M A 12, Eag146, tinacristina27, Dr Kefla) and Editors' Choice quote.
- https://www.pelobuddy.com/just-work-out-offline/ - 04:19Z - Just Work Out offline mode (2024-03-15), classes require connection to begin playback, offline sync and streak-credit uncertainty.
- https://www.pelobuddy.com/free-app-tier-ending/ - 04:20Z - free tier ended for new signups April 2024, existing members kept, trial cut 30d to 7d, April 2024 prices $12.99/$24, App One 3 equipment classes/month, CFO "cannibalizing" quote.
- https://www.onepeloton.com/blog/milestones - 04:20Z - milestone badge thresholds, special-event badges, daily and weekly streak badges, Achievements tab.
- https://www.onepeloton.com/blog/what-is-club-peloton - 04:20Z - Club Peloton points system, 11 levels Bronze through Legend, badges and partner rewards.

Failed fetches (not cited): support.onepeloton.com articles (401/404 to anonymous fetch), justuseapp.com reviews (403).
