# PRD: Longer Training Days, Day-Matched Bookends, a General Health Coach, and Sign Out (2026-11-12)

- Status: **Part A approved and implemented (2026-11-12); Parts B and C are drafts awaiting captain approval.**
  Every decision below was settled with the captain in a design grill on 2026-11-12.
  The captain approved Part A as written on 2026-11-12, settling Open Question 2 in favor of decision 1, and it is implemented (ADR-0018); Parts B and C are not authorized until the captain approves them, each on its own.
- Story prefixes: `US-SZ##` (Part A, session sizing and bookends), `US-HC##` (Part B, health Coach), `US-SO##` (Part C, sign out).
- Related decisions (new, on landing): ADR-0018 (session sizing and day-matched bookends), ADR-0019 (the Coach answers general health and fitness questions).
- Amends, on landing: [ADR-0013](../../../docs/adr/0013-fixed-four-sets-five-step-reps.md) (fixed movement counts by length); [ADR-0017](../../../docs/adr/0017-coach-agent-on-convex.md) (diet guidance scope); `prd-ppl-rest-accounts-coach-agent_261110.md` decisions 7-8 and 12, its Goals line on movement counts, FR-3, FR-12, and its non-goal "Calorie or macro targets, meal plans, weight-loss plans"; US-M02's prefer-then-fill bookend selection.

## Introduction / Overview

Four captain asks, delivered as three independent parts that can ship in parallel:

1. **Part A - Longer Training Days and day-matched bookends.**
   Sessions get more main movements per length, 45 and 60 minute sessions get a second Core Sprinkle, and every warm-up and cooldown stretch relates to the day's group.
2. **Part B - A general health and fitness Coach.**
   The Coach answers general questions about sleep, stress, recovery, nutrition, cardio and other training, not only Rep Today training, inside medical, age and on-purpose rails.
3. **Part C - Sign Out.**
   A signed-in user can sign out from Settings without losing work silently, and the phone keeps nothing of the previous account.

## Goals

- Main movements per Training Day follow the new length table (decision 1), and 45/60 minute sessions carry two Core Sprinkles (decision 2).
- Every warm-up and cooldown stretch complements the day's group whenever the catalog has enough matching stretches.
- The Coach gives a helpful general answer to any health or fitness question in scope and a clear redirect for anything medical, crisis-related or off-topic.
- A user can sign out in two taps, and no workout is lost without an explicit warning.

## Interview decisions and where this PRD carries them

| # | Decision (captain's answer) | Carried by |
| --- | --- | --- |
| 1 | Main movements by length: 5 min 1, 10 min 2, 15 min 2, 20 min 3, 30 min 3, 45 min 4, 60 min 5 (replaces decision 8 of the 2026-11-10 PRD: 1/1/1/1/2/3/4). | US-SZ01 |
| 2 | Core Sprinkles by length: none at 5-10 min, 1 at 15-30 min, 2 at 45-60 min. | US-SZ01 |
| 3 | The Abs Focus Area adds one Core Sprinkle wherever core appears: 2 at 15-30 min, 3 at 45-60 min (one from each of the three core ladders). | US-SZ01 |
| 4 | Push and Pull have two ladders each, so their fifth main slot (60 min) is a **Variation**. Legs fills its fifth slot from its four ladders as the Practice Movement of its first ladder. | US-SZ02 |
| 5 | The Variation slot is built now and left empty until a Variation with Trainer art exists for the user's current rung; until then a 60-minute Push or Pull Day has 4 main movements, filled by reps and rest. Each Variation goes live by landing its catalog entry and art, with no further engine change. | US-SZ02; captain content task (Open Question 1) |
| 6 | When a rung has several Variations, they rotate, least recently done first. A Variation unlocks with its parent rung and never advances the ladder (2026-11-10 decision 12 stands). | US-SZ02 |
| 7 | Strict bookend matching: every warm-up and cooldown stretch complements the day's group (Push Day: push; Pull Day: pull; Legs Day: squat or hinge). The existing variety order (least recently done first, no recent repeats, Different-workout exclusions) picks among matching stretches. Unmatched stretches are used only if the matches run out. | US-SZ03 |
| 8 | The desk-worker posture/hip preference only reorders within the matching stretches; it never brings an unmatched stretch into a bookend. | US-SZ03 |
| 9 | Coach scope, in: sleep, stress and recovery, hydration, nutrition (per decision 10), cardio, walking and daily activity, questions about other training (gym lifting, running, sports), energy and general wellbeing habits. Custom Workouts stay bodyweight-only. | US-HC01 |
| 10 | Diet depth for adults: general published ranges framed as general (for example protein for active adults), sample meals and day-of-eating ideas, weight-management principles (a moderate deficit, a sustainable pace, protein and strength training to keep muscle), and general evidence on common supplements (protein powder, creatine, caffeine). Out: a personal calorie or macro number calculated for this user, crash or very-low-calorie diets and fasting protocols pushed as a plan, and diet for pregnancy or medical conditions. The Coach is never sent height or weight and does not ask for them. | US-HC02 |
| 11 | Coach scope, out: diagnosis, treatment, medication and injury rehab plans (redirect to a professional); mental health crises and disordered eating (a short, caring redirect to professional help, never coaching); topics unrelated to health (a polite decline and an offer of health or training help). | US-HC01 |
| 12 | Users under 18 or of unknown age: the server-side diet rail stays and keeps covering supplements, weight loss and weight management. Everything else in decision 9 is open to every age. Plain hydration (how much water to drink around training) is open to every age and leaves the rail's word list. The redirects of decision 11 apply at every age. | US-HC03 |
| 13 | Sign Out lives in Profile -> Settings, in the account section above Delete Account, in plain (non-destructive) styling, behind a "Sign out of Rep Today?" confirmation. | US-SO01 |
| 14 | Before signing out, the app tries to upload pending changes. If any remain (for example offline), the dialog says recent workouts have not been saved to the account and will be lost, with Sign Out Anyway and Cancel. Nothing is lost silently. | US-SO01 |
| 15 | Signing out erases the phone's copy of the account: workouts, profile, today's choices, the Coach conversation and scheduled reminders; the account's data stays on the server. The app returns to sign-in. | US-SO02 |
| 16 | Signing back in downloads the history and lands on Today with no repeated onboarding; a brand-new account still onboards. Premium stays linked to the account, with no restore needed. | US-SO02 |

