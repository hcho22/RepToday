# Instagram carousels: behavioral claim verification

Every behavioral claim across every slide HTML file and every `caption.md` file, checked against the shipped iOS source.

## Why this file exists

The carousel copy was written from `../02-brand/positioning.md` and the brand lines rather than against the app.
Four consecutive review rounds each surfaced more false or imprecise behavioral claims, four of them on a single sentence, so the captain commissioned one bounded exhaustive pass instead of a fifth round of spot fixes.
Each earlier defect was true-sounding, written in good faith, and wrong: "no quiz, no sign-up" against a six-step onboarding questionnaire, an Apple Health toggle that does not exist, "not on the home screen, not in the history" against a `Best run` line that renders on both.

Every claim below was judged against **what a brand-new install actually experiences**, not against what the brand documents assert.
A claim that could not be settled from code is recorded as a finding, not waved through as a pass.

## How to read the verdicts

| Verdict | Meaning |
|---|---|
| **true** | The code settles it in the copy's favour, at the cited lines. |
| **fixed** | Was false or imprecise. The copy in this commit is the corrected version; the old text is quoted in the findings section. |
| **true (caveat)** | True as written, with a non-obvious edge recorded so a future reviewer does not rediscover it as a defect and "correct" a correct line. |
| **not code-checkable** | A framing, register, or intent claim with no mechanic behind it. Not a defect; simply outside what source can settle. |

Code paths are relative to `ios/RepToday/RepToday/`.
Line numbers are as of this commit.

Every score figure quoted below was produced by **executing** the shipped `ConsistencyScore.evaluate` against synthetic histories in the Simulator, not by reading the arithmetic off the source.
The scoring claims are the ones four earlier rounds kept getting subtly wrong, so they were measured rather than reasoned about.
The probe was a throwaway and is not committed; it drove `evaluate(logs:weeklyGoal:asOf:calendar:)` directly with `weeklyGoal: 3` and a fixed `asOf`, which is enough to reproduce every number here.

It was checked for non-vacuity rather than trusted, in the same spirit as the sabotage checks the README records against the guards that carry one.
An early run passed while silently executing nothing, because the probe file had been recreated after `xcodegen generate` last ran and so was not in the project, which made `-only-testing` match no tests and report success over zero assertions.
The figures below come from a run that regenerated the project first and carried one deliberately wrong expected value: the wrong one failed with the actual number attached and every real one passed, so the run is known to have executed.

## Scope note on captions and alt text

Each `caption.md` restates its slides and then quotes every slide verbatim as alt text.
That correspondence is a **committed, re-runnable guard** rather than a one-off check: `alt-text-check.py` compares every copy-bearing slide element against its own slide's alt-text paragraph and fails on any word that has drifted, so a slide row below covers its caption and alt-text restatements too.
It reports the number it compared on each run rather than pinning it here, and it reads which elements carry copy out of `carousel.css` rather than from a list, so a text style added later is covered by construction.
It is wired into `render.sh` beside the other three and is sabotage-checked in every direction the README enumerates.
Earlier revisions of this document asserted the property from a script that was run once by hand and not committed, which left the folder's most drift-prone correspondence resting on trust in a folder whose whole standard is guards rather than trust.
The single intentional divergence is `carousel-1` slide 6, where the slide's `What "no deciding" means here, exactly.` is nested inside a double-quoted alt-text string and so uses single quotes there; the guard unifies quote glyphs for exactly this reason and relaxes nothing else.
Caption-only claims (sentences with no slide counterpart) are listed separately per carousel.

---

## Carousel 1: "You do not pick a workout."

| # | Claim | Slide | Code | Verdict |
|---|---|---|---|---|
| 1.1 | "You do not pick a workout." | `slide-01.html:20` | `ViewModels/OnboardingViewModel.swift:29-38` (the six onboarding steps, none of them a workout choice), `Views/Ready/ReadyView.swift:188-206` | true |
| 1.2 | "The session is chosen for you." | `slide-02.html:16` | `ViewModels/ReadyViewModel.swift:183`, `:407-415` | true |
| 1.3 | "A complete bodyweight session, assembled on your phone" | `slide-02.html:17` | `Services/Mock/MockServices.swift:28-50`, `Services/Mock/MockExerciseService.swift:143-145` | true |
| 1.4 | "sized to the time you have, from 5 minutes up to 60." | `slide-02.html:17` | `Services/Programmer/DefaultDurationLearning.swift:37` (`chipValues = [5, 10, 15, 20, 30, 45, 60]`), consumed verbatim at `ViewModels/ReadyViewModel.swift:59` and `Views/Onboarding/OnboardingView.swift:653` | **fixed** (was F16) |
| 1.5 | "One Start button, nothing to browse." | `slide-02.html:17` | `Views/Ready/ReadyView.swift:188-206` (one Start, never disabled); no catalog surface exists | true (caveat: see F8) |
| 1.6 | "Wanting to move is not the hard part." plus the stack-of-choices copy | `slide-03.html:16-18` | none | not code-checkable (thesis, not a mechanic) |
| 1.7 | "So the deciding happens before you arrive." | `slide-04.html:16` | `ViewModels/ReadyViewModel.swift:183` (generate runs inside `load()`, before render) | true |
| 1.8 | "Rep Today assembles the whole session on the phone, then opens to it." | `slide-04.html:17` | `ViewModels/ReadyViewModel.swift:407-415`; `Views/Ready/ReadyView.swift:60-66` renders only once `workout != nil` | true |
| 1.9 | "Not a faster menu. No menu." | `slide-04.html:17` | No catalog, picker, or session editor exists in `Views/` | true |
| 1.10 | Diagram: the whole path is Open, then Start | `slide-05.html:19,24` | `Views/Ready/ReadyView.swift:189-196` (Start hands over the already-built object) | true (caveat: see F8) |
| 1.11 | "Setup asks about you once, on the first open" | `slide-05.html:27`, `slide-06.html:17` | `ViewModels/OnboardingViewModel.swift:29-38`; `Utilities/AppState.swift:38-42`; `Views/RootView.swift:13-22` | true (caveat: see F5) |
| 1.12 | "iOS asks once about Health" | `slide-05.html:27`, `slide-06.html:18` | `Views/RootView.swift:88-90` (unconditional `.task` on `MainTabsView`) | true |
| 1.13 | "After that, nothing stands between these two." | `slide-05.html:27` | `Views/Ready/ReadyView.swift:188-206`; paywall's sole call site is `Views/Progress/ProgressTabView.swift:63-72` | true (caveat: see F6) |
| 1.14 | "No account to make, no subscription sheet." | `slide-05.html:27` | `Views/Onboarding/OnboardingView.swift:238-250`; `ViewModels/OnboardingViewModel.swift:286-292` (local UUID fallback) | true |
| 1.15 | "A few things, including your body basics, how fit you are now, and how long you usually have." | `slide-06.html:17` | `Views/Onboarding/OnboardingView.swift:266-320` (name, sex, age, height, weight), `:565` ("How active are you?"), `:658` ("How long do you usually have?") | true |
| 1.16 | "It never asks you to choose a workout, and it does not come back." | `slide-06.html:17` | `ViewModels/OnboardingViewModel.swift:29-38`; `Utilities/AppState.swift:38-42` | true (caveat: see F5) |
| 1.17 | "iOS asks once ... for permission to write your sessions to Apple Health." | `slide-06.html:18` | `Services/Health/HealthKitService.swift:32-34,48` (share types only, read set empty); `Info.plist:35-36` declares only `NSHealthUpdateUsageDescription` | true |
| 1.18 | "Decline it and everything works the same." | `slide-06.html:18` | `Services/Health/HealthKitService.swift:59-61` (guard returns); `Services/ActiveSession/SessionCompletionService.swift:158-161` (`try?`, step 7 of 8, after all durable bookkeeping) | true |
| 1.19 | "the path from opening the app to starting a session asks nothing. No sign-up, no paywall." | `slide-06.html:18` | as 1.13 and 1.14 | true (caveat: see F6) |
| 1.20 | "Bodyweight only, so it needs no equipment." | `slide-07.html:16` | `Resources/Exercises.json` (71 entries, every `equipment: []`); enforced `Services/Mock/MockExerciseService.swift:143-145` | true |
| 1.21 | "Built on the phone, so it needs no signal." | `slide-07.html:16` | `Services/Mock/MockServices.swift:28-50`; engine files import Foundation only; library decoded from the app bundle at `Services/Mock/MockExerciseService.swift:86-97` | true (caveat: see F9) |

