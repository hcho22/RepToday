# Pitch 4: Audience-First - "A floor, a wall, and the minutes you actually have"

Angle: start from the person, not the product.
The person is a tired adult with 5 to 20 minutes, no equipment, and no decision-making energy left.
Everything below is built on their three real constraints - time, space, energy - and the one promise the product can actually keep: a floor and a wall is enough.

## 1. Positioning statement

For desk-bound adults and traveling parents who have 5 to 20 minutes, no equipment, and no energy left to plan, Rep Today is the workout app that opens to a ready session you can start with one tap.
Unlike class catalogs and AI coaches that ask questions, stream video, and gate the core product behind a subscription, Rep Today never asks "how long do you have?" before Start, never needs the internet, and never charges for workouts.
That promise holds because every one of its 42 movements works with a floor and a wall, sessions are generated on-device in under 100ms, the free tier includes unlimited workouts forever, and consistency is scored with a forgiving rolling measure where a 5-minute session counts as a full show-up.

## 2. ICP: "Dana at 9:15pm"

Dana is 38, a product manager, two kids, married, suburban, iPhone.
[ASSUMPTION] The name, job, and family shape are a composite persona; the product has zero users, so no real customer exists yet.

**When Dana uses it.**
At 9:15pm on a Tuesday, kids finally down, sitting on the living room floor in work clothes with maybe 15 minutes of usable energy left.
At 6:40am in a Courtyard Marriott before a client day, with a carpeted patch between the bed and the desk.
At 12:40pm in a home office between calls, needing the hips and back to stop complaining, not a training block.

**Dana's constraints, in order.**
Energy: by evening there is nothing left for deciding, browsing, or configuring.
Time: the window is 5 to 20 minutes and it closes without warning.
Space and gear: no home gym, no bands in the suitcase, just a floor and a wall.

