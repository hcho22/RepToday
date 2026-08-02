# Pitch 1: The App Is the Disciplined One (structural discipline inversion)

Tournament v2, written blind to all other pitches and prior positioning work.
Research base: `01-research/pain-point-frequency.md`, `01-research/meta-ad-library-sweep.md`, `01-research/platform-signal-evidence.md`, `01-research/product-facts-brief.md`, `01-research/name-collisions.md`, plus the Freeletics, Sweat, and Ladder teardowns.

## 0. The lead in one breath

Every fitness app in the observed market sells the workout and outsources the discipline to you.
RepToday inverts that: the discipline lives in the product.
The session is already on screen when the app opens.
Five minutes counts as a full show-up.
Missing yesterday costs nothing.
You were never the undisciplined one; you were the one holding all the decisions.

## 1. Positioning statement

**For** busy desk-bound adults in their 30s-40s who want to move but lose the nightly fight against friction, not against laziness (the tired parent at 9pm),

**RepToday is the workout app that** carries the discipline for you: it opens straight to a ready bodyweight session generated on your phone in under 100ms, counts five minutes as a full show-up, and forgives every miss with a rolling Consistency Score instead of a streak.

**Unlike** the apps it will stand next to:

- Freeletics interrogates you before you can move (a "detailed onboarding: goals, fitness level, available equipment, days per week, and even how much time you have per session") and retains you with badges, streaks, and benchmark leaderboards (`01-research/competitor-freeletics.md`, citing the Freeletics blog and App Store listing).
- Sweat is questionnaire-first and browse-based, its program weeks start only on Mondays, and its retention layer is trophy badges and challenge pressure (`01-research/competitor-sweat.md`).
- Ladder makes you pass a team-matching quiz and a subscription before a coach-fixed 30-40 minute plan begins, with challenge and streak badges on top (`01-research/competitor-ladder.md`).
- The only discipline creative observed in the Meta Ad Library is the drill-sergeant pole: Jillian Michaels' "your no-excuses solution... All you have to do is show up" (`01-research/meta-ad-library-sweep.md`).

Every one of them asks the user to supply the consistency.

**Because** the discipline is structural, not motivational: the session exists before you decide anything (on-device, deterministic, offline, under 100ms, no account, no question before Start), the free tier is unlimited workouts forever, and there are no streaks, XP, badges, or leaderboards anywhere to lose (`01-research/product-facts-brief.md`).
The ad-library sweep found ready-on-open, friction-deletion, and forgiveness language entirely unoccupied in the observed slice, while users are explicitly asking for it: "I need the app to tell me exactly what to do" (`01-research/pain-point-frequency.md`, rank-3 pain; `01-research/meta-ad-library-sweep.md`, unoccupied-territory synthesis).

## 2. Hero message

**Headline** (6 words):

> The app is the disciplined one.

**Subhead** (24 words):

> Open it and a session is already on screen.
> Five minutes counts.
> Missing yesterday costs nothing.
> Bodyweight only, works offline, free without limits.

**Always-in-viewport proof line:**

> Open to Start: zero questions, zero setup, a full session on screen in under 100ms.

This proof line is deliberately a demo claim, not a social-proof claim, because RepToday is pre-launch with zero users and zero testimonials and the sweep's conclusion is that the substitute for a missing proof stack must be the demo itself (`01-research/meta-ad-library-sweep.md`, implications section).

## 3. The 6-second hook

Opening line of a zero-follower TikTok/Shorts video, spoken flat over a hand holding a phone:

> "The most disciplined thing I own is a workout app. Watch."

Then the screen record: thumb taps the icon, a complete session is already sitting there, thumb hits Start.
That is the whole 6 seconds.

Why this survives where "discipline" usually dies:

- The discipline is attributed to the object, not demanded of the viewer, so the drill-sergeant reading is structurally impossible in the sentence itself.
- It sets up a claim that the very next second of footage proves; the app-open-to-ready-session screen record is a format no observed competitor runs (`01-research/meta-ad-library-sweep.md`).
- It contains no shame, no "you", no instruction; a tired parent at 9pm can watch it without being accused of anything.
- It works with zero followers because it needs no authority, no physique, and no before/after; the phone is the whole cast.

Fallback variant for testing, same mechanics:

> "I stopped trying to be disciplined. I made the app hold it instead."

## 4. Messaging hierarchy