Caption-only claims: none. Every caption sentence restates a slide claim above.

---

## Carousel 2: "Why I built this."

| # | Claim | Slide | Code | Verdict |
|---|---|---|---|---|
| 2.1 | Founder origin narrative (slides 1 to 4) | `slide-01.html:20`, `slide-02.html:16-17`, `slide-03.html:16-17`, `slide-04.html:16-18` | none | not code-checkable (first-person account) |
| 2.2 | "An engine on the phone assembles the whole session, offline" | `slide-05.html:17` | `Services/Mock/MockServices.swift:28-50`; `Services/Engine/*` import Foundation only | true |
| 2.3 | "and the app opens straight to it" | `slide-05.html:17` | `ViewModels/ReadyViewModel.swift:183`, `:407-415` | true |
| 2.4 | "It does not ask what you want." | `slide-05.html:17` | No picker on the path; `Views/Ready/ReadyView.swift:188-206` | true |
| 2.5 | "if it chose wrong for you, one tap mid-session swaps that movement for a similar one" | `slide-05.html:18` | `Views/ActiveSession/ActiveSessionView.swift:411-419`; `ViewModels/ActiveSessionViewModel.swift:684-686`, `:702-778`; `Services/Engine/ExerciseSwap.swift:138,151,156` | **fixed** (was F1) |
| 2.6 | "It is not a strength program. It is not coaching." | `slide-06.html:17` | No program, plan, schedule, or coaching surface exists in `Views/`; grep for a user-facing "program" string returns nothing | true (caveat: see F10) |
| 2.7 | "It is not a replacement for a gym, and it is not trying to be one." | `slide-06.html:17` | Consistent with the MVP non-goals in the repo-root `AGENTS.md` | not code-checkable (positioning) |
| 2.8 | "I wanted one that did the deciding for me. So that is the one I built." | `slide-07.html:15` | none | not code-checkable (first-person) |

Caption-only claims: none.

---

## Carousel 3: "You have ten minutes and no plan."

| # | Claim | Slide | Code | Verdict |
|---|---|---|---|---|
| 3.1 | The three time windows (9pm, 7am, between calls) | `slide-02.html:17-19` | none | not code-checkable (audience recognition) |
| 3.2 | "You never lacked the will. You lacked a session you did not have to plan." | `slide-03.html:16` | none | not code-checkable (framing) |
| 3.3 | "One session, sized to the time you actually have, already built by the time you get there." | `slide-04.html:17` | `ViewModels/ReadyViewModel.swift:183`, `:407-415` | true |
| 3.4 | "If the length is wrong, one tap changes it, from 5 minutes up to 60." | `slide-04.html:18` | `Views/Ready/ReadyView.swift:170-183` (one tap, no confirm step); `ViewModels/ReadyViewModel.swift:270-286` (regenerates in place); `Services/Programmer/DefaultDurationLearning.swift:37` | **fixed** (was F7) |
| 3.5 | "That is a calendar, not a character flaw." | `slide-05.html:16` | none | not code-checkable (framing) |
| 3.6 | "A patch of floor, a wall, no equipment, no signal required." | `slide-05.html:17` | `Models/Enums.swift:86-90` (Zero-Equipment Floor is "a floor and a wall"); `Models/Exercise.swift:73` (`apartmentFriendly`) | **fixed** (was F2) |
| 3.7 | "You want a catalog to browse." (listed as *not* for you) | `slide-06.html:17` | No catalog surface exists; `exerciseService.exercises()` has one UI consumer, `ViewModels/ProgressViewModel.swift:115` | true |
| 3.8 | "You want to build and edit your own sessions." (listed as *not* for you) | `slide-06.html:18` | No create, edit, or save surface anywhere in `Views/`; the only content levers are the duration chip and the in-session swap and skip | true |
| 3.9 | "You want a coach, a strength program, or a gym replacement." (listed as *not* for you) | `slide-06.html:19` | as 2.6 | true |
| 3.10 | "Bodyweight. Offline. 5 to 60 minutes. Nothing to plan." | `slide-07.html:16` | as 1.20, 1.21, 1.4 | true |

Caption-only claims: none. Both corrected sentences were mirrored into the caption body and the slide alt text in the same commit.

---

## Carousel 4: "There is nothing here to lose."

Carousel-4 slide 2 and slide 5 are captain-signed-off wording.
Both were still verified rather than assumed, per the sign-off's own "unless your verification finds them factually wrong" clause.
Neither is factually wrong, so neither was touched.

| # | Claim | Slide | Code | Verdict |
|---|---|---|---|---|
| 4.1 | "A streak you can break / Badges / XP and levels / Leaderboards" under "None of this exists in the app" | `slide-02.html:17-20` | Exhaustive grep over `ios/`: `leaderboard`, `trophy`, `medal`, gamification `level` and `rank` all return zero hits; every `streak`, `XP`, and `badge` hit is a doc comment asserting absence, a test name, or the StoreKit intro-offer badge at `Models/SubscriptionPlan.swift:40` | true |
| 4.2 | "Not on the home screen, not in the history, not anywhere." | `slide-02.html:22` | as 4.1 | true |
| 4.3 | "The one run the app shows you is your longest ever, and that number only counts up." | `slide-02.html:22` | `Services/Consistency/ConsistencyScore.swift:174-194` (historical maximum over all history); rendered `Views/Ready/ReadyView.swift:365` and `Views/Progress/ProgressTabView.swift:210`; full-history reads at `ViewModels/ReadyViewModel.swift:214` and `ViewModels/ProgressViewModel.swift:99` | true (caveat: see F4) |
| 4.4 | "Rep Today keeps a Consistency Score: a rolling average of showing up, not a count of days in a row." | `slide-03.html:17` | `Services/Consistency/ConsistencyScore.swift:102-140`, `:164-166` (linear recency weight), `:45` (8-week window) | true |
| 4.5 | "A short week moves the number. It cannot empty it." | `slide-04.html:16` | Worst single short week is 100 to 85.2; worst single empty week is 100 to 77.8, never 0 (`ConsistencyScore.swift:114`, `:130`, `:164-166`) | true (caveats: see F11 and F15) |
| 4.6 | "Nothing in the score is measured in days, so there is no day to miss." | `slide-04.html:17` | `Services/Consistency/ConsistencyScore.swift:81` (bucketed by `weeksAgo`), `:130` (adherence from the weekly count only), `:204-212` (week math) | **fixed** (was F3) |
| 4.7 | "It averages your recent weeks" | `slide-04.html:17` | `Services/Consistency/ConsistencyScore.swift:102-140` | **fixed** (was F3) |
| 4.8 | "a week that falls short dents it, the dent shrinks with every week after, and after eight it is gone entirely" | `slide-04.html:17` | `Services/Consistency/ConsistencyScore.swift:164-166` (weight falls linearly), `:45` and `:110` (weeks 8 or more ago are outside the window) | **fixed** (was F3) |
| 4.9 | "The shortest session is a full show-up." | `slide-05.html:16` | `Services/Consistency/ConsistencyScore.swift:83` (any log counts as one workout, duration never read), `:10-12`; `Views/Ready/ReadyView.swift:362` renders "Every time you show up counts - even five minutes." | true |
| 4.10 | "The short session you had time for counts exactly the same as the long one you did not." | `slide-05.html:17` | as 4.9 | true |
| 4.11 | "Sessions run anywhere from 5 to 60 minutes." | `slide-05.html:17` | `Services/Programmer/DefaultDurationLearning.swift:37` (the chip vocabulary the user actually touches, spanning 5 to 60); `Services/Engine/SessionShapeSelection.swift:45` corroborates that the engine accepts the whole span | true (caveat: see F16) |
| 4.12 | "Coming back is the event, not the failure." | `slide-06.html:16` | Supported by 4.13 and 4.14 below | true |
| 4.13 | "Come back after a week away and the session waiting is deliberately gentler." | `slide-06.html:17` | `Services/Engine/ReturnOverride.swift:38` (7 calendar days), `:64-68`, `:53` and `:94-98` (difficulty capped at 2), `:48` and `:110-111` (volume scaled to 0.7) | **fixed** (was F12) |
| 4.14 | "The weeks you were away are excused from the score, and the session you came back with counts as a full week." | `slide-06.html:17` | `Services/Consistency/ConsistencyScore.swift:121-123` and `:148-159` (gap weeks excused), `:125-128` (the return week scores a full 1.0), `:84` (`wasReturn` stamped from the log) | **fixed** (was F12) |
| 4.15 | "You're someone who moves." | `slide-07.html:15` | `Views/Ready/ReadyView.swift:331` renders this exact line in-product | true |
| 4.16 | "The score's job is to reflect that, not to threaten it." | `slide-07.html:16` | none | not code-checkable (intent; see F11 for the tension) |