**What Dana has tried.**
A gym membership that lapsed because the round trip cost more time than the workout. [ASSUMPTION]
Browse-and-choose class apps, where picking a class at 9pm is itself a task; this decision fatigue is documented demand ("I need an app that requires little decision-making ... Tell me exactly what to do", [hn.algolia.com/api/v1/items/36666806](https://hn.algolia.com/api/v1/items/36666806)) and an in-category complaint ("excessive scrolling, multiple clicks to get to something", [Centr App Store reviews](https://apps.apple.com/us/app/centr-strength-fitness-app/id1382530817)).
A streak-based habit app, abandoned after one broken streak; the mechanism is documented ("That was it, back to 0 ... just stopped using it entirely after that", [hn.algolia.com/api/v1/items/40903998](https://hn.algolia.com/api/v1/items/40903998)). [ASSUMPTION that Dana specifically experienced this]
A "home workout" program that eventually asked for equipment ("Sometimes they used large gym equipment not typical for a home", [Centr App Store reviews](https://apps.apple.com/us/app/centr-strength-fitness-app/id1382530817)).

**What Dana is not.**
Not a gym rat, not chasing a physique deadline, not willing to be shamed.
Dana wants to be someone who moves, on the days as they actually are.

## 3. Name recommendation: keep Rep Today

**Back the incumbent.**
Rep Today is the right name for this audience, and the collision scan supports it.

**Positioning fit.**
"Today" is exactly the unit of commitment this audience can afford: not a program, not a transformation, one rep today.
"Rep" is plain, physical, and identity-framed; the name is a quiet instruction that matches the product's discipline-first mechanic, where a 5-minute session counts as a full show-up.
Neither word is hype, which matches the voice rules.

**Collision findings** (from [name-collisions.md](../../01-research/name-collisions.md), all fetched 2026-07-15).
No app named "Rep Today" or a close variant surfaced in a US App Store search; the "Rep" prefix is crowded with gym-logging trackers (RepCount, RepCounter Pro), but none use "Today," so the full name reads distinct ([iTunes Search API, "rep today"](https://itunes.apple.com/search?term=rep+today&entity=software&country=US&limit=15)).
reptoday.app returned NXDOMAIN, a strong availability signal; github.com/reptoday returned 404 ([dns.google](https://dns.google/resolve?name=reptoday.app&type=NS), [github.com/reptoday](https://github.com/reptoday)).
reptoday.com is held by HugeDomains at $3,895 buy-now ([HugeDomains](https://www.hugedomains.com/domain_profile.cfm?d=reptoday.com)); recommendation: launch on reptoday.app and treat the .com as an optional later purchase, not a blocker.
Known risk: REP Fitness (repfitness.com) owns "REP" mindshare in fitness web search, but it sells racks and benches, not apps ([repfitness.com](https://www.repfitness.com)).

**Why not the alternatives.**
Cairn has a direct same-category App Store collision ("Cairn - Hiking Safety Tracker", Health & Fitness) and a taken GitHub org; disqualifying for a Health & Fitness launch.
Stack is saturated (exact-name Ketchapp game with 56k+ ratings, Stack Team App in Sports, Stack Sports in web search); findability would be poor from day one.
A brand-new name would restart the completed com.reptoday.app identifier migration for no offsetting gain; nothing in the research suggests a stronger unclaimed direction.

**Mandatory caveat.**
Trademark and App Store name clearance are UNVERIFIED for Rep Today and every other candidate.
A USPTO search (ideally with counsel) and an App Store Connect name reservation must happen before submission.

## 4. App Store listing name and subtitle

**Listing name (30 chars): `Rep Today: 5-Min Home Workouts`** (exactly 30 characters).
This replaces the planned "Rep Today, Rest Tomorrow."
Reasoning: the rhyme spends 14 characters on a phrase that carries no search keywords, and "Rest Tomorrow" can be misread as the app prescribing rest days, which cuts against the show-up-today identity.
"5-Min Home Workouts" states the audience's two constraints (time, place) in the searchable words they actually type, and 5 minutes is a real session option that the product treats as a full show-up.

**Subtitle (30 chars): `No equipment. Opens ready.`** (26 characters).
Both claims are product facts: bodyweight-only 42-movement library, and the app opens to a pre-generated session with one Start button.

## 5. Hero message

**Headline (7 words):**
A floor, a wall, and five minutes.

**Subhead (22 words):**
Open the app and a session is already on screen.
Bodyweight only, 5 to 60 minutes, works offline.
You're someone who moves.

## 6. Messaging hierarchy

### Pillar 1: It opens ready

**Claim:** you make zero decisions between opening the app and starting.
**Proof from mechanics:** the app opens to a complete, pre-generated session at your learned Default Duration with one dominant Start button; it never asks "how long do you have?"; changing duration is a one-tap chip that regenerates the session in under 100ms; the AI is never on the path between open and Start.
**Evidence the pain is real:** "I need an app that requires little decision-making ... Tell me exactly what to do" ([hn.algolia.com/api/v1/items/36666806](https://hn.algolia.com/api/v1/items/36666806)); "excessive scrolling, multiple clicks to get to something" ([Centr reviews](https://apps.apple.com/us/app/centr-strength-fitness-app/id1382530817)).
**Sample line:** The workout is on screen before you have to think.

### Pillar 2: A floor and a wall is enough

**Claim:** every session works in a hotel room, a living room, or an office, with nothing to buy and no signal required.
**Proof from mechanics:** all 42 movements are bodyweight-only and pass the "floor and a wall" test; sessions are generated on-device, deterministically, fully offline; no account is required.
**Evidence the pain is real:** "Sometimes they used large gym equipment not typical for a home" ([Centr reviews](https://apps.apple.com/us/app/centr-strength-fitness-app/id1382530817)); the same buyer asking for zero-decision workouts also required offline functionality ([hn.algolia.com/api/v1/items/36666806](https://hn.algolia.com/api/v1/items/36666806)).
**Sample line:** Every movement passes the hotel room test.

### Pillar 3: Showing up counts, even the small days

**Claim:** consistency is measured in a way a real life can survive.
**Proof from mechanics:** the Consistency Score is rolling and forgiving, not a streak; a 5-minute session counts as a full show-up; one miss dents the score but never zeroes it; a return after a gap is served easy and winnable and is celebrated, with a gentle Re-entry Ramp afterward; difficulty backs off immediately when a session was too hard.
**Evidence the pain is real:** "Then after 200 days, I lost my streak and ... breathed a sigh of relief" ([hn.algolia.com/api/v1/items/38919053](https://hn.algolia.com/api/v1/items/38919053)); "back to 0 ... just stopped using it entirely after that" ([hn.algolia.com/api/v1/items/40903998](https://hn.algolia.com/api/v1/items/40903998)).
Honest note: the most vivid streak-loss quotes are from Duolingo and habit apps, not fitness apps, so this pillar leads with the mechanic, not the complaint.
**Sample line:** Miss a day and the score bends. It never breaks.

### Pillar 4: The workouts are free, full stop

**Claim:** unlimited workouts on the free tier, forever; the paywall never gates the core loop.
**Proof from mechanics:** free tier is unlimited workouts; premium (~$7.99/mo or ~$59.99/yr, 14-day trial) unlocks depth like deeper analytics and the Strength Phase, never the session itself.
**Evidence the pain is real:** "you cannot use this app unless you pay for it. You just can't" ([30 Day Fitness reviews](https://apps.apple.com/us/app/30-day-fitness-workout-at-home/id1099771240)); "the app won't do anything until you sign up for the free trial" ([hn.algolia.com/api/v1/items/39991813](https://hn.algolia.com/api/v1/items/39991813)).
Honest note: this wedge works against paywalled apps, not against Nike Training Club, whose free tier is genuinely praised ([NTC reviews](https://apps.apple.com/us/app/nike-training-club-wellness/id301521403)); keep this pillar supporting, not leading.
**Sample line:** The free tier is unlimited workouts. That is the tier.

## 7. Three sample headlines (ads/social)

1. 9pm, kids down, ten minutes left in you. That counts here.
2. The hotel room is the gym. Floor, wall, done.
3. No questions before Start. The session is already built.

## 8. What this positioning deliberately gives up

**The optimization crowd.**
Serious lifters, program followers, and people chasing measurable strength numbers will read "a floor and a wall" as not-for-me, and they will be right; the product says itself it is not a strength program, not coaching, and not a gym replacement.

**Users who want control.**
Zero-decision positioning will repel people who want to edit sessions; Freeletics reviewers already complain about exactly this ("there's no option to simply swap out or modify a specific exercise", [Freeletics reviews](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212)).
We accept losing them rather than diluting the it-opens-ready promise.

**The AI marketing wave.**
The honest architecture (AI tunes policy asynchronously, a deterministic engine builds every session) means we cannot and do not ride "AI coach" hype; competitors with looser standards will out-shout us on that keyword.

**Social proof and community energy.**
Zero users means zero testimonials, and the product has no social features; this positioning leans entirely on specific, checkable mechanics instead of numbers or crowds, which is slower but is the only honest option.

**The founder's rhyme.**
Dropping "Rest Tomorrow" from the listing name gives up a memorable tagline in exchange for search keywords and message discipline; the rhyme can live on as an occasional social line, not the store identity.

**Aggressive daily framing.**
"Rep Today" flirts with daily-streak connotations; the copy must keep countering that with the forgiving-score message, which costs us some punchier absolutist lines.

**Offline as a lead claim.**
Offline-by-design is real, but the evidence for connectivity complaints is the weakest research theme, so it stays a supporting detail inside Pillar 2 rather than a headline.