## Verified facts on current main (2026-11-12)

- Main slots are `SessionAssembly.mainSlotCount` (5-20 min 1, 30 min 2, 45 min 3, 60 min 4); Core Sprinkles are `coreSprinkleCount` (none up to 10 min, one beyond, two with Abs).
- Warm-up holds 1 stretch up to 10 minutes and 2 beyond; cooldown holds none up to 10 minutes, 1 at 15-20 and 2 from 30 (unchanged by this PRD).
- Bookends lead with one stretch that complements the day's lead pattern and fill the rest by variety (US-M02 prefer-then-fill, `leadingComplement`); `sitsLong` reorders toward posture/hip openers first (`postureHipLean`).
- Matching stretches in the catalog by the `complements` tag: push 8 (3 moving, 5 holds), pull 6 (2 moving: Thoracic Rotations and Arm Circles; 4 holds), squat 14, hinge 11.
  Strict matching never runs short today; a Pull Day's warm-up will nearly always be Thoracic Rotations and Arm Circles.
- The Coach's instructions (`convex/coachPrompt.ts`) scope it to training, form and encouragement, with adult-only general diet guidance and a ban on calorie or macro targets, meal plans and weight-loss plans.
- The minor diet rail (`convex/coachSafety.ts`) already blocks supplements, creatine and weight loss, and today also blocks hydration and drink words.
- There is no Sign Out control; `AccountSignInViewModel` signs out only on internal failure paths.
  Onboarding already offers "Already have an account? Sign in and your plan comes back."

### Movement counts per session (warm-up + main + core + cooldown)

| Length | Today | Proposed | Proposed with Abs |
| --- | --- | --- | --- |
| 5 | 2 | 2 | 2 |
| 10 | 2 | 3 | 3 |
| 15 | 5 | 6 | 7 |
| 20 | 5 | 7 | 8 |
| 30 | 6 | 8 | 9 |
| 45 | 8 | 10 | 11 |
| 60 | 9 | 11 (10 on Push/Pull until Variations exist) | 12 |

This reverses part of the 2026-11-10 PRD's goal of "at most 8 movements at 45 minutes and 9 at 60", which came from user reports that long sessions felt crowded (see Open Question 2).

## Parts

### Part A - Longer Training Days and day-matched bookends

#### US-SZ01: Main movement and Core Sprinkle counts by length
**Description:** As a user, I want more main work in each session length, and more core work in long sessions.
**Acceptance Criteria:**
- [ ] Main slots follow decision 1; Core Sprinkles follow decisions 2-3.
- [ ] Slot order follows the 2026-11-10 decisions 9-11: a Push or Pull Day's slots 1-2 are its ladders' current rungs, slots 3-4 their Practice Movements; a Legs Day fills from the squat, lunge, bridge and hip ladders, one squat-side and one hinge-side first.
- [ ] Focus Area ordering, the Practice fallback (rung below at volume reps, else one fewer movement), every-station-4-sets, 5-step reps, and no-mixed-groups invariants are unchanged.
- [ ] The fit-feasibility harness reports planned time for every length x level x day, with particular attention to 5-20 minutes; a session that cannot fit runs short honestly, never over its tolerance.
- [ ] Verify in the simulator, light and dark, Dynamic Type, on a 375x667 screen.