Caption-only claims: none.

---

## Carousel 5: "A floor and a wall."

| # | Claim | Slide | Code | Verdict |
|---|---|---|---|---|
| 5.1 | "A floor and a wall." as the whole equipment list | `slide-01.html:20`, `slide-02.html:16` | `Models/Enums.swift:86-90`: "the Zero-Equipment Floor guarantees each session is completable with only a floor and a wall"; `Models/Exercise.swift:73` defines `apartmentFriendly` the same way and all 71 entries carry it | true (caveat: see F13) |
| 5.2 | "Every movement in Rep Today is bodyweight." | `slide-02.html:17` | `Resources/Exercises.json`: 71 entries, zero with a non-empty `equipment`; enforced at load by `Services/Mock/MockExerciseService.swift:143-145` (a violating library is a hard launch failure, not a silent degrade) | true |
| 5.3 | "There is no version of a session that needs a band, a bar, or a bench." | `slide-02.html:17` | as 5.2, plus the runtime filter `Services/Engine/ExercisePoolFilter.swift:151-153`, which `Services/Engine/ExerciseSwap.swift:151` also draws through | true |
| 5.4 | "Nothing sneaks in later. No bands in week three. No pull-up bar in month two." | `slide-03.html:16-17` | The bodyweight filter is unconditional: no phase, difficulty tier, or progression chain relaxes it (`ExercisePoolFilter.swift:151-153`) | true |
| 5.5 | "Bodyweight is the boundary the app is built inside, not the beginner setting you graduate out of." | `slide-03.html:17` | as 5.4 | true |
| 5.6 | "The session is not fetched from anywhere. It is built on the phone, by the phone, every single time." | `slide-04.html:17` | `Services/Mock/MockServices.swift:28-50`; every file under `Services/Engine/`, `Services/Programmer/`, `Services/Consistency/` imports Foundation only | true |
| 5.7 | Hotel-room test: airplane mode, hotel room, a basement with no bars, "The session still builds." | `slide-05.html:17-21` | as 5.6; the exercise library is decoded from the app bundle at `Services/Mock/MockExerciseService.swift:86-97`, never fetched | true |
| 5.8 | "A workout that needs equipment has already chosen where you will be. One that needs a server has already chosen when." | `slide-06.html:16` | Describes mechanisms, names no company and claims no motive | not code-checkable (argument) |
| 5.9 | "This one chooses neither." | `slide-06.html:17` | as 5.2 and 5.6 | true |
| 5.10 | "Bodyweight. Offline. 5 to 60 minutes." | `slide-07.html:16` | as 5.2, 5.6, 4.11 | true |

Caption-only claims: none.

---

## Carousel 6: "The workout is the free part."

Positioning pillar 2 (free means the workouts, forever; premium gates only depth).
Written from code, not from the pillar: pillar 2 also lists premium as gating "the earned Strength Phase", which the code does not support and this carousel does not claim (see the note under the table, and F18).