Priority order; each pillar names its product proof and one sample line that passes the voice rules.

**Pillar 1: The session is already there.**
Proof: opens to a complete pre-generated session at the learned Default Duration, one dominant Start button, never asks "how long do you have?", generated on-device deterministically in under 100ms, no account needed (`01-research/product-facts-brief.md`).
This answers the rank-3 pain in the user's own words: "I need the app to tell me exactly what to do" (`01-research/pain-point-frequency.md`).
Sample line: "You don't decide to work out. The workout is on screen, and you press Start."

**Pillar 2: Five minutes is a full show-up.**
Proof: sessions run 5-60 minutes, the duration chip is one tap and non-blocking, and a 5-minute session counts as a complete show-up in the Consistency Score (`01-research/product-facts-brief.md`).
Sample line: "It is 9:40pm and you have five minutes. That is a workout, and the app treats it like one."

**Pillar 3: Missing yesterday costs nothing.**
Proof: the Consistency Score is rolling and forgiving, not a streak; a miss dents it and never zeroes it; a return after a gap is served easy and celebrated; no XP, levels, badges, or leaderboards anywhere (`01-research/product-facts-brief.md`).
This is the rank-2 pain, the most emotionally vivid in the corpus: "That was it, back to 0, through no fault of my own" (`01-research/pain-point-frequency.md`).
Per that file's guardrail, creative presents the mechanism ("apps that punish a missed day") and never claims fitness-app users said those exact words.
Sample line: "Come back after a week away and the app hands you an easy session, not a zero."

**Pillar 4: Nothing to buy, nothing that can gate you.**
Proof: zero-equipment bodyweight only (floor and a wall, the hotel-room test), fully offline, free tier is unlimited workouts forever; premium (~$7.99/mo, ~$59.99/yr, 14-day trial) gates only depth, never the core loop (`01-research/product-facts-brief.md`).
This answers the rank-1 pain ("you cannot use this app unless you pay for it. You just can't.") as a supporting proof, and per the research guardrail it is never aimed at Nike Training Club, whose free tier is genuinely loved (`01-research/pain-point-frequency.md`).
Sample line: "A floor, a wall, and your phone. No gym, no gear, no signal, no bill."

**Pillar 5: Honest machinery.**
Proof: the AI never generates a workout; a deterministic on-device engine assembles every session, and the AI only tunes a per-user Session Policy asynchronously, off the path between opening the app and starting (`01-research/product-facts-brief.md`).
This is a trust wedge against AI-coach skepticism voiced in-category: "There is no AI or adjustments or changes...all marketing BS" (Freeletics App Store review, `01-research/competitor-freeletics.md`).
Sample line: "No AI stands between you and Start. The engine is deterministic; the tuning happens later, quietly."

## 5. What this lead deliberately gives up

- It makes no outcome promise: no physique, no strength gains, no transformation.
  Ladder's hourglass creative and Yoga-Go's "visible transformation in 28 days" own the outcome-intent buyer, and this lead concedes them entirely (`01-research/meta-ad-library-sweep.md`).
- It demotes the rank-1 pain (paywall rage) from headline to supporting proof, even though it has the most sourced mentions (`01-research/pain-point-frequency.md`).
- It buries mobility-as-relief, the most open product-differentiation territory the sweep found for regular people who do not already train; mobility appears only inside "a session," never as its own promise (`01-research/meta-ad-library-sweep.md`).
- It partially concedes control-seekers (rank-4 pain, "let me customize"): the in-session swap and duration chip exist, but a lead built on "the app decides" will actively repel some of them, and the pain-point file flags this exact tension as counter-evidence for maximal zero-decision positioning (`01-research/pain-point-frequency.md`).
- It leans on the word "discipline," which does real work only when the inversion lands; in formats where the second sentence is never read, the word alone can miscode the brand toward the pole it is refuting.
- It is demo-dependent: the hero and hook both stake everything on the open-to-session screen record, so static placements and text-only surfaces carry a weaker version of the argument.

## 6. Name stress-test (mandatory)

