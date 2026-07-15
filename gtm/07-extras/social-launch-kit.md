# Social Launch Kit - Rep Today (first-week drafts)

**STATUS: DRAFT ONLY. NOTHING IN THIS FILE GETS POSTED NOW.**
The product is pre-launch with zero users, zero downloads, and zero App Store presence.
Every draft below is written for future publication and must be re-checked against reality on the day it ships (status lines, links, TestFlight availability).
Every line has been written to pass the voice rules in [brand-guidelines.md](../02-brand/brand-guidelines.md) §7 and the truth policy in [product-facts-brief.md](../01-research/product-facts-brief.md): no invented numbers, users, or testimonials, and no health claims.
Channel sequencing follows [channel-plan.md](../05-thesis/channel-plan.md): App Store launch first, one quiet week, then Show HN, then Product Hunt within the month; Reddit only after rules are read manually.

---

## 1. Profile assets

### X bio

**160-char variant (157 chars):**

> Open the app. Your workout is already there. Bodyweight sessions built on your phone, offline, in under 100ms. No workout is ever paywalled. iOS, pre-launch.

**80-char variant (77 chars):**

> Open the app. Your workout is already there. Bodyweight, offline. Pre-launch.

Note: remove "pre-launch" and swap in the App Store link on launch day.

### Instagram bio

Instagram's actual limit is 150 characters, so the long variant is kept under 150, not 160.

**Long variant (142 chars):**

> A floor, a wall, and five minutes. Bodyweight sessions built on your phone, offline, in under 100ms. Free means the workouts. iOS, pre-launch.

**80-char variant (78 chars):**

> A floor, a wall, and five minutes. Bodyweight, offline, free tier. Pre-launch.

### Profile image spec (describe, do not render yet)

Per brand-guidelines.md §3 and §4.