| # | Claim | Slide | Code | Verdict |
|---|---|---|---|---|
| 6.1 | "The workout is the free part." | `slide-01.html:20` | Settled by 6.2, 6.6, 6.7 (the whole loop is free; only the deeper analytics view is paid) | true |
| 6.2 | "Every session. Unlimited." plus "The complete session Rep Today opens to is free, every time, with no limit on how many you generate." | `slide-02.html:16-17` | `Services/Subscription/StoreKitSubscriptionService.swift:10-11` ("Never gates the loop. Premium only unlocks the depth layer (US-M02). Free is unlimited core workouts forever"); `Services/Subscription/StoreKitFacade.swift:3-4` ("the free tier keeps working unlimited, so a StoreKit failure never blocks a workout"); the generation path carries no entitlement gate (`ViewModels/ReadyViewModel.swift:399-415`; `Services/Engine/SessionAssembly.swift` has no premium/subscription reference) | true |
| 6.3 | "No account to make, and no card to enter." | `slide-02.html:17` | `ViewModels/OnboardingViewModel.swift:286-292` (local UUID fallback, no account required - as row 1.14); the open-to-Start path never reaches a purchase (`ViewModels/PaywallViewModel.swift:7-9`; the paywall's sole call site is `Views/Progress/ProgressTabView.swift:63-72`) | true |
| 6.4 | "A workout you have to pay to reach has already chosen who gets to do it." | `slide-03.html:16` | Describes a mechanism in the abstract, names no company and claims no motive - the free-tier analog of row 5.8 and the same construction the folder blesses there | not code-checkable (argument) |
| 6.5 | "Rep Today does not. The session is there the moment you open it, and starting it never costs anything." | `slide-03.html:17` | Session assembled before render (`ViewModels/ReadyViewModel.swift:152` `load()`, `:399-415` `generate()`; as rows 1.7/1.8); Start reaches no paywall (`Views/Ready/ReadyView.swift:188-206`, no entitlement reference; `StoreKitSubscriptionService.swift:10-11`) | true |
| 6.6 | "One thing is paid: a deeper view." plus "Pattern-by-pattern balance, your weekly training volume, and how your sessions have felt over time. That is what the paid tier unlocks, and it is the only thing it unlocks." | `slide-04.html:16-17` | `Views/Progress/ProgressTabView.swift:822` (the verbatim in-product feature line: "Unlock pattern-by-pattern balance, your weekly training volume, and how your sessions have felt over time."), `:630-653` (`DeepAnalyticsSection` = pattern balance, weekly volume, difficulty mix); `Services/Progress/ProgressAnalytics.swift:13-16` (only `deep` is gated, at the render boundary); `StoreKitSubscriptionService.swift:10-11` ("Premium only unlocks the depth layer") | true |
| 6.7 | "The workouts stay free." | `slide-04.html:17` | `Views/Progress/ProgressTabView.swift:826` ("Your workouts are always free - Premium just adds the deeper view"); `StoreKitSubscriptionService.swift:10-11` | true |
| 6.8 | "One quiet card, in one place." plus "The invitation to go deeper is a single card on the Progress tab. It is never a popup, never mid-session, and it never stands between you and Start." | `slide-05.html:16-17` | `Views/Progress/ProgressTabView.swift:801-806` (`PremiumUpsellCard` = "a single quiet card, never a modal or repeated prompt"; "the only entry point; nothing here gates the core loop"), `:103-106` (rendered in place of the deep layer for free users, on the Progress tab); the paywall is presented only as a Progress-tab sheet (`:63-72`), never on the Ready/Start path | true (caveat: see F6) |
| 6.9 | "Free is the workout. Paid is the view." plus "The paid tier only ever adds a deeper look at training you already did for free. It does not sit between you and a session, and by the way it is built, it cannot." | `slide-06.html:16-17` | `Services/Progress/ProgressAnalytics.swift:13-16` (the free/paid split "lives at the render boundary"; the analytics are computed from the user's own `WorkoutLog` history, `:1-10`); `StoreKitSubscriptionService.swift:10-11`; the generation/Start path carries no entitlement gate (structural, as 6.5) | true |
| 6.10 | "The workouts were never the paid part." plus "Use Rep Today for as long as you like without paying anything. Premium is there if you want the deeper view, and invisible if you do not." | `slide-07.html:15-16` | `StoreKitSubscriptionService.swift:10-11` ("Free is unlimited core workouts forever"); premium surfaces only as the one opt-in card that renders when a free user opens the Progress tab's deep layer (`Views/Progress/ProgressTabView.swift:103-106`) | true |

Caption-only claims: none. Every caption sentence restates a slide claim above.

Pillar 2's "earned Strength Phase" is deliberately not carried on any slide: `Services/Consistency/PhaseEvaluator.swift` gates the Strength Phase on consistency and cleared entry tiers and carries no subscription/entitlement reference, so it is earned, never sold. Publishing "premium gates the Strength Phase" would be false; recorded so a future editor does not restore it. See F18 for the parallel pillar-5 routing-around.

---

## Carousel 7: "The warm-up is not filler."

The mobility post. It deliberately does not make positioning pillar 5's "co-primary" / "half the session" claim, because the shipped engine contradicts it - see F18 for the full record. Every line below is the true, code-supported matched-bookend story.

| # | Claim | Slide | Code | Verdict |
|---|---|---|---|---|
| 7.1 | "The warm-up is not filler." | `slide-01.html:20` | Thesis; settled by 7.2 to 7.6 below | true |
| 7.2 | "Every session opens with mobility." plus "A stretch on the way in, chosen for the day. Past ten minutes, a cooldown of held stretches on the way out." | `slide-02.html:16-17` | `Services/Engine/SessionAssembly.swift:24-26` (every session opens with a `.warmup` mobility block; past `cooldownThresholdMinutes` closes with a static-stretch cooldown), `:144-153` (`warmupExerciseCount` is at least 1 at every length, so even a 5-minute session opens with a warm-up), `:155-157` (`cooldownThresholdMinutes = 10`: 15/20/30/45/60 get a cooldown, 5/10 do not - "past ten minutes"), `:1132-1134` (`cooldownBlock` draws holds first) | true |
| 7.3 | "It matches what you are about to train." plus "Every stretch is tagged with the movements it complements, and the session opens with one that fits the day's main pattern. The way in shifts as your training does." | `slide-03.html:16-17` | `Models/Exercise.swift` `complements: [MovementPattern]` (the US-M02 tag, present on all 26 mobility movements in `Resources/Exercises.json`, load-validated); `Services/Engine/SessionAssembly.swift:1417-1419` (`leadStrengthPattern` = the day's lead strength pattern), `:1373-1385` (`leadingComplement` promotes the best-variety stretch whose `complements` names the lead pattern to the front of the bookend) | true |
| 7.4 | "Tell it, and it leads with your hips." plus "Say you sit six or more hours most days, and the warm-up leads with hip and posture openers first, the stretches that counter a chair." | `slide-04.html:16-17` | `Views/Onboarding/OnboardingView.swift:621-629` (the onboarding toggle "I sit 6+ hours most days" sets `sitsLong`); `Services/Engine/SessionAssembly.swift:1405-1409` (`postureHipLean` stable-partitions the bookend pool so posture/hip openers lead when `sitsLong`), `:434-440` (`postureHipPatterns = [.squat, .hinge]`, the hip-dominant patterns), `:442-448` (`isPostureHipOpener` = a stretch complementing one of those) | true (caveat) |
| 7.5 | "Rarely the same stretch twice." plus "The pool turns over on its own. What you did last time gets pushed back, and the longest-ago and never-tried stretches come first." | `slide-05.html:16-17` | `Services/Engine/SessionAssembly.swift:1336-1359` (`orderedMobility` sorts never-worked and longest-ago first), `:1433-1439` (`recentlyUsedIds` pushes the last `varietyWindow` sessions' stretches back), `:1421-1431` (`mobilityLastWorked` supplies the longest-ago ordering) | true |
| 7.6 | "It frames the work. It is not the work." plus "Every session is strength-led. The stretches open and close it. They are not the main event, and they are not padding either: each one is chosen to earn the minute it takes." | `slide-06.html:16-17` | `Services/Engine/SessionAssembly.swift:11-12,24-26` (every session strength-led since US-M01; mobility appears only as the warm-up/cooldown bookends, never a training block); `Models/SessionPolicy.swift:37-43` (`pillarWeighting` inert - there is no mobility-share lever); "chosen to earn the minute" restates 7.3 to 7.5 | true |
| 7.7 | "The stretch was picked on purpose." plus "Not a generic warm-up bolted on the front. One matched to the day, and to how you spend it." | `slide-07.html:15-16` | Restates 7.3 (matched to the day) and 7.4 (matched to how you sit); "generic warm-up bolted on the front" describes what this is *not*, a self-referential contrast that names no other app | true |

Caption-only claims: none.

The 7.4 caveat, recorded so it is not rediscovered: the shipped `sitsLong` behavior is a pure *reorder* of the fixed-count bookend pool toward posture/hip openers (`postureHipLean`), not a lean on session *size*. The in-product onboarding caption at `Views/Onboarding/OnboardingView.swift:626` ("We'll lean your shorter sessions toward mobility.") overstates that; the slide copy describes the actual reorder ("leads with hip and posture openers first"), not a size change, so it is true where the in-app caption is loose.

---

## Carousel 8: "It is 9pm."

The 9pm day-in-life recognition. The scene beats are recognition and are marked "not code-checkable" the same way carousel 3's windows are (row 3.1); the product claims woven through are verified against code.

| # | Claim | Slide | Code | Verdict |
|---|---|---|---|---|
| 8.1 | "It is 9pm." plus "The kids are down. The house is quiet." plus "You have maybe ten minutes before the couch wins. The will is there. The window is small, and it is closing." | `slide-01.html:20`, `slide-02.html:16-17` | none | not code-checkable (audience recognition; as 3.1) |
| 8.2 | "The last thing you have energy for is a decision." plus "Not the movement. The choosing. Which app, which workout, how long, where to start. That is the part that loses to the couch." | `slide-03.html:16-17` | none | not code-checkable (framing; the decision-fatigue thesis, as 3.2) |
| 8.3 | "The deciding is already done." plus "Open Rep Today and a full session is already on the screen, sized to the time you have. Nothing to browse, nothing to pick, nothing to plan." | `slide-04.html:16-17` | Session assembled before render (`ViewModels/ReadyViewModel.swift:152` `load()`, `:399-415` `generate()`; as 1.7/1.8/3.3); no catalog, picker, or session editor surface exists (as 1.9/3.7/3.8) | true |
| 8.4 | "Ten minutes tonight. More when you have it." plus "If ten is wrong, one tap changes it, from 5 minutes up to 60, and the session rebuilds around the new number." | `slide-05.html:16-17` | `Views/Ready/ReadyView.swift:170-183` (one tap, no confirm step); `ViewModels/ReadyViewModel.swift:270` (`selectDuration` regenerates in place); `Services/Programmer/DefaultDurationLearning.swift:37` (`chipValues = [5, 10, 15, 20, 30, 45, 60]`, so "ten" and "5 ... 60" are real chips) - carries the F7/F16 corrected phrasing "from 5 minutes up to 60" | true |
| 8.5 | "A patch of floor is the whole setup." plus "Bodyweight, so it needs no equipment. Built on the phone, so it needs no signal. No account between you and the first move." | `slide-06.html:16-17` | Bodyweight / no equipment (`Resources/Exercises.json`, every entry `equipment: []`, enforced `Services/Mock/MockExerciseService.swift:143-145`; as 1.20/5.2); built on phone / no signal (`Services/Mock/MockServices.swift:28-50`, engine imports Foundation only; as 1.21/5.6); no account (`ViewModels/OnboardingViewModel.swift:286-292`; as 1.14) | true (caveat: "no signal" is scoped to session generation, see F9) |
| 8.6 | "You did not need more time." plus "You needed one less decision at the end of a long day. That is the whole idea." | `slide-07.html:15-16` | none | not code-checkable (framing; ties back to 8.2) |

Caption-only claims: none. The caption's scene sentences restate the recognition beats above. No hotel room appears anywhere (carousel 5 owns that image, and pairing a hotel room with a short session would assemble AB-5 leg B), and no minute figure is paired with "counts" (AB-5 leg A), per the folder README's carousel-5 note.

---

## Carousel 12: "The way back is gentle."

This carousel goes deep on the return-after-a-gap experience, so two precise things are recorded before the table, because both are exactly where the copy could have drifted.

**The "celebration" is a scoring treatment, never a screen.** The brand deck (Hero B) and one frozen PMF angle (P13) both say the app "celebrates" a comeback, but F12 established - and the current source confirms - that nothing the user can see marks a return: `wasReturn` is read only by the scorer (`Services/Consistency/ConsistencyScore.swift:84`), the policy exclusion (`Services/Programmer/DeterministicSessionPolicyService.swift:208`), and the swap ease (`Services/Engine/ExerciseSwap.swift:170`); it reaches the log write and one telemetry property and **no view**. There is no welcome-back copy anywhere in `Views/`. So no slide claims a banner. Slide 6 states the honest version instead - the comeback is counted in the *score*, not on a *screen* - and says so in as many words ("It is not a banner and not a badge").

**Mid-week versus settled-week, stated precisely (the F3/F11 nuance the score's layers create).** The score is a weighted rolling average whose in-progress week is bucket 0 at the **highest** recency weight (`ConsistencyScore.swift:110`, `:114`, `:164-166`), so a fresh week begins at zero adherence and climbs as sessions land. A comeback session does not dodge this by existing; it resolves it *once logged*: the moment a `wasReturn` session is recorded, that week is in `returnWeeks` and its adherence is set to a full `1.0` regardless of count (`:125-128`). So "counts as a full week" (slide 6) is a **week-level** treatment that takes effect when the comeback session is completed - not a mid-session UI event and not an automatic pre-session bump.

| # | Claim | Slide | Code | Verdict |
|---|---|---|---|---|
| 12.1 | "The way back is gentle." | `slide-01.html:20` | Supported by 12.2 to 12.4: the Return override serves the first session back easy and winnable | true |
| 12.2 | "A week away changes the next session." plus "Go about seven days without finishing a session, and the one waiting when you come back is built as a comeback, not a normal day." | `slide-02.html:16-17` | `Services/Engine/ReturnOverride.swift:38` (`returnThresholdDays = 7`), `:64-68` (`isReturn`: gap at or past the threshold), `:74-86` (`daysSinceLastSession`, measured from the most recent completed log) | true |
| 12.3 | "It meets you where you are now, not where you left off." plus "However hard you were training before the gap, the comeback is capped to an easier level, so a strong past week can never serve you a punishing one." | `slide-03.html:16-17` | `Services/Engine/ReturnOverride.swift:53` (`returnMaxDifficulty = 2`), `:94-98` (`returnPool` caps the eligible pool to that tier), `:50-53` (doc: a strong pre-gap history cannot serve a punishing tier) | true |
| 12.4 | "The catch-up is spread out, never loaded onto day one." plus "The first session back asks for less, not more. Whatever readjustment the time away calls for is eased in over the next few sessions, never dumped on the one you returned with." | `slide-04.html:16-17` | `Services/Engine/ReturnOverride.swift:48` (`reentryFloorScale = 0.7`), `:110-111` (the Return serves that eased volume floor), `:40-43` and `:118-125` (the Re-entry Ramp walks volume back over `rampSessions = 3`), `:5-7` and `:19-25` (doc: the readjustment is spread across the following sessions, never loaded onto the Return) | true |
| 12.5 | "The weeks you were gone are not counted against you." plus "Consistency in Rep Today is a rolling average of showing up, not a run of days. The empty weeks a comeback closes are dropped from that average, not scored as misses." | `slide-05.html:16-17` | `Services/Consistency/ConsistencyScore.swift:102-140` (weighted rolling average of weekly adherence), `:164-166` (linear recency weight), `:81` and `:204-212` (bucketed by whole weeks, never days), `:118-123` and `:148-159` (empty gap weeks a Return closed are excused from the average) | true |
| 12.6 | "The session you come back with counts as a full week." plus "It is not a banner and not a badge. The comeback is counted in the score instead: that one session lands as a full week, so coming back can only steady your number or rebuild it, never lower it." | `slide-06.html:16-17` | `Services/Consistency/ConsistencyScore.swift:125-128` (a Return week scores adherence `1.0`), `:84` (`wasReturn` stamped from the log), `:21-24` (doc: a comeback cannot reduce the score, only preserve or rebuild it); "not a banner and not a badge" is settled by the visible-surface absence in F12 and the section note above | true (caveat: see the section note and F12; "counts as a full week" is week-level, resolved once the comeback session is logged) |
| 12.7 | "The comeback matters most." plus "So it is the session Rep Today makes the easiest." | `slide-07.html:15-16` | The "easiest" half is the Return override of 12.2 to 12.4 (`Services/Engine/ReturnOverride.swift`) | true (caveat: "matters most" is intent, not a mechanic; the easiest-session half is 12.2 to 12.4) |

Caption-only claims: none. Every caption sentence restates a slide claim above.

---

## Carousel 13: "Straight answers."

Every answer is settled against shipped behaviour, not the brand deck. This carousel deliberately makes **no** AI claim on any slide or in the caption, so it owes no AI disclosure (the launch checklist's disclosure rule triggers only on an AI mention).

| # | Claim | Slide | Code | Verdict |
|---|---|---|---|---|
| 13.1 | "Straight answers." plus "The questions people ask" | `slide-01.html:19-20` | Cover label for the FAQ; the answers are settled by 13.2 to 13.7 | not code-checkable (cover framing) |
| 13.2 | "Yes. Every workout is free." plus "Not a trial, not a teaser. Every workout Rep Today builds is free to do, with no session locked behind a purchase." | `slide-02.html:16-17` | `Views/Paywall/PaywallView.swift:93` ("Your workouts are always free"); `Views/Progress/ProgressTabView.swift:100-102` ("The core loop and the basic history above are never gated"); the paywall's only entry point is the Progress upsell (`:63-72`, `:103-107`) | true |
| 13.3 | "Only a deeper look at your own progress." plus "Premium adds a richer view of how your training is balancing out over time. It never touches the workouts, and the core of the app stands on its own without it." | `slide-03.html:16-17` | `Views/Progress/ProgressTabView.swift:100-107` (only the `DeepAnalyticsSection` is entitlement-gated; the core loop and basic history are never gated); `Views/Paywall/PaywallView.swift:100-105` (the gated depth: pattern balance, weekly volume, difficulty mix), `:93` | true |
| 13.4 | "No account, no sign-up." plus "The app works without signing in to anything. Sign in with Apple is there if you want it, and skipping it changes nothing about the workouts." | `slide-04.html:16-17` | `ViewModels/OnboardingViewModel.swift:286-292` (`resolvedIdentifier` falls back to a local identifier, resolves offline, never blocks `finish()`); `Views/Onboarding/OnboardingView.swift:238-250` (Sign in with Apple is optional and skippable, as row 1.14); `Persistence/PersistenceController.swift:5-17` (the core loop always works without an account). The copy was softened off an earlier "sync across devices" clause, which conflated Sign in with Apple identity with CloudKit's iCloud-account sync; the accurate sync statement lives on slide 6 (13.6) | true |
| 13.5 | "Yes. Airplane mode is fine." plus "Every session is built on your phone, by your phone, the moment you open it. Nothing is fetched, so a plane, a basement, or a dead zone changes nothing." | `slide-05.html:16-17` | `Services/Mock/MockServices.swift:28-50` and every file under `Services/Engine/` imports Foundation only; the library decodes from the app bundle at `Services/Mock/MockExerciseService.swift:86-97`, never fetched (as rows 1.21, 5.6, 5.7) | true (caveat: scoped to session generation, as F9) |
| 13.6 | "Your history is yours. Sharing is optional." plus "Your workout history lives on your device and syncs only to your own private iCloud, never to us. The one thing you can share is anonymous usage data, on unless you turn it off in Settings, and counted against a random number rather than your name." | `slide-06.html:16-17` | `Persistence/PersistenceController.swift:5-17` (the durable store is on-device; sync is additive and falls back to local-only), `:9` and `:29-31` (the Cloud store mirrors to the user's own private CloudKit database); `Views/Settings/SettingsView.swift:23` (the opt-out `Toggle` bound to `AppState.analyticsEnabled`), `:179` ("Share anonymous usage data"), `:192-195` (counted against a random per-install number, never name, email, or device); the gate defaults on, so "on unless you turn it off" is accurate | true |
| 13.7 | "Then just start." plus "The session is ready when you are." | `slide-07.html:15-16` | `ViewModels/ReadyViewModel.swift:183`, `:407-415` (the session is generated inside `load()`, before the Ready screen renders), as rows 1.7, 1.8, 3.3 | true |

Caption-only claims: none. Every caption sentence restates a slide claim above.

---

## Carousel 14: "It is coming to iOS."

A launch announcement, written to stay true across the whole pre-launch window: no slide names a date, promises a listing, or carries a URL. The product-mechanic claims reuse the same code the pinned carousels are settled against; the status claims are true because the pre-publication checklist still carries the listing as unbuilt.

| # | Claim | Slide | Code | Verdict |
|---|---|---|---|---|
| 14.1 | "It is coming to iOS." | `slide-01.html:20` | Rep Today is an iOS app (the whole `ios/` target; repo-root `AGENTS.md`); the pre-launch framing is honest because no App Store listing exists | not code-checkable (pre-launch status / positioning) |
| 14.2 | "A complete session, already on the screen." plus "You open Rep Today and the workout is already built and waiting. No browsing and no questions between opening it and starting." | `slide-02.html:16-17` | `ViewModels/ReadyViewModel.swift:183`, `:407-415` (generate runs inside `load()`, before render); no catalog or picker on the path (as rows 1.7, 1.8, 1.9, 1.13) | true |
| 14.3 | "No equipment. No account. No signal." plus "Bodyweight movements only, built on your phone with no connection, and no sign-in standing between you and your first session." | `slide-03.html:16-17` | Bodyweight: `Resources/Exercises.json` (every entry `equipment: []`), enforced `Services/Mock/MockExerciseService.swift:143-145` (as 1.20, 5.2); offline generation as 1.21, 5.6; the local-identifier no-account path as 1.14 and 13.4 | true |
| 14.4 | "As much time as you have. Five minutes, up to sixty." plus "Tell Rep Today how long you have and it sizes the whole session to fit, anywhere from a five-minute reset to a full hour." | `slide-04.html:16-17` | `Services/Programmer/DefaultDurationLearning.swift:37` (`chipValues = [5, 10, 15, 20, 30, 45, 60]`, the vocabulary the user actually touches, spanning five to sixty), consumed at `ViewModels/ReadyViewModel.swift:59`; the engine accepts the whole span (as 1.4, 4.11) | true |
| 14.5 | "For the people who keep meaning to move." plus "Busy, desk-bound, out of patience for planning a workout, and looking for one that is already decided by the time they open the app." | `slide-05.html:16-17` | The "already decided by the time they open the app" half is 14.2; the audience description is `positioning.md`'s "busy, desk-bound adults" | true (caveat: the audience description is positioning, not a mechanic; the readiness half is 14.2) |
| 14.6 | "Not out yet, and no countdown to it." plus "Rep Today is an iOS app that has not been released. There is no App Store page, and no date to promise here: this is a heads-up, not a launch clock." | `slide-06.html:16-17` | Pre-launch status is true: no App Store listing exists (`../08-redteam/pre-publication-checklist.md`; the README pre-publication table). No mechanic; the honest status beat | not code-checkable (pre-launch status statement) |
| 14.7 | "When it opens, it opens ready." plus "That is the whole idea behind Rep Today." | `slide-07.html:15-16` | `ViewModels/ReadyViewModel.swift:183`, `:407-415` (opens to an already-built session), as 14.2 | true |

Caption-only claims: the caption closes on "iOS, not released yet. Join the waitlist at the link in bio.", which names the bio link rather than a destination on any slide (per the folder's rule that no slide carries a URL or a CTA). Not a behavioural claim about the app.

---

## Findings

### Carousels 6 to 8 (written from code; one deliberate routing-around recorded)

The three new carousels were written against the shipped source from the start, so none carries a corrected claim of its own.
One positioning-vs-code conflict was routed around rather than published, and it is recorded here with the prominence the folder gives that class of decision.

**F18. Carousel 7 is the mobility post, and positioning pillar 5's "co-primary" / "half the session" framing is false about the shipped engine, so this carousel routes around it exactly as the folder README routes pillar 5 out of carousels 1 to 5.**

`positioning.md` pillar 5 ("Mobility is a pillar, not a warm-up") proofs itself as "mobility is co-primary with strength and primal in the engine's pillar weighting" and carries the hook "Half your session can be the part other apps skip." That hook is also pre-registered as angle P08, which is why quoting it verbatim in a slide or caption is a `claim-audit.py` failure; it is quoted here because `claim-verification.md` is documentation, not publishable copy, and the guard scopes the frozen-hook check to slides and captions only.

The shipped engine contradicts every part of the pillar-5 framing:

- US-M01 removed the Movement Practice mobility middle block and the `PillarBalance` / `PillarWeights` split machinery. `Models/SessionPolicy.swift:37-43` records `pillarWeighting` as inert ("no engine path reads this lever today"), so there is no pillar weighting for mobility to be co-primary in.
- `Services/Engine/SessionAssembly.swift:11-12,24-26` states mobility "appears only as the warm-up and cooldown bookends, never as a training block ... there is no mobility middle block at any length", and that every session is strength-led. A blend's training minutes are essentially all strength, or strength leading a small primal minority at 41 to 60 minutes. Mobility is nowhere near half.

Publishing "co-primary" or "half" would therefore be a false claim about the product. Rather than publish it or drop the mobility post, carousel 7 argues the true story the engine does support - quality over quantity: the mobility you get is deliberately chosen, matched to the day's lead movement (7.3), biased toward hip and posture relief when you sit all day (7.4), rotated for variety (7.5), and honestly scoped as the frame around a strength-led session rather than half of it (7.6).

This is the same routing-around the README's "Two stale sources this folder had to route around" note already records for pillar 5, whose "co-primary" / "half the session" framing is "never published as written" and which records that "Carousels 1 to 5 do not use pillar 5 at all". Carousel 7 is the first asset to build on the corrected, code-true version of the underlying idea, and it makes none of the claims that note forbids. Recorded prominently because a future editor who reads pillar 5 will be tempted to restore the co-primary / half framing, and it is false.

### Corrected in this commit

**F1. Carousel 2 slide 5: the app was described as swapping a movement by itself.**

Was: *"It has already chosen, and it will swap a movement mid-session if it chose wrong."*

The app does not detect that it chose wrong and does not swap anything on its own.
Swap is a user-initiated control (`Views/ActiveSession/ActiveSessionView.swift:411-419`, label "Swap this exercise", hint "Replaces it with a similar movement"); the engine only picks the replacement once the user asks.
The sentence read as machine self-correction, which is a capability the product does not have.
Now: *"It has already chosen, and if it chose wrong for you, one tap mid-session swaps that movement for a similar one."*

Recorded edge, deliberately not put on the slide: the swap can decline.
When `ExerciseSwap` finds no safe same-pattern peer inside the time budget the original movement stays, and the app says so in-product ("No safe alternative for this one - it stays in your session.", `ActiveSessionView.swift:581`).
The product discloses this itself at the moment it happens, which is the right place for it.

**F2. Carousel 3 slide 5: "a patch of floor" omitted the wall.**

Was: *"A patch of floor, no equipment, no signal required."*

The Zero-Equipment Floor is a floor **and a wall**, and the code says so in as many words (`Models/Enums.swift:86-90`).
This is not a technicality for a brand-new install: a beginner's entry tier in three separate chains is wall-dependent, namely Wall Push-Up (`push_horizontal` order 0), Wall Sit (`squat` order 0), and Wall Scapular Pull (`pull_horizontal` order 0).
A reader who took "a patch of floor" literally could not do their first session.
Carousel 5 already had this right; carousel 3 was the surface that drifted.
Now: *"A patch of floor, a wall, no equipment, no signal required."*

**F3. Carousel 4 slide 4: the sentence that had already taken four rounds of correction.**

Was: *"The score reads the week, not the day: miss a day and still meet your weekly goal, and it does not move at all. A week that falls short dents it, the dent is small, and it fades as the weeks after it come in."*

Three independent defects in one sentence.

*It pointed at a weekly goal the app never shows.*
`weeklyGoal` is written once at `ViewModels/OnboardingViewModel.swift:331` as the hardcoded constant `ConsistencyScore.defaultWeeklyGoal` (3), the user is never asked for it, and it appears nowhere in `Views/`.
Per the captain's decision on `weekly-goal-has-no-in-app-surface` this was fixed in the copy, not the product; surfacing or making the goal settable is filed separately as `reptoday-weekly-goal-invisible` and was out of scope here.

*"it does not move at all" was true only of the settled end-of-week value.*
`ConsistencyScore.swift:114` loops `for weeksAgo in 0...oldestIncluded`, so the in-progress week is bucket 0 at the **highest** recency weight (8 of a 36 weight total, `:164-166`).
Running the shipped `ConsistencyScore.evaluate` over a user with eight on-goal weeks: the score reads **77.8 on the first morning of a new week**, then 85.2, 92.6, and 100.0 as that week's three sessions land.
So the number a user actually sees moves continuously through every week and starts each one about 22 points down.
The claim's antecedent ("still meet your weekly goal") cannot even be evaluated until the week is over, which is exactly why four rounds of true-but-incomplete patching never converged.

*"the dent is small" was unsupported.*
A single zero week costs 22.2 points from 100 and a single short week costs 14.8, which is the largest effect any one week can have precisely because week 0 carries the top weight.

The slide was rewritten rather than cut.
Cutting it was an acceptable outcome under the brief, but slide 4 is the carousel's honesty beat: removing it would leave only the sunny claims on slides 3 and 7 and make the post less honest, not more.
The rewrite drops the day-level claim entirely rather than trying to phrase it a fifth time.
Now: *"Nothing in the score is measured in days, so there is no day to miss. It averages your recent weeks: a week that falls short dents it, the dent shrinks with every week after, and after eight it is gone entirely."*

Every clause is now settled by the code rather than by a scenario: nothing in the score is day-indexed (`:81`, `:130`, `:204-212`), the dent shrinks monotonically as the recency weight falls (`:164-166`, measured 85.2, 87.0, 88.9, 90.7, 92.6, 94.4, 96.3, 98.1 across the eight weeks that follow), and a week 8 or more weeks old is outside the window (`:45`, `:110`).

**F12. Carousel 4 slide 6: the app was said to mark the return.**

Was: *"Return after a week away and the app opens to a session that is easy and winnable, and it treats the return itself as the thing worth marking."*

The first half is true.
The second half is not: nothing in the app marks, names, acknowledges, or celebrates a return anywhere the user can see.
`wasReturn` reaches the log write (`ViewModels/ActiveSessionViewModel.swift:618`) and a telemetry property (`:1521`), and no view reads it.
There is no "welcome back" copy, and the Variety Language note only ever produces day-type lines like "Today's a strength day" (`Services/Language/VarietyLanguage.swift:84-96`).

What is real, and is what the sentence was reaching for, is the scoring treatment: the weeks in the gap are excused from the average and the comeback week scores a full 1.0.
That is stronger than the claim it replaced and it is fully checkable.
Now: *"Come back after a week away and the session waiting is deliberately gentler. The weeks you were away are excused from the score, and the session you came back with counts as a full week."*

**F7. Carousel 3 slide 4: "anywhere from 5 to 60 minutes" implied a continuous range.**

Was: *"If the length is wrong, one tap changes it. Anywhere from 5 to 60 minutes."*

There are seven discrete lengths, not a continuum: `Services/Programmer/DefaultDurationLearning.swift:37` defines `chipValues = [5, 10, 15, 20, 30, 45, 60]`, and the comment two lines above it explicitly contrasts these with "arbitrary minute values".
A reader with 25 minutes taps 20 or 30.
Coupled to "one tap changes it", "anywhere" promised a choice the app does not offer.
Now: *"If the length is wrong, one tap changes it, from 5 minutes up to 60."*

The bare range statement elsewhere ("Sessions run anywhere from 5 to 60 minutes", `carousel-4/slide-05.html:17`) describes the span of session lengths that exist rather than a selectable value, is true as written, and was left alone.

This rationale was originally extended to `carousel-1/slide-02.html:17` as well, which was wrong: that sentence carries selection framing. See F16.

**F16. Carousel 1 slide 2 carried the same continuum framing F7 corrected on carousel 3, and this table certified it on evidence that does not settle it.**

Was: *"A complete bodyweight session, assembled on your phone and sized to the time you have. Anywhere from 5 to 60 minutes. One Start button, nothing to browse."*

F7 corrected exactly this framing on carousel 3 and then exempted this sentence, on the reasoning that a bare range statement describes the span of session lengths rather than a selectable value.
That reasoning holds for `carousel-4/slide-05.html:17` ("Sessions run anywhere from 5 to 60 minutes", a statement about what exists) and does not hold here, where "sized to the time you have" **is** the selection framing and "Anywhere" attaches directly to it.
The duration input is seven discrete chips everywhere a user can touch it: `Services/Programmer/DefaultDurationLearning.swift:37` defines `chipValues = [5, 10, 15, 20, 30, 45, 60]`, whose own doc comment says "the Ready Screen offers chips, not arbitrary minute values", and `ViewModels/ReadyViewModel.swift:59` and `Views/Onboarding/OnboardingView.swift:653` both consume that array verbatim.
A reader with 25 minutes taps 20 or 30.
Now: *"A complete bodyweight session, assembled on your phone and sized to the time you have, from 5 minutes up to 60. One Start button, nothing to browse."*
Mirrored into the slide alt text at `caption.md:28` in the same commit.

The row itself was the second half of the defect, and is the more serious half.
Claim 1.4 read verdict **true** citing `Services/Engine/SessionShapeSelection.swift:45` (`supportedRange = 5...60`), which is an engine-internal clamp on an arbitrary `Int` the UI never supplies; its own doc comment says it exists so "the mapping is total".
A clamp cannot settle a claim about what a user may pick, so the row certified a user-facing claim on evidence that does not reach it, and a table that does so is worse than no table because the next reader trusts it.
Row 1.4 now records the corrected copy against the chip vocabulary.

Every other row was re-checked for the same defect, and the rule that separates them is whether the claim is about **what the user may select** or about **what the engine produces**.
A selection-shaped claim is settled only by the vocabulary the UI actually offers; an engine-internal constant is a proxy for that and cannot certify it.
A claim about what the engine produces - the pool it draws from, the number it computes, the session it assembles - is settled by engine source directly, because there the engine is the subject rather than a stand-in for one.
Applying that rule: only one other row rested on an engine-internal constant for a selection-shaped claim, 4.11, which cited `SessionShapeSelection.swift:45` alone for "Sessions run anywhere from 5 to 60 minutes".
The copy there is correct and captain-signed-off and was not touched, but the citation now leads with the chip vocabulary and keeps `supportedRange` only as corroboration.
Rows 3.10 and 5.10 restate 1.4 and 4.11 by reference and inherit both corrections.
Every remaining row citing engine source is an engine-produces claim under that rule, so none of them carries this defect.
The rule is recorded here instead of the list of row numbers it was applied to, because a list is a second thing to keep in step with the table and goes stale the moment a row is added - which is the failure this finding exists to record, one level up.

**F14. README restated absolutes the slides had already corrected.**

`README.md:25` summarised carousel 4 as "no streaks, badges, XP, or leaderboards anywhere", and the "Claims deliberately not made" bullet on streak framing said the mechanic is "named exactly once per carousel, only to say it was not built".
Both are the pre-correction absolute: the app does surface one chain-shaped number, `Best run: N weeks on goal.`, which is why carousel 4 slide 2 names it rather than denying it.
Both lines now carry the qualification, and the bullet records *why* the negation is deliberately not an absolute so it does not get re-tightened.

This finding's own first fix was incomplete, and the residue is worth recording.
It corrected "exactly once" but left the rest of the sentence asserting that each carousel names the mechanic - which no carousel but 4 does, and which carousel 4 does for four mechanics at once rather than one.
The bullet is now written as guidance for a future slide (name one only to say it was not built, never as a device) rather than as a description of what the carousels did, so there is no per-carousel universal left to falsify.
The general lesson is the same one F17 records: a sentence stating a style intention in the past tense reads as a verified description, and the next editor has no way to tell which it was.

**F17. The README's own note explaining why carousel 5 keeps the hotel room rested on a false premise, taken from a search too narrow to establish it.**

Was: *"it names no session length anywhere (the words 'five' and '5 min' appear nowhere in the folder)"*, and, as the stated tripwire, *"adding a session length to carousel 5, or turning 'The session still builds.' into a claim about a short session still counting. Either one, on its own, completes leg B on that post."*

Carousel 5 does carry a session-length range: `carousel-5-a-floor-and-a-wall/slide-07.html:16` reads "Bodyweight. Offline. 5 to 60 minutes.", mirrored at that folder's `caption.md:41`.
The parenthetical was true only because it named two strings that happen to be absent; the note's conclusion therefore did not follow from its premise, and by its own tripwire the tripwire was already tripped.
No carousel copy changed - the range is correct and stays - but the recorded reasoning did, and the audit trail is exactly where a false premise does the most damage, because the next editor inherits it.

The note now states the true premise and the narrower grounds that actually hold: carousel 5 never names five minutes as *the* session, never puts a length on the same slide as the hotel room, and resolves its hotel-room slide to "The session still builds.", a claim about offline generation rather than about a short session counting.
The real edge is pairing five minutes specifically with the hotel room, or turning "still builds" into a counting claim.

The root cause is worth more than the correction: the negative result came from a case-insensitive string search for `five`, `5 min` and `5-min`, which does not match `5 to 60 minutes`, and it was written up as though it had searched the concept.
So the note now records the pattern that produced it.
Any negative result recorded in this folder should name its method, so a reader can judge its reach instead of inheriting a conclusion.
The A/B pre-exposure rule itself is unchanged and stays verbatim-scoped.

### Verified, not changed, recorded so they are not rediscovered

**F4. `longestChain` is recomputed, not stored, so "only counts up" is a property of the design rather than of a persisted high-water mark.**

There is no `max(stored, new)` anywhere; `Services/ActiveSession/SessionCompletionService.swift:143-146` overwrites the persisted value and both displays recompute live.
Given a fixed log set and goal it is monotonically non-decreasing, because the scan is anchored at `oldestActivity` rather than at the 8-week window (`ConsistencyScore.swift:179`) and `longest = max(longest, current)` never shrinks.
Adding a workout can only move a week onto goal, never off it.
`weeklyGoal` cannot rise (it is written once and has no UI), so the one input that could retroactively disqualify weeks is pinned.

Three paths could still show a smaller number: a full-history read failure on the Ready screen falls back to the 70-day window (`ViewModels/ReadyViewModel.swift:214`), a locale change to the first weekday can re-split weeks (the week math at `ConsistencyScore.swift:204-212` takes its calendar as a parameter, and the `Calendar.current` default that supplies it in production enters at `:59` and `:226`), and account deletion zeroes everything.
The first is a degraded read and the third is a deliberate wipe, so the signed-off claim stands as written.
This is recorded rather than acted on, because it is a caveat on a captain-approved line, not a defect in it.

**F5. Onboarding can reappear, by exactly one route: Delete Account.**

`Services/Account/AccountDeletionService.swift:71-76` sets `appState.isOnboarded = false` and routes back to onboarding.
"It does not come back" remains true of the experience the slide describes, since a user who deletes their account has asked for a reset rather than had setup return unbidden.
No copy change.

**F6. A brand-new install does see one extra tap on its first session, after Start.**

`ContinuousCircuitExplainerView` (`Views/ActiveSession/ActiveSessionView.swift:195-198`) shows once on first arrival at the player, holds the session on a user pause while it is up, and dismisses on "Got it".
The carousel claims are scoped to "the path from opening the app to starting a session" and to the gap between Open and Start; the explainer is after Start, inside the player, and the session has already begun behind it.
So the claims are correctly scoped and no copy change is owed.
Recorded because a reviewer meeting this modal on a fresh install would reasonably suspect the "nothing stands between these two" line, and the answer is that the line was scoped narrowly on purpose.

**F8. The Ready screen has more than one tappable control, which is not what "one Start button" claims.**

Steady state is eight: Start plus seven duration chips, rising to ten when a paused session offers Resume and Discard (`Views/Ready/ReadyView.swift:170-183`, `:188-206`, `:275-294`).
"One Start button, nothing to browse" claims one dominant action and no catalog, and both hold: Start is the single primary action and is never disabled, and no surface lists exercises to pick from.
Carousel 3 slide 4 independently tells the reader the length is changeable, so the package does not hide the chips.

**F9. "No signal" is a claim about session generation, and generation is genuinely offline. The app as a whole does use the network.**

Telemetry posts in Debug builds (`Services/Analytics/LiveAnalyticsService.swift`, inert in Release because the endpoint is deliberately unset), CoreData mirrors to CloudKit, and StoreKit listens for transactions.
None of them is in the generation path and none can block it; the CloudKit store falls back to local-only on any failure (`Persistence/PersistenceController.swift:63-70`).
Every claim in the folder is scoped to the session ("The session is not fetched from anywhere", "Built on the phone, so it needs no signal"), and no slide says the app makes no network calls.
Correct as written; recorded so nobody strengthens it to "the app never touches the network", which would be false.

**F10. "It is not a strength program" sits alongside a strength-led engine and an earned Strength Phase.**

Every session is strength-led since US-M01, progression chains advance, and `PhaseEvaluator` gates a Strength Phase.
The claim still holds in the sense a reader takes it: there is no program to follow, no schedule, no periodization, no plan surface, and no coaching feedback anywhere in `Views/`.
Recorded because the tension is real and a future reviewer will notice it.

**F11. The in-progress week enters the average at zero adherence and the highest weight, so the displayed score dips at the start of every week.**

Quantified under F3: a user with eight on-goal weeks reads 77.8 on the first morning of a new week and climbs back to 100 as that week's sessions land.
No surviving claim contradicts this, because F3 removed the sentence that did.
It does sit in tension with slide 7's "The score's job is to reflect that, not to threaten it", which is an intent claim with no mechanic behind it rather than a checkable one.
Left as written; flagged here because it is the single most surprising behavior behind this carousel and it is what made the original slide 4 wrong.

**F15. The score can reach exactly 0, so "it cannot empty it" survives only because it is scoped to a single short week.**

Carried forward from an earlier round rather than rediscovered, and re-confirmed here by execution.
After 8 or more consecutive idle weeks the score is exactly **0.0**: `oldestIncluded` caps the window at 7 weeks ago (`ConsistencyScore.swift:110`), every week in it is empty and unexcused, so the weighted sum is zero.
Measured: last activity 8 weeks ago scores 0.0, and 9 weeks ago also 0.0.
Seven weeks ago is the last week that still registers at all, and it scores 2.8, because that week carries the minimum weight of 1 against a total of 36.

Slide 4's headline is scoped to "a short week", singular, and one short week can only take a full score to 85.2 (or 77.8 if the week is entirely empty).
So the claim is true as written and was left alone.
It would become false the moment anyone generalised it to "it can never reach zero", which is why this is recorded rather than left to be re-derived a third time.

**F13. One shipped movement's name implies a surface that "a floor and a wall" does not cover.**

`push_incline` ("Incline Push-Up", difficulty 1, `push_horizontal` order 1) sits one tier above Wall Push-Up, so the incline it needs must be lower than a wall, which in practice means a counter, a stair, or a couch arm.
It nonetheless carries `equipment: []` and `apartmentFriendly: true`, and `Models/Exercise.swift:73` defines that flag as "doable in a small space with only a floor and wall".

The carousel copy faithfully restates the product's own Zero-Equipment Floor guarantee, so no slide is wrong and nothing was changed here.
What is in question is the product data, not the advertisement: either `push_incline` is genuinely performable against a wall and the name is misleading, or the `apartmentFriendly` guarantee does not hold for it.
**This is a product-data question for the captain and is out of scope for a copy pass.**
It is recorded here rather than fixed, in the same spirit as `reptoday-weekly-goal-invisible`.

---

## Standing checklist item

`../08-redteam/pre-publication-checklist.md` carries "Verify every behavioral claim in the site/video/screenshots against the actual approved binary before launch day".
The item enumerates the surfaces that existed when it was written; these carousels are the same class of pre-launch asset, so the item is read as covering them too.

This pass discharges that item **for the Instagram surface at the source level**, which is the strongest form available before a build exists to install.
It is not a binary check and does not claim to be: it reads shipped source, not a signed artifact.
When an approved binary exists, the rows above are the checklist to walk against it, and the `true (caveat)` rows are where a binary is most likely to disagree with source, particularly F6 (the first-run explainer) and F8 (what is actually tappable on the Ready screen).

## Re-running the mechanical guards

The four guards in this folder cover format and correspondence, not truth, and all four pass on this commit.

```bash
./gtm/10-instagram/render.sh    # re-renders every slide, then runs all four guards
```

`fit-check.py` confirms every slide is exactly 1080x1350 with a clean 72px margin band, `widow-check.py` measures real line boxes and confirms no large-type line is a stranded short word, `claim-audit.py` confirms no banned string and no verbatim reuse of a pre-registered PMF hook, and `alt-text-check.py` confirms every slide's copy is still quoted verbatim in its own alt text.
Re-rendering on the same Chrome build is byte-for-byte reproducible, as the folder README claims: the render diff of each commit in this pass is scoped to exactly the slides whose copy that commit changed, and no others.
Stated as the property rather than as a count, because a count of re-rendered slides describes one past run and goes stale on the next.
