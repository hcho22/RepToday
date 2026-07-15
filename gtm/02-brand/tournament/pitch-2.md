# Pitch 2: Identity and Discipline

Angle: the app is not a workout library, a coach, or a game.
It is the shortest possible path to becoming someone who moves every day.
Showing up is the whole game, and the app's only job is to make showing up trivially easy.

## 1. Positioning statement

For busy, desk-bound adults who have installed and quit fitness apps before, Rep Today is a discipline-first micro-workout app built around one identity: you are someone who moves every day.
Unlike catalog apps that make you browse and choose (Peloton, Apple Fitness+, Nike Training Club), interrogation apps that quiz you before you can start (Freeletics, Down Dog), and streak-and-badge apps that punish a missed day (Seven, Peloton, Freeletics), Rep Today opens to a complete bodyweight session with one Start button, counts a 5-minute session as a full show-up, and never zeroes you out for missing a day.
Because identity is built by repetition, not intensity, every mechanic in the product removes a reason not to start and forgives the days you don't.

## 2. ICP

**Dana, 38. Product manager, two kids, one lapsed gym membership.**

It is 9:12pm.
The kids are down, the laptop is closed, and Dana has about twenty minutes of willpower left in the day.
The gym is a 20-minute round trip that has not happened since March.

What Dana has tried, in order: a gym membership (still auto-renewing), Peloton App (browsed classes for four minutes, picked nothing, closed it), a streak-based habit app (quit for good after one missed day reset everything).
The quit-after-streak-loss mechanism is documented repeatedly in the research: "That was it, back to 0 ... and just stopped using it entirely after that" ([hn.algolia.com/api/v1/items/40903998](https://hn.algolia.com/api/v1/items/40903998)) and "after 200 days, I lost my streak and... breathed a sigh of relief" ([hn.algolia.com/api/v1/items/38919053](https://hn.algolia.com/api/v1/items/38919053)).
The demand for zero decisions is also documented verbatim: "I need an app that requires little decision-making. Big buttons, pre-programmed workouts ... Tell me what to do with no ambiguity" ([hn.algolia.com/api/v1/items/36666806](https://hn.algolia.com/api/v1/items/36666806)).

When Dana uses Rep Today: 9pm in the living room, 7am before standup, or in a hotel room on a work trip (every movement passes the floor-and-wall test).
[ASSUMPTION] Dana's composite profile (age, job, family shape, usage moments) is a construction from the brief's stated audience ("a tired parent at 9pm", desk-bound adults) plus the cited complaint evidence, not from user data.
There are zero users, so there is no Dana yet.
The positioning must recruit her, not quote her.

What Dana is buying: not a fitness outcome, an identity.
She wants to be a person who moves every day, and she wants that to be true even in the weeks when 5 minutes is all she has.

## 3. Name recommendation: keep Rep Today

**Recommendation: back the incumbent, Rep Today.**

Positioning fit.
The name is the daily behavior stated as an instruction: get a rep in, today.
"Rep" is the smallest unit of showing up, and "Today" scopes the whole ambition to the only day that matters for identity building.
No other researched candidate says the angle this literally: Cairn is a metaphor you must explain, Stack is a metaphor plus a saturated word.

Collision findings (all from the collision scan, fetched 2026-07-15).
Rep Today is the cleanest of the four candidates: a US App Store search for "rep today" returned no app named "Rep Today" or a close variant, and only one unrelated Health & Fitness result ([iTunes Search API, "rep today"](https://itunes.apple.com/search?term=rep+today&entity=software&country=US&limit=15)).
The "Rep" prefix is crowded with gym-logging trackers (RepCount, RepCounter Pro, etc.), but none use "Today", so the full name reads distinct ([iTunes Search API, "rep count"](https://itunes.apple.com/search?term=rep+count&entity=software&country=US&limit=10)).
The main web collision is REP Fitness, a home gym equipment retailer, not an app ([repfitness.com](https://www.repfitness.com)); it owns "REP" mindshare in fitness search but sells racks and barbells, the exact things this app exists to not need.
[ASSUMPTION] That product-category distance reduces confusion risk, but only counsel can say whether REP Fitness's marks actually pose a problem.

By contrast: Cairn has a direct same-category App Store collision ("Cairn - Hiking Safety Tracker", live in Health & Fitness) ([iTunes Search API, "cairn"](https://itunes.apple.com/search?term=cairn&entity=software&country=US&limit=15)), and Stack is saturated across categories including an exact-name game with 56k+ ratings ([iTunes Search API, "stack"](https://itunes.apple.com/search?term=stack&entity=software&country=US&limit=15)).
Neither is worth redoing the completed identifier migration for.

Domains and handles.
reptoday.app returned NXDOMAIN, a strong availability signal ([dns.google resolve](https://dns.google/resolve?name=reptoday.app&type=NS)); github.com/reptoday returned 404 ([github.com/reptoday](https://github.com/reptoday)).
reptoday.com is held by HugeDomains at $3,895 buy-now ([HugeDomains profile](https://www.hugedomains.com/domain_profile.cfm?d=reptoday.com)).
Recommended path: register reptoday.app now and launch on it; treat the .com as an optional later purchase, not a blocker.
[ASSUMPTION] A .app domain is acceptable for an iOS-only product at launch; the audience finds the app through the App Store, not through type-in traffic.

Switching cost.
The bundle id com.reptoday.app is locked and the identifier migration is done.
Every alternative name pays that cost again and, per the findings above, buys a worse collision profile.

**Caveat, stated plainly: trademark clearance and App Store name reservation are UNVERIFIED for Rep Today and for every other candidate.**
No USPTO or registry search has been performed, and App Store Connect reservation cannot be checked pre-submission ([name-collisions.md](../../01-research/name-collisions.md)).
A trademark search plus counsel review is the founder's required next step before submission, whatever name wins this tournament.

## 4. App Store listing name and subtitle

**Listing name (25/30 chars): `Rep Today: Move Every Day`**

**Subtitle (29/30 chars): `Bodyweight workouts, no setup`**

This is a deliberate change from the planned "Rep Today, Rest Tomorrow" (24 chars), and it is nearly free to make: the listing name is planned, not locked, and no App Store Connect record exists yet.
Two reasons to change it.
First, "Rest Tomorrow" is a wink that reads as "never rest", which is intensity framing and drifts toward the no-excuses register the voice rules ban; it also quietly contradicts the product's most defensible mechanic, forgiveness.
Second, it spends 13 characters on a joke; "Move Every Day" spends them stating the identity promise, and the subtitle then carries the two hardest product facts (bodyweight only, nothing to configure) in plain words.
[ASSUMPTION] Keyword value of "workouts" and "bodyweight" in the subtitle; no ASO keyword-volume data was collected in the research files I was directed to.

## 5. Hero message

**Headline (6 words):**

> Become someone who moves every day.

**Subhead (19 words):**

> Open the app and a session is already waiting. Five minutes counts. Missing a day never zeroes you out.

## 6. Messaging hierarchy

### Pillar 1: Showing up is the whole game

Claim: this app measures whether you showed up, not how hard you went.
Proof from mechanics: the Consistency Score is rolling and forgiving, not a streak; a 5-minute session counts as a full show-up; a single miss dents the score and never zeroes it.
Sample line: "A five-minute session counts in full. Showing up is the win, and the app keeps score that way."

### Pillar 2: We removed every reason not to start

Claim: there is nothing between opening the app and moving.
Proof from mechanics: the app opens to a complete, pre-generated session with one dominant Start button; it never asks "how long do you have?"; sessions generate on-device, deterministically, offline, in under 100ms; every movement needs only a floor and a wall; no account required.
Sample line: "Your session is already on screen when you open the app. One button. No questions, no equipment, no signal needed."

### Pillar 3: Missing a day is part of the plan

Claim: the app is built for the week you fall off, not just the weeks you don't.
Proof from mechanics: no streaks, XP, levels, badges, or leaderboards anywhere; a Return after a gap is served easy and winnable and is celebrated; readjustment happens over a gentle Re-entry Ramp; the Asymmetric Ramp backs off immediately when a session was too hard and climbs gradually when it was too easy.
Evidence this matters: streak loss is a documented quit event ("stopped using it entirely after that", [hn.algolia.com/api/v1/items/40903998](https://hn.algolia.com/api/v1/items/40903998)), and competitors already market against "streak anxiety", so the pain is recognized in the category ([hn.algolia.com/api/v1/search "streak anxiety"](https://hn.algolia.com/api/v1/search?query=%22streak%20anxiety%22&tags=comment)).
Sample line: "Take a week off. Your first session back is easy on purpose, and coming back is treated as a win."

### Pillar 4: Consistency earns what intensity can't

Claim: progress in this app is unlocked by showing up, and only by showing up.
Proof from mechanics: everyone starts in the Discipline Phase, where consistency is the only goal; the Strength Phase is earned through sustained consistency plus cleared movement tiers and can never be self-selected; the free tier includes unlimited workouts forever, so the core loop is never paywalled.
Sample line: "The Strength Phase is not a setting you pick. It is something you become eligible for by showing up."

## 7. Three sample headlines (ads and social)

1. "The workout is already on screen when you open the app."
2. "No streak to lose. Just a person who moves."
3. "Five minutes counts as a full show-up."

## 8. What this positioning deliberately gives up

**The optimizer market.**
People shopping for strength programming, progressive overload analytics, or coaching (Caliber, Ladder buyers) will correctly conclude this app is not for them.
The brief says so itself: not a strength program, not coaching, not a gym replacement.

**The customizer market.**
Zero-decision positioning alienates users who want to edit sessions; Freeletics reviewers already complain "there's no option to simply swap out or modify a specific exercise" ([apps.apple.com Freeletics reviews](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212)).
We are choosing the "tell me exactly what to do" buyer over the tinkerer, on purpose.

**The gamification retention hook.**
Streaks and badges retain some users; refusing them entirely means giving up a proven short-term engagement lever and betting that identity plus forgiveness retains better.
With zero users, that bet is unproven, and this pitch does not pretend otherwise.

**The free-tier wedge as a lead message.**
"Unlimited workouts free forever" is real and strong against paywalled apps, but it does not differentiate against Nike Training Club, whose free tier is genuinely loved ([apps.apple.com NTC reviews](https://apps.apple.com/us/app/nike-training-club-wellness/id301521403)).
This positioning keeps free-forever as proof inside Pillar 4, not as the headline.

**Outcome and transformation marketing.**
No calories, no weight loss, no before-and-afters, no pain claims; that entire (large, high-converting) ad vocabulary is off the table by rule, and this positioning does not try to sneak it back in as "results".

**A safety margin on "every day."**
"Move every day" sets a high bar, and if the surrounding copy ever gets lazy it could read as pressure, which is the exact failure mode of streak apps.
Every line under this positioning must carry the forgiveness clause nearby; the hero subhead does ("missing a day never zeroes you out"), and that discipline is a permanent editorial cost.