- **Avatar (both platforms):** the app icon treatment. Moss (#2E6B4E) solid background, the Ready Mark (rounded square holding the low filled circle) in Bone (#F1EEE8). No gradients, no gloss, no figure silhouettes. At avatar sizes the mark stays legible; if the platform crops to a circle, keep the mark's 25% clear space so nothing clips.
- **X header (1500x500):** Paper (#FAF7F2) background. The hero headline "Open the app. Your workout is already there." set in the rounded system sans, Bold, Ink (#1B2228), sentence case with the period, left-aligned within the safe area. Optionally the Ready Mark small at the right edge in Moss. One accent max; no Clay needed here. No photography, no gradients, no device mockup unless it is the real, uncropped Ready Screen.
- **Instagram has no header;** the grid's first pinned post can carry the same Paper-background headline card, designed against the fixed-canvas rules in §5 (2x scale, 80px+ margins at 1080 wide).

---

## 2. Hacker News "Show HN" (launch week +1, per channel plan)

Timing per channel-plan.md: App Store launch first, one quiet week to shake out crashes, then this post, with a full day reserved for answering comments in person.

**Title (78 chars):**

> Show HN: Rep Today - iOS workouts generated on-device, offline, in under 100ms

**Body:**

> I built an iOS app that opens directly to a complete bodyweight workout with one Start button.
> No login, no onboarding quiz, no "how long do you have?" prompt.
> The session is already on screen when the app opens, and I want to talk about the design decision that makes that possible, because I think the split is the interesting part.
>
> The AI never generates a workout.
> There is an async "Programmer" that tunes a per-user session policy - progression rate, weighting across three pillars (strength, mobility, primal movement), and a variety window.
> A deterministic engine then assembles every session from a 42-movement bodyweight library, entirely on-device, offline, in under 100ms.
> The AI is never on the path between opening the app and starting.
> At MVP the Programmer is deterministic on-device heuristics too; there is exactly one optional LLM call in the entire app (a single line of variety flavor text) and it always has an offline template fallback.
>
> Why this split: open-to-start latency is the whole product.
> The target user has a 10-minute window at 9pm, and every question, spinner, or network round trip in that window loses them.
> Determinism also means the engine is testable - same inputs, same session - and the duration picker (5 to 60 minutes) is just re-running the engine with a different time budget, so changing your mind regenerates the session in under 100ms without touching anything else.
>
> One more deliberate choice: no streaks, XP, badges, or leaderboards anywhere.
> Consistency is tracked as a forgiving rolling score - a missed day dents it but never zeroes it, and coming back after a gap serves you an easy session instead of a penalty.
> I think loss-framed mechanics are why people quit fitness apps, but I have no data of my own yet to prove it.
>
> What it isn't: it is not a strength program, not coaching, and not a gym replacement.
> iOS 17+ only, no Android, no watch app, no social features.
> Works fully offline and without an account (SwiftUI, CloudKit for optional sync, HealthKit writes).
>
> I'm a solo founder. This launched [N] days ago and has essentially no users yet, so I have no retention numbers to show you - just the architecture and the reasoning.
> Free tier is unlimited workouts forever; a paid tier unlocks analytics depth, never the core loop.
> Happy to answer anything about the engine, the policy tuner, or the no-gamification bet.

Post-day edits required: replace [N] with the true number, add the App Store link, and re-verify the "no users" line against reality (if there are real installs by then, state the real number or say nothing).

---

## 3. Product Hunt draft (launch week +2 or +3, after Show HN)

**Tagline (44/60 chars):**

> Open the app. Your workout is already there.

**Description:**

> Rep Today is an iOS app for people whose workout window is 10 unpredictable minutes at 9pm.
> It opens to a complete zero-equipment bodyweight session with one Start button - no questions, no account, no internet needed.
> A deterministic engine builds every session on your phone in under 100ms, and a 5-60 minute duration chip regenerates it in one tap.
> Three pillars: bodyweight strength, mobility, and primal movement, all doable with a floor and a wall.
> No streaks, XP, badges, or leaderboards anywhere.
> Free tier is unlimited workouts forever.

**First comment from the maker:**

> Hi, solo founder here.
> I built this for the 9pm version of myself: kids down, energy gone, and every fitness app asking me to log in, answer a quiz, or browse a catalog before I could move.
> Rep Today's whole design goal is that the distance between opening the app and doing your first rep is one tap.
>
> Two choices I expect questions about.
>
> First, no streaks - by design.
> A single missed day dents a rolling Consistency Score but never resets it, and coming back after a gap gets you an easy, winnable session, not a guilt screen.
> A 5-minute session counts as a full show-up.
> I believe the fear of losing a counter is why tired people delete fitness apps, but that is a bet, not a proven result - the app is brand new and I have no retention data yet.
>
> Second, the free tier: unlimited workouts, forever, no core feature behind the paywall.
> Paid unlocks depth (deeper analytics and an earned Strength Phase), because I'd rather charge the people who want more than tax the people who just want to start.
>
> It is not a strength program, not coaching, and not a gym replacement.
> iOS only for now.
> I'd genuinely value critique - especially from anyone whose workout window looks like mine.

---

## 4. Reddit drafts

**REQUIRED MANUAL STEP BEFORE EITHER POST (from channel-plan.md, non-negotiable):**
Self-promotion rules for these subreddits could NOT be verified during research (reddit.com and all mirrors were blocked; see creator-landscape.md).
Treat both communities as no-promotion until you have manually read each sub's rules page and any pinned self-promo policy.
These drafts assume permission exists; if the rules say otherwise, adjust the post to comply or do not post at all.
Also required: 3-4 weeks of genuine participation with zero product mentions before either post goes up, per the channel plan.
A removed post or mod warning is a full stop for that community.

### 4a. r/bodyweightfitness

**Title:**

> I built a free iOS app that opens straight to a ready bodyweight session - looking for honest critique from people who actually train this way

**Body:**

> Solo dev here, long-time bodyweight-only trainee (small apartment, frequent travel, zero equipment).
> My problem was never the training, it was the starting: every app wanted an account, a quiz, or a browse session before I could move.
>
> So I built an app that opens to a complete session - strength, mobility, and primal movement from a 42-movement floor-and-wall library - with one Start button.
> Sessions run 5 to 60 minutes, generated on the phone, offline, so it works in a hotel room with no signal.
> Difficulty backs off immediately when a session was too hard and climbs slowly when it was too easy.
> No streaks or badges; consistency is a rolling score that a missed day can dent but never reset.
>
> It is not a program in the RR sense - no progression toward specific skills like planche or front lever - and I won't pretend it replaces one.
> It is for the days and weeks when following a real program isn't happening and the alternative is nothing.
>
> It just launched and has close to zero users, so I'm not here to show numbers, I'm here for critique.
> The workout tier is free, unlimited, forever - that part never changes.
> If you're willing to try the TestFlight beta and tell me where the movement selection or progression logic is wrong, the link is in my profile / first comment (per sub rules).
> Happy to answer anything about how the session generation works.

### 4b. r/fitness30plus

**Title:**

> Built an app for the 9pm-after-the-kids-are-down workout window - would love beta testers who'll tell me what's wrong with it

**Body:**

> I'm a solo developer in my [30s/40s - use real age bracket] with young kids, and my training windows are exactly what this sub describes: 9pm after bedtime, 7am in a hotel, ten minutes between calls.
> What kept killing me wasn't motivation, it was setup - by the time an app finished asking questions, the window was gone.
>
> So I built an iOS app that opens to a ready bodyweight session with one Start button.
> No equipment (floor and wall only), no account needed, works offline, 5 to 60 minutes with a one-tap duration change.
> The part I care most about for this audience: there are no streaks.
> Missing a week because life happened dents a rolling score but never zeroes it, and your first session back is deliberately easy and winnable.
> A 5-minute session counts as fully showing up.
>
> It just launched, it has close to zero users, and it is not coaching or a gym replacement - it's for the days when the alternative is nothing.
> Unlimited workouts are free forever; that's not a trial.
> I'm looking for TestFlight beta testers over 30 who will use it for a couple of weeks and tell me honestly where it fails - especially tired parents, since that's who it's built for.
> Link in first comment if the mods allow; otherwise DM me and I'll send it.

---

## 5. X/Twitter first-week sequence (7 posts)

Plain text throughout.
No emojis in any post below; none of these posts needs one, and the brand default is none.
No hashtags except where noted (posts 1 and 4 carry one each; the rest carry zero, because hashtags add noise and no reach worth having).
Post at most one per day; the sequence assumes launch day is Day 1.

**Post 1 - launch announcement (Day 1):**

> Rep Today is live on the App Store.
> Open the app and a complete bodyweight workout is already there. One Start button. No questions, no account, no internet needed.
> Built solo, launching at zero users.
> [App Store link]
>
> #buildinpublic

Note: single hashtag justified - this is genuinely a build-in-public post and that community is the realistic first audience.

**Post 2 - the one-tap demo (Day 2, video post):**

Screen-recording notes (record from a real device, not staged):
cold-open the app from the home screen, let the Ready Screen appear with the session visible, tap Start, first movement appears.
No cuts, no speed-up, real time.
If the whole clip is under 10 seconds, that is the message.
Do not overlay any numbers except what the app itself shows.

Caption:

> This is the entire flow from home screen to first rep.
> No cuts. The session was built on the phone before the screen finished appearing.

**Post 3 - no streaks, by design (Day 3):**

> Rep Today has no streaks. On purpose.
> Miss a day and your Consistency Score dips. It never resets.
> Come back after two weeks off and the app serves you an easy session and is glad you're here.
> You're someone who moves, not someone who owes.

**Post 4 - offline architecture thread-starter (Day 4):**

> How Rep Today builds a workout in under 100ms, offline:
> The AI never generates a workout. It tunes a policy - progression rate, pillar weighting, variety - asynchronously.
> A deterministic engine on your phone assembles every session from that policy.
> Nothing between open and Start ever touches a network. Thread below.
>
> #iosdev

**Mandatory first reply (posted immediately with the opener, never dropped in editing):**

> At launch the Programmer is deterministic on-device logic, not a model. Exactly one optional line of text in the app is AI-generated, and it always has an offline fallback.

Note: the opener plus its mandatory first reply ship together; continue with 1-2 further replies covering the 42-movement library and the duration-chip regeneration.
Single hashtag justified: the thread is written for iOS engineers.

**Post 5 - the free-tier promise (Day 5):**

> Free means the workouts. All of them. Forever.
> The paid tier unlocks depth - deeper analytics, an earned Strength Phase. It never gates starting a session.
> If an app makes you pay before your first rep, the paywall is just another form of friction.

**Post 6 - what it isn't (Day 6):**

> What Rep Today is not:
> Not a strength program. Not coaching. Not a gym replacement.
> No Android yet, no watch app, no social features.
> It is a ready bodyweight session in the ten minutes you actually have. That's the whole product.

**Post 7 - the duration chip (Day 7, optionally with a second short clip):**

> Got 20 minutes instead of 10? One tap.
> The new session is there before your thumb lifts, because it's rebuilt on-device in under 100ms.
> 5 to 60 minutes, and Start is never disabled while you decide.

Clip notes if recorded: show the duration chip tapped from 10 to 20, session visibly regenerating instantly; real time, no cuts.

---

## 6. Creator outreach templates

Rules for both, per channel-plan.md and creator-landscape.md: personal email, not a campaign; a working TestFlight link and one honest paragraph; the ask costs the recipient nothing; no payment stated or implied; one follow-up only, in week 3.
Do not send until TestFlight is actually live.

### 6a. GMB Fitness (Ryan Hurst / team)

**Subject:** A solo dev building for the "more important things to do" trainee - would value your critique

> Hi Ryan,
>
> I'm a solo iOS developer, pre-launch, zero users.
>
> I've built Rep Today, a micro-workout app for busy adults training in small unpredictable windows.
> It opens to a complete zero-equipment bodyweight session (strength, mobility, primal movement) with one Start button - no quiz, no account, sessions of 5 to 60 minutes built on-device and offline.
> GMB's framing of results in 15-45 minutes for people with more important things to do is the closest thing I found anywhere to who I'm building for, which is why yours is one of exactly three emails I'm sending.
>
> The ask is small: early TestFlight access is attached, and if you or anyone on the team tries it, I'd value 20 minutes of honest critique - especially on the movement selection and how difficulty adapts.
> There's no payment or promotion attached to this and I'm not asking for a mention.
> If it's not interesting, no reply needed.
>
> TestFlight: [link]
> One-paragraph technical summary: a deterministic on-device engine assembles every session in under 100ms, fully offline, from a per-user policy. At launch the policy tuner is deterministic on-device logic too, not AI; the app's only AI-generated text is one optional line with an offline fallback.
>
> Thanks for reading,
> [name]

### 6b. Hybrid Calisthenics (Hampton Liu)

Framing per creator-landscape.md: his stated stance is that nobody should have to be sold their own health, so the pitch is free-tier-only, and the ask is nothing beyond a look.

**Subject:** Built a workout app where missing a day never zeroes you out - no ask, just thought you'd want to see it

> Hi Hampton,
>
> Solo developer here, pre-launch, zero users.
> I'm not asking you to promote anything, and I know how you feel about people being sold their own health - I agree, which is why I'm writing.
>
> I built Rep Today, an iOS app that opens to a ready bodyweight session with one Start button.
> The part I think you'd care about: there are no streaks, XP, or badges anywhere.
> Missing a day dents a rolling score but never resets it, a 5-minute session counts as fully showing up, and coming back after a gap gets you an easy session and a welcome, never a penalty.
> The workout tier is free, unlimited, forever - that is permanent, not a promotion.
>
> If you're curious, early TestFlight access is here: [link].
> If you try it and something about the forgiveness design feels wrong or shame-adjacent, I would genuinely want to hear that - that's the whole email.
> No reply needed otherwise.
>
> Thanks for what you put out there,
> [name]

---

## Pre-publication checklist (applies to every draft above)

- Update every status line ("pre-launch", "zero users", "[N] days ago") to the truth on the day of posting.
- Insert real links (App Store, TestFlight) - none exist yet.
- Reddit: rules read manually, participation history established, mod permission where required.
- No draft may gain emojis, streak language, urgency mechanics, invented numbers, or health claims in editing.
- The name is "Rep Today" in prose, never "RepToday". The name has not been trademark-searched or registered; never claim or imply otherwise. Where a legal line is needed, use the canonical line from brand-guidelines.md section 2.
- Any post that says "AI" must carry the at-launch disclosure in the same post or its mandatory first reply: the Programmer is deterministic on-device logic at launch, and the app's only AI-generated text is one optional line with an offline fallback.