#### US-SZ02: The Variation slot
**Description:** As a user on a 60-minute Push or Pull Day, I want a fifth movement that varies my current rung once its art exists.
**Acceptance Criteria:**
- [ ] A catalog entry can declare itself a Variation of a parent rung; it is eligible only when its parent rung is the user's current rung and Trainer art exists for both Trainers.
- [ ] A 60-minute Push or Pull Day's fifth slot takes an eligible Variation, rotating least recently done first (decision 6); with none eligible the slot stays empty (decision 5).
- [ ] A Variation never advances progression, Earned Reps or a foundation, and obeys injury exclusions and withdrawn-movement rules like any movement.
- [ ] A Legs Day's fifth slot is its first ladder's Practice Movement (decision 4).
- [ ] No Variation catalog entries or art are added by this story.
- [ ] Tests prove both paths with a test-only Variation fixture.

#### US-SZ03: Day-matched bookends
**Description:** As a user, I want my warm-up and cooldown to prepare and relieve the muscles I train today.
**Acceptance Criteria:**
- [ ] Every warm-up and cooldown stretch complements the day's group (decision 7); the variety order picks among matches; unmatched stretches fill only when matches run out.
- [ ] `sitsLong` reorders only within matches (decision 8).
- [ ] Bookend counts, the Rest Day Recovery flow and the Different-workout press are unchanged.
- [ ] Tests assert that every bookend stretch matches on each day at every length and level, and that a pool with too few matches falls back without emptying a bookend.

### Part B - A general health and fitness Coach

#### US-HC01: General health and fitness scope
**Description:** As a premium user, I want the Coach to answer my general health and fitness questions, not only questions about my Rep Today training.
**Acceptance Criteria:**
- [ ] The Coach's instructions carry the in-scope topics of decision 9 and the redirects of decision 11, keeping the existing tone, tools, proposal model and safety-move exclusions.
- [ ] A crisis or disordered-eating message gets a short, caring redirect to professional help, with no coaching.
- [ ] An off-topic message gets a polite decline and an offer of health or training help.
- [ ] The Coach evaluation (`convex/coachEval.ts`) adds turns for sleep, stress, a gym-lifting question, a running question, a medical-symptom question, a crisis message and an off-topic request, and the chosen model passes them.

#### US-HC02: Deeper general diet guidance for adults
**Description:** As an adult premium user, I want practical general nutrition guidance.
**Acceptance Criteria:**
- [ ] Adults receive the guidance of decision 10, and none of its exclusions.
- [ ] The Coach never asks for height or weight and never states a personal calorie or macro number.
- [ ] Evaluation turns cover a protein question, a sample-meals request, a weight-loss question, a creatine question, a request for a personal calorie target (declined with general guidance) and a pregnancy diet question (redirected).

#### US-HC03: The age rail under the wider scope
**Description:** As a parent of a teenage user, I want the Coach to stay out of diet topics for my child while still helping with sleep and training.
**Acceptance Criteria:**
- [ ] Users under 18 or of unknown age receive no diet, supplement or weight guidance, enforced on the server before and after the model (decision 12).
- [ ] Plain hydration questions are answered for every age; the rail's word lists are adjusted so "how much water should I drink after a workout" passes and "should I drink protein shakes" is still declined.
- [ ] Sleep, stress, recovery, cardio and other-training questions are answered for every age.
- [ ] Walked with a 16-year-old account and an adult account on the Convex development deployment.

### Part C - Sign Out

#### US-SO01: Sign Out in Settings
**Description:** As a signed-in user, I want to sign out of Rep Today.
**Acceptance Criteria:**
- [ ] Settings shows Sign Out in the account section above Delete Account, in plain styling (decision 13).
- [ ] Confirming first attempts to upload pending changes; with changes still pending, the dialog warns they will be lost and offers Sign Out Anyway and Cancel (decision 14).
- [ ] Cancel leaves the user signed in with nothing changed.

#### US-SO02: A clean phone after sign-out
**Description:** As a user handing over or sharing a phone, I want nothing of my account left on it after I sign out.
**Acceptance Criteria:**
- [ ] Signing out erases the phone's copy of the account per decision 15, cancels its scheduled reminders, and returns to sign-in.
- [ ] Signing back in with the same account restores the history from the server and lands on Today without onboarding; a new account onboards (decision 16).
- [ ] Premium remains active after signing back in, with no Restore Purchases.
- [ ] A different account signed in afterwards sees none of the previous account's data.
- [ ] Verify in the simulator, light and dark, Dynamic Type, VoiceOver, on a 375x667 screen.