**Does RepToday serve this lead?**
Yes, and unusually directly.
"Rep" is the smallest unit of exercise; "Today" is the only day the app cares about.
Under the discipline inversion, the name encodes both halves of the promise: the smallest show-up counts (Pillar 2), and only today exists, so yesterday cannot be held against you (Pillar 3).
It is plain, declarative, and two syllables of concrete nouns, which matches the voice rules better than any metaphor name could.
Collision posture from `01-research/name-collisions.md`: cleanest of the candidates; no "Rep Today" or close variant in US App Store search; reptoday.app returned NXDOMAIN (strong but not conclusive availability signal); github.com/reptoday 404; the main web collision is REP Fitness, an equipment retailer, not an app.
Known frictions, stated honestly: the "Rep" prefix is crowded with gym-logging trackers (RepCount, RepCounter Pro, etc.), so the bare name can misread as a rep counter until the subtitle corrects it, and "rep" is strength-coded, which slightly undersells the mobility co-primary pillar.
Both frictions are subtitle-fixable and neither fights the lead itself.

**The alternates under this lead:**

- Cairn: the trail-marker metaphor gestures at quiet consistency, but it does zero work for the inversion, requires explanation a 6-second hook cannot afford, and has a live same-category collision ("Cairn - Hiking Safety Tracker", Health & Fitness) (`01-research/name-collisions.md`).
- Stack: "stacking days" is streak semantics wearing a different shirt; a stack is a thing that topples, which is exactly the mental model the forgiveness pillar exists to kill, and the name is saturated across categories (exact-name Ketchapp game with 56K+ ratings, Stack Team App, Stack Sports) (`01-research/name-collisions.md`).
  Under this lead specifically, Stack is not merely weaker; it is counter-positioned.

**One flag on the listing name, not the app name:**
The draft listing name "Rep Today, Rest Tomorrow" fights this lead.
"Rest Tomorrow" reads as rest deferred, a faint hustle-culture echo, and it implies a day-on/day-off contract the forgiving Consistency Score explicitly does not enforce.
Since the app is unsubmitted, changing the listing suffix is free; recommend a subtitle that does the disambiguation work the "Rep" prefix needs, in the spirit of "Rep Today: The Ready Workout" [ASSUMPTION: exact subtitle wording untested; App Store subtitle rules and character limits to be checked at submission].

**Verdict: confirm RepToday.**
No challenger proposed; under this lead the incumbent is not merely adequate, it is load-bearing, and both live alternates are worse for reasons the lead itself supplies.
Formal trademark and App Store name clearance remain UNVERIFIED for every candidate and are the founder's next action (`01-research/name-collisions.md`).

## 7. Risks of this lead, stated plainly

- **Semantic capture.** "Discipline" is owned in-market by the drill-sergeant register (Jillian Michaels' "no-excuses" is the only observed discipline creative, `01-research/meta-ad-library-sweep.md`).
  In any surface where the inversion gets truncated to the single word, the brand can be miscoded as the thing it opposes.
  Mitigation is mechanical: no discipline-adjacent line ships without the inversion in the same breath.
- **Overpromise risk.** "The app supplies the discipline" can be heard as "the app will make you work out," which no app can honestly claim; the app deletes decisions, it does not press Start.
  Copy must always claim the friction removal, never the behavioral outcome.
- **Thin direct evidence.** Decision fatigue is the rank-3 pain with 4 sourced mentions, small-N by the research's own admission, and the "unoccupied territory" finding is bounded to one logged-out Meta keyword sweep that cannot see dark posts or TikTok creative (`01-research/pain-point-frequency.md`, `01-research/meta-ad-library-sweep.md`).
  Someone may already own this angle on the platforms where we will actually test.
- **Copyable message, defensible mechanism.** Peloton already runs "Less time choosing classes, more time moving" (`01-research/meta-ad-library-sweep.md`).
  A large player can adopt the friction story overnight; the durable defense is the structural demo (ready session in under 100ms, offline, no hardware, no quiz), so creative must keep the mechanism visible, not just the slogan.
- **Concept-ad fragility at zero followers.** The lead asks a cold viewer to accept an inversion of a familiar word in 6 seconds; if the screen record does not immediately land, there is no proof stack (zero users, zero ratings) to catch the skeptic.
  The platform evidence says TikTok and Shorts judge the content itself rather than the account (`01-research/platform-signal-evidence.md`), which makes this testable fast, but a null result must be read as "this framing," not "this product."
- **Audience self-selection skew.** People who search for or resonate with "discipline" may skew toward the intensity-seeking segment this product deliberately does not serve, inflating installs that churn.
  [ASSUMPTION] The hook's tired-flat register will pre-filter most of that segment; this is an inference, not a tested result.