## Functional Requirements

- FR-1: Main movement count follows decision 1; Core Sprinkle count follows decisions 2-3.
- FR-2: A 60-minute Push or Pull Day's fifth slot is an eligible Variation or empty; a Variation never advances progression.
- FR-3: Every bookend stretch complements the day's group unless the catalog has too few matches.
- FR-4: The Coach answers in-scope general health and fitness questions and redirects medical, crisis, disordered-eating and off-topic messages.
- FR-5: The Coach never gives a personal calorie or macro number and never asks for height or weight.
- FR-6: Users under 18 or of unknown age receive no diet, supplement or weight guidance; plain hydration is open to every age.
- FR-7: Sign out never discards an unuploaded change without an explicit warning.
- FR-8: After sign-out the phone holds no data of the signed-out account.

## Non-Goals (Out of Scope)

- Variation list and Trainer art production (captain content task; Open Question 1).
- New stretches for the catalog (the remedy if Pull Day bookends feel repetitive).
- Changes to bookend counts, the Rest Day Recovery flow, or the Coach's tools.
- Sending height, weight or other new personal data to the Coach.
- Changing the Coach's LLM provider or model unless its evaluation fails the new turns.
- Equipment-based Custom Workouts.
- Production deployment and release, which follow the owed M3/M4 release steps.

## Design Considerations

- The Settings Sign Out row and its dialogs use `DesignSystem/Theme.swift` tokens and are checked in light and dark, largest Dynamic Type, VoiceOver and a 375x667 screen.
- Coach copy stays discipline-first: warm, specific, short, never shaming.

## Technical Considerations

- Part A: `SessionAssembly.swift` (`mainSlotCount`, `coreSprinkleCount`, the slot plan, `orderedMobility`, `leadingComplement`, `postureHipLean`), `Exercises.json` schema for Variations, and the fit-feasibility, bookend-selection and invariant tests.
- Part B: `convex/coachPrompt.ts`, `convex/coachSafety.ts`, `convex/coachEval.ts`, with their tests; a Convex development deployment for the walk.
- Part C: `Views/Settings/SettingsView.swift`, `Services/Account/`, `Services/Sync/` (outbox flush and pending count), `Persistence/CoreDataSyncStore.swift`, `TodayChoices`, the Coach conversation cache and the reminder scheduler.
- The three parts touch disjoint code and can be built and reviewed in parallel.

## Success Metrics

- 45/60 minute session completion rate does not fall against the post-M1 baseline (watch for the crowding complaint of Open Question 2).
- Coach turns answered rather than declined, and the share of in-scope non-training questions.
- Sign-outs with pending changes that end in Cancel versus Sign Out Anyway.

## Open Questions

1. Variation list per Push and Pull rung and its Trainer art schedule (carried from the 2026-11-10 PRD). Recommendation: Wide and One-legged for Standard push-up, Decline for Pike; the captain supplies the list and art.
2. Movement counts rise to 10 at 45 minutes and 11 at 60 (11 and 12 with Abs), against the 2026-11-10 goal of 8 and 9 that answered user reports of crowded long sessions. Confirm the higher counts are intended, or keep 45/60 main movements at 3/4 and change only 10-30 minutes.

## Documentation changes (applied when each part lands)

### CONTEXT.md - updated terms
- **Training Day**: main slots by length 1 (5), 2 (10-15), 3 (20-30), 4 (45), 5 (60); a Push or Pull Day's fifth slot is a Variation.
- **Core Sprinkle**: one core movement at 15-30 minutes and two at 45-60, plus one with Abs.
- **Variation** (no longer "planned"): fills a 60-minute Push or Pull Day's fifth slot once its Trainer art exists, rotating among a rung's Variations.
- **Pillar** (mobility bookends): every bookend stretch complements the day's group.
- **Coach**: answers general health and fitness questions; adult diet guidance per decision 10; redirects per decision 11.
- **Account**: a user can sign out; signing out erases the phone's copy and keeps the server's.

### New ADRs
- 0018 Session sizing by length and day-matched bookends (amends ADR-0013's movement counts and US-M02's prefer-then-fill).
- 0019 The Coach answers general health and fitness questions (amends ADR-0017's diet scope; keeps the server-side age rail).

## Verification (when parts are implemented)

- Part A: fit harness, invariant guard and bookend tests green; simulator walk of each Training Day at 5/10/20/45/60 min, with and without Abs.
- Part B: evaluation turns pass on the Convex development deployment; 16-year-old and adult accounts walked.
- Part C: simulator walk of sign-out online, sign-out offline with a pending workout, sign back in, and a second account on the same phone.
