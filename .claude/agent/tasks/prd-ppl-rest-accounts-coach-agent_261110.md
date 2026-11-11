# PRD: Push/Pull/Legs Training Days, Rest Days, Accounts and the Coach Agent (2026-11-10)

- Status: **Approved for documentation (2026-11-10); M1 implemented (2026-11-10); M2 implemented (2026-11-10); M3 implemented against the development Clerk instance and Convex deployment (2026-11-11), its device exit criteria and release steps pending (`artifacts/reports/accounts-m3/validation.md`); M4 not started.**
  Every decision below was settled with the captain in a design grill on 2026-11-09 and 2026-11-10.
  The captain approved this PRD and its documentation changes on 2026-11-10.
  No implementation is authorized until the captain approves a milestone.
- Story prefixes: `US-TD##` (M1 Training Days), `US-HO##` (M2 Home, Focus Areas and Outside Activity), `US-AU##` (M3 Accounts), `US-CA##` (M4 Coach Agent).
- Related decisions (new): ADR-0012 to ADR-0017 (see "Documentation changes").
- Supersedes, on landing: [ADR-0004](../../../docs/adr/0004-round-cap-wide-circuit.md) (wide circuit); the primal block of US-E02; the Coach PRD non-goal "no server-side accounts" (`prd-phase-2-strength-coach-analytics_260825.md`); the Cloudflare/App Attest Coach authentication design (`docs/coach-runtime-authentication.md`); CloudKit as the sync store.
- Amends, on landing: [ADR-0001](../../../docs/adr/0001-strength-primary-sessions.md) (primal no longer a pillar), [ADR-0003](../../../docs/adr/0003-even-round-circuit-timing.md) (rest rail and tolerance), [ADR-0005](../../../docs/adr/0005-two-writer-policy-safety.md) (coach levers mostly inert under a fixed rotation), [ADR-0006](../../../docs/adr/0006-foundations-push-pull-legs-core.md) (clearing bar), [ADR-0007](../../../docs/adr/0007-staple-movements-for-beginner-and-intermediate.md) (Practice exception).

## Introduction / Overview

Users report that 45 and 60 minute sessions have too many exercises: today a 45-minute session serves about 11-14 distinct movements and a 60-minute one about 12-18, because ADR-0004 fills long sessions by going wider.
They want something simpler for home and hotel rooms: fewer movements, more reps, and real recovery.
The engine also has no notion of a split or a day off; every day works every pattern, chosen by staleness.

This PRD reshapes the program into a fixed **Push -> Pull -> Legs** rotation with an automatic **Rest Day** after each cycle, a simple set grammar (always 4 sets, reps in steps of 5), and a small, fixed number of movements per session.
It adds a launch **Welcome Page**, body-part **Focus Areas**, and logging of **Outside Activities** (a run, a swim) that shift tomorrow's Training Day.
It then moves users onto real **Accounts** (Clerk sign-in, Convex as the local-first source of truth) so the premium **Coach** can become an agent with memory that writes **Custom Workouts**, gives adult-only general diet guidance, and sets reminders, in its own tab.

The work ships as four milestones, in order: M1 Training Days -> M2 Home, Focus Areas and Outside Activity -> M3 Accounts -> M4 Coach Agent.

## Goals

- A 45-minute session serves at most 8 movements (2 warm-up, 3 main, 1 core, 2 cooldown) and a 60-minute session at most 9, plus one more core movement when Abs is a Focus Area, down from 11-18 today.
- Every training station is exactly 4 sets with reps in multiples of 5.
- A session never mixes Push, Pull and Legs work.
- A Rest Day follows every completed cycle, and rest never lowers the Consistency Score.
- An Outside Activity gives the muscle group it worked at least one day off.
- Every served engine movement has custom Trainer art.
- Users sign in once, their data survives a phone change, and the app keeps working offline.
- Premium users get a Coach that remembers them, acts on their behalf, and writes workouts they approve.

## Interview decisions and where this PRD carries them

| # | Decision (captain's answer) | Carried by |
| --- | --- | --- |
| 1 | Training Days rotate **Push -> Pull -> Legs** in a fixed order and advance only on completed sessions; a missed day never skips a group. | US-TD04 |
| 2 | Strict separation: a Push Day never contains Pull or Legs work (and so on); only the Core Sprinkle and the warm-up/cooldown cross days. | US-TD04 |
| 3 | Each Training Day adds one **Core Sprinkle**, rotating across core ladders from cycle to cycle. Core never gets its own day. | US-TD04 |
| 4 | Progression wins over variety: each ladder contributes its current rung, unchanged until earned. | US-TD04 |
| 5 | Remove only movements with no Trainer art (`pull_ytw`); keep single-pose `pull_wall_scapular_pull` and `pull_reverse_snow_angel` and commission their end poses. | US-TD01; captain art task |
| 6 | **Primal retired** as a training family for home/hotel simplicity (crawls need floor space). Bear Hold stays on the core ladder. | US-TD01; ADR-0014 |
| 7 | Bookends: warm-up at most 2 movements, cooldown at most 2. | US-TD04 |
| 8 | Main movements by length: 5-10 min 1, 15-20 min 1, 30 min 2, 45 min 3, 60 min 4; plus 1 Core Sprinkle (none at 5-10 min). | US-TD04 |
| 9 | Push and Pull have two ladders each; slots 3 and 4 are **Practice Movements**: the next harder rung at low reps (4x10; per side 4x5; holds 15s). Practice never advances the ladder. | US-TD02, US-TD04 |
| 10 | Practice bypasses the staple gate but never injury exclusions, Strength-Phase locks, or withdrawn movements. With no harder rung, the rung below is used at volume reps; with neither, the session has fewer movements. | US-TD04; ADR-0015 |
| 11 | Legs Days use the current rungs of the squat, lunge, bridge and hip ladders. | US-TD04 |
| 12 | **Variations** (same-rung alternatives such as Wide or One-legged push-ups) join long sessions as extra stations once their Trainer art exists, pinned to the parent rung, never advancing it. | Future story after art; Open Question 1 |
| 13 | Every main and core station is **exactly 4 sets** at every length. | US-TD03, US-TD04 |
| 14 | Reps are always multiples of 5: 15-30 (beginner/intermediate), 15-50 (advanced); per side 5/10/15; holds in 5-second steps. | US-TD03 |
| 15 | Advancement needs 4 clean sets at the top of the range at earned reps, not rated too hard. | US-TD03 |
| 16 | Reps are the fit lever: short sessions go below Earned Reps (floor 10, per side 5); long sessions **Pad** above them up to the level's top. Padding never moves the Rep Ramp or a rung. | US-TD02, US-TD03, US-TD04 |
| 17 | Rest after a round is at most 60s on sessions of 30 min or less. On 45/60 min sessions the pause between movements grows from 15s up to 60s and the rest after a round grows up to a level cap: beginner 2:00, intermediate 1:30, advanced 1:00. If a session still cannot fill, it runs short and Today shows the honest time. Tolerance about +/-3 min. | US-TD00, US-TD04 |
| 18 | A **Rest Day** follows every completed cycle. Any session-free day after Legs satisfies it. Today shows a Rest Day card with an optional mobility-only Recovery flow and "Train anyway", which forfeits the rest. Rest never dents the Consistency Score. | US-TD05 |
| 19 | A tap-through **Welcome Page** on every cold launch, before Today: greeting, today's Training Day or Rest Day, the cycle strip, "Let's go". It replaces the launch spinner. | US-HO01 |
| 20 | **Focus Areas** replace the unused goal list: multi-select Chest, Shoulders, Arms, Back, Abs, Legs, Glutes; asked in onboarding, editable in Settings. A focused body part is ordered first, padded first and given the Practice slot first on its day; Abs adds a second Core Sprinkle. The rotation never changes. | US-HO02, US-HO03 |
| 21 | **Outside Activity** types map to groups (run/bike/hike -> Legs; swim/row/climb -> Pull; other -> none). The group it hit gets at least one day off: it swaps behind the next group, or, if it is the last group in the cycle, the Rest Day comes early. It counts as showing up and never completes a group. | US-TD04 (rotation input), US-HO04 |
| 22 | Outside Activities are entered by hand from Today, plus opt-in Apple Health read that surfaces "Add it / Ignore" suggestions, never applied automatically. | US-HO04, US-HO05 |
| 23 | **Required Clerk sign-in** (Apple, Google, email) at the end of onboarding ("Save your plan"). Existing users sign in once on next launch and their history uploads automatically. Today's optional Sign in with Apple step is removed. | US-AU02, US-AU04 |
| 24 | **Convex is the server source of truth**, replacing CloudKit; the app is **local-first**: sessions generate, play and log offline and sync later. The Coach needs connectivity. | US-AU01, US-AU03 |
| 25 | The **Coach runs as Convex actions**, authenticated by Clerk; premium comes from a per-user entitlement kept current by App Store Server Notifications. The Cloudflare Coach route and per-request App Attest/receipt checks are retired. | US-CA01, US-CA02 |
| 26 | The Coach becomes an **agent** (premium): persistent memory and tools to log an Outside Activity, rest or train anyway, change today's length, swap a movement, set Focus Areas, and schedule reminders. | US-CA03 |
| 27 | **Custom Workouts**: the AI writes them freely from the user's workout history, status and injury history; the user reviews, edits and accepts before playing. Any movement is allowed: catalog ones show Trainer art, others show text only and are not tracked. A played Custom Workout counts like an Outside Activity. | US-CA04, US-CA05 |
| 28 | The Coach becomes the **4th tab** (Today / Coach / Progress / Profile) with persistent history, quick-action chips and inline Custom Workout cards. Free users see a preview and the paywall. | US-CA06 |
| 29 | **Diet**: general guidance (protein, hydration, low carb, low sugar, vegetables) for adults only; no diet topics for users under 18; never medical advice. | US-CA07 |
| 30 | **Reminders**: the Coach schedules on-device notifications from chat; they are listed and editable in Settings; copy is identity-framed, never guilt or streak framed. | US-CA08 |
| 31 | Ship order: M1 -> M2 -> M3 -> M4. | Milestones |

Defaults chosen during planning, confirmed by the captain on 2026-11-10 (Open Question 2, reconciliations in ADR-0013): Legs at 30/45 min fills one squat-side and one hinge-side ladder first, least recently worked; holds range 20-60s (advanced to 90s) and advance at 4 sets at the top; Earned Reps climb one 5-step per non-too-hard session where prescribed reps were at or above earned; Recovery does not count as a session for the score or the rotation; Return sessions scale prescribed reps (rounded to 5), not Earned Reps; existing users start at Push after the update.

## Verified facts on current main (2026-11-10)

> **Stale on arrival (noted at M1 implementation):** these facts were read from a checkout behind `origin/main`.
> By then `main` had already shipped hands-free sessions with 15-second rests and stretched work windows (ADR-0010), round rep numbers with a three-session climb (ADR-0011), and the withdrawal of `pull_ytw` (72 served).
> ADR numbers 0009-0011 were taken, so this PRD's ADRs are 0012-0017.
> How M1 reconciles with ADR-0010 and ADR-0011 is recorded in ADR-0013.

- Session engine: `ios/RepToday/RepToday/Services/Engine/SessionAssembly.swift` builds Warm-Up -> Strength (-> Primal at 41-60 min) -> Cooldown; the lead pattern is the stalest (`MovementPatternFocus.swift`); long sessions widen via further-chain accessories (ADR-0004); round rails 2-4 (:99-100); round rest 30-75s (:78-79); +/-60s tolerance (:67).
- Rest: no rest-day concept; `Consistency.weeklyGoal` is hardcoded to 3 (`ViewModels/OnboardingViewModel.swift:331`); a 7+ day gap triggers a Return session (`ReturnOverride.swift`).
- Catalog: 76 movements (43 strength, 26 mobility, 7 primal), 73 served. Trainer art: 70 full pairs, 2 single poses, `pull_ytw` none.
- Goals: `PrimaryGoal` (`Models/Enums.swift:155`) is never asked and never read by the engine.
- Navigation: tabs Today (`ReadyView`) / Progress / Profile; the Coach is a page pushed from Profile; a spinner shows during the launch check (`Views/RootView.swift:22-29`).
- Identity: no server accounts; Core Data + CloudKit; optional Sign in with Apple; Convex holds anonymous telemetry only (`convex/schema.ts`: `events`, `rateLimits`). (Superseded by M3: see ADR-0016.)
- Coach: stateless per turn; OpenAI via a Cloudflare Worker (`proxy/src/worker.js`); App Attest + StoreKit receipt per request; the LLM takes no actions.
- HealthKit: write-only (`Services/Health/HealthKitService.swift:49`).

## Milestones

### M1 - Training Days (engine)

Outcome: users get Push/Pull/Legs days with fewer movements, 4 sets of 5-step reps, real rest, and Rest Days.
Exit criteria: all M1 stories pass; the fit harness shows every length x level x day fills within tolerance or reports an honest shortfall; a full 45-minute session plays end to end in the simulator with Trainer art on every movement.

#### US-TD00: Fit-feasibility harness
**Description:** As the team, we want a test that prices every length x level x Training Day so timing regressions are caught before users see them.
**Acceptance Criteria:**
- [x] Test-only harness over 7 lengths x 3 levels x 3 Training Days using `SessionAssembly.workSecondsPerSet` and the real catalog.
- [x] Reports planned minutes vs requested; asserts decision 17 (fill within ~+/-3 min or flagged honest shortfall).
- [x] Runs in CI on both iOS lanes.

#### US-TD01: Retire primal and withdraw `pull_ytw`
**Description:** As a home or hotel user, I want no crawling movements and no movement without a picture.
**Acceptance Criteria:**
- [x] New `MovementAudience.retired`; all locomotion movements retired; `pull_ytw` withdrawn; `MovementAccess.isWithdrawn` covers both.
- [x] Catalog loader accepts a withdrawn rung at the top of a chain (`pull_reverse_snow_angel` -> `pull_ytw`).
- [x] Primal block and its machinery deleted from `SessionAssembly`; old logs and paused sessions with primal still decode.
- [x] Served catalog count is 68; affected tests updated.

#### US-TD02: Station role and earned level on every prescription and log
**Description:** As the engine, I need to know which reps were earned and which stations were Practice so Padding and Practice never advance progression.
**Acceptance Criteria:**
- [x] `PrescribedExercise` and `LoggedExercise` gain optional `role` (main / practice / core), `earnedReps`, `earnedDurationSeconds`; old JSON decodes unchanged.
- [x] One predicate decides what counts for progression (not skipped, not Practice), used by chain frontier, Adaptive Overload capacity, plateau diagnosis, progress analytics and foundation clearing.
- [x] `CompletedSet` unchanged (US-CC09 guard stays green).
- [x] New test: a Practice station never moves a rung or the Rep Ramp.

#### US-TD03: 5-step rep grammar and the new advancement bar
**Description:** As a user, I want simple, round rep targets and a clear bar for moving up.
**Acceptance Criteria:**
- [x] One owner of ranges and steps (decision 14) and short-session floors (decision 16).
- [x] Earned Reps stored unrounded, served floored to a multiple of 5; climb and back-off per the planning default.
- [x] Advancement per decision 15; `advancementCriteria` text rewritten in `Exercises.json`.
- [x] Interim: sets fixed at 4, round rest capped at 60s; app ships and plays correctly.

#### US-TD04: Training Day rotation and the slot-plan engine
**Description:** As a user, I want each day to train one group with a few movements done well.
**Acceptance Criteria:**
- [x] Pure, date-injected rotation: Training Day of a log; today's plan (train day X or rest) from logs plus a list of Outside Activities (empty until M2), including the deferral rules of decision 21; core-ladder rotation.
- [x] Session = up to 2 warm-up + main slots per decision 8 + Core Sprinkle + up to 2 cooldown; slot order per decisions 9-11.
- [x] Fit per decisions 16-17; tolerance about 3 minutes; wide-circuit accessories, round rails and reserve promotion deleted.
- [x] Swap keeps the slot's role.
- [x] Invariant guard: every main/core station has 4 sets, every rep target is a multiple of 5, no session mixes groups, no primal, no `pull_ytw`.
- [x] Existing tests rewritten or retired as listed in Technical Considerations.

#### US-TD05: Rest Day on Today
**Description:** As a user, I want the app to tell me when to rest and let me recover or train anyway.
**Acceptance Criteria:**
- [x] Today shows a Rest Day card after a completed cycle (decision 18).
- [x] "Recovery" starts a short mobility-only flow that neither advances the rotation nor counts as a session.
- [x] "Train anyway" starts the next group.
- [x] Test pins that rest days never lower the Consistency Score.
- [x] Verify in the simulator, light and dark, largest Dynamic Type.

### M2 - Welcome Page, Focus Areas and Outside Activity

Outcome: a warm launch moment, personal emphasis, and outside workouts that shape tomorrow.
Exit criteria: all M2 stories pass and are verified in the simulator.

#### US-HO01: Welcome Page
**Description:** As a user, I want a welcome moment that tells me what today is before I land on Today.
**Acceptance Criteria:**
- [x] Shown on every cold launch after onboarding, never on resume from background.
- [x] Shows greeting with name, today's Training Day or Rest Day, the cycle strip, and "Let's go".
- [x] Replaces the launch spinner; loading happens behind it.
- [x] Verify in the simulator, light and dark, Dynamic Type, Reduce Motion.

#### US-HO02: Focus Areas in onboarding and Settings
**Description:** As a user, I want to pick the body parts I want to improve.
**Acceptance Criteria:**
- [x] `PrimaryGoal` replaced by Focus Areas (decision 20), multi-select, optional.
- [x] New onboarding step and a Settings editor.
- [x] Persists locally (and to Convex after M3).

#### US-HO03: Focus Areas shape Training Days
**Description:** As a user, I want my focus areas to get a bit more attention on their days.
**Acceptance Criteria:**
- [x] Mapping per decision 20 (Chest -> horizontal push, Shoulders -> vertical push, Arms -> diamond/dips and rows, Back -> pull, Abs -> core, Legs -> squat and lunge, Glutes -> bridge and hinge).
- [x] Focused movements ordered first, padded first, Practice slot first; Abs adds a second Core Sprinkle.
- [x] Rotation unchanged; fit harness still green.

#### US-HO04: Log an Outside Activity
**Description:** As a user who ran three miles, I want to log it so tomorrow doesn't hit my legs again.
**Acceptance Criteria:**
- [x] "Log outside activity" on Today: type, duration, optional distance.
- [x] Rotation applies decision 21; Today and the Welcome Page reflect the change immediately.
- [x] Counts as showing up for the Consistency Score; never completes a group.
- [x] Edit and delete a logged activity.

#### US-HO05: Apple Health suggestions
**Description:** As a user with an Apple Watch, I want my recorded workouts suggested so I don't retype them.
**Acceptance Criteria:**
- [x] Opt-in Health read permission for workouts, with clear copy.
- [x] New Health workouts appear on Today as "Add it / Ignore"; nothing is applied without a tap.
- [x] Rep Today's own written workouts are never suggested back.

### M3 - Accounts (Clerk + Convex, local-first)

Outcome: every user has an account; data lives on the phone first and syncs to Convex; CloudKit is gone.
Exit criteria: fresh install, existing-user migration, offline use and account deletion all verified on a device.

#### US-AU01: Convex data model and Clerk auth
**Acceptance Criteria:**
- [x] Convex tables for users, profiles, workout logs, outside activities, session policies, focus areas, custom workouts and coach memory, keyed to the Clerk user; existing `events`/`rateLimits` untouched. (Custom workouts and coach memory are owned, empty tables M4 fills.)
- [x] Clerk configured as the Convex auth provider; every function checks the caller owns the data.

#### US-AU02: Sign-in at the end of onboarding
**Acceptance Criteria:**
- [x] "Save your plan" step after onboarding answers: Apple, Google, email via Clerk; required to continue. (Signing in to an account that already holds a plan brings it back instead of creating one. Apple and Google verify on a device only.)
- [x] Optional Sign in with Apple step removed from the welcome step.

#### US-AU03: Local-first sync
**Acceptance Criteria:**
- [x] Core Data remains the on-device store; changes queue and sync to Convex when online; idempotent by record id.
- [x] Sessions generate, play and log fully offline.
- [ ] CloudKit container and sync removed. (Deferred, captain-accepted: the iCloud mirror stays on only for a user who onboarded before accounts and whose history has not finished uploading; no new user ever mirrors iCloud, and the mirror stops once the move has queued everything. Removing the CloudKit container (`NSPersistentCloudKitContainer`), the iCloud container entitlement and the `remote-notification` background mode moves to a later build, once the upload window has passed; ADR-0016.)

#### US-AU04: Existing-user migration
**Acceptance Criteria:**
- [x] One-time required sign-in on next launch for users onboarded before M3.
- [x] On-device and iCloud history uploads automatically; re-running is safe; nothing is lost if interrupted.

#### US-AU05: Account deletion and privacy
**Acceptance Criteria:**
- [x] Delete account removes Convex data and the Clerk user, and wipes local data. (It also deletes the legacy iCloud copy - the Core Data CloudKit zone in the user's private database - while the container exists; when iCloud is unavailable that deletion is owed and retried on a later launch.)
- [x] Privacy policy and App Store privacy labels updated before release. (The policy source `gtm/03-site/privacy.html` and the label declarations in `artifacts/reports/accounts-m3/validation.md` are updated; publishing the site and entering the labels in App Store Connect are release steps.)

### M4 - Coach Agent

Outcome: premium users get a Coach tab with an agent that remembers, acts, writes Custom Workouts, guides diet for adults and sets reminders.
Exit criteria: all M4 stories pass against a Convex dev deployment and on a device with a sandbox subscription.

#### US-CA01: Coach on Convex
**Acceptance Criteria:**
- [ ] Coach turn runs as a Convex action, authenticated by Clerk, reading the user's history, status, injury history and conversation memory server-side.
- [ ] Cloudflare Coach route and `CoachRuntimeAuthentication` retired; the variety-language route is evaluated separately.

#### US-CA02: Per-user premium entitlement
**Acceptance Criteria:**
- [ ] App Store Server Notifications keep a per-user entitlement in Convex; the Coach checks it on every turn.
- [ ] Restore purchases links an existing subscription to the account.

#### US-CA03: Agent tools and memory
**Acceptance Criteria:**
- [ ] Conversation history persists and is sent as context.
- [ ] Tools: log Outside Activity, rest today or train anyway, change today's length, swap a movement, set Focus Areas, schedule a reminder; every action shows a confirmation with Undo.
- [ ] Safety-owned engine moves (de-load, Return, cold start) stay out of reach (ADR-0005).

#### US-CA04: Generate a Custom Workout
**Acceptance Criteria:**
- [ ] The Coach writes a workout from history, status and injury history (decision 27).
- [ ] It appears as a proposal card; nothing plays until accepted.
- [ ] Catalog movements resolve to their Trainer art; others are text-only steps.

#### US-CA05: Review, edit and play a Custom Workout
**Acceptance Criteria:**
- [ ] Edit before accepting: swap, remove, reorder, change reps or time.
- [ ] Plays in the hands-free player; logged as a Custom Workout that counts like an Outside Activity (decision 27).

#### US-CA06: Coach tab
**Acceptance Criteria:**
- [ ] Fourth tab (Today / Coach / Progress / Profile); full-screen chat, persistent history, quick-action chips, inline Custom Workout cards.
- [ ] Free users see a preview and the paywall; the Coach row leaves Profile.
- [ ] Verify in the simulator, light and dark, Dynamic Type, VoiceOver.

#### US-CA07: Diet guidance with an age rail
**Acceptance Criteria:**
- [ ] General guidance only (decision 29) for users 18 and over; declines diet topics for users under 18; never medical advice.
- [ ] Coach data disclosure updated to cover workout history and injury history.

#### US-CA08: Coach reminders
**Acceptance Criteria:**
- [ ] Coach schedules on-device notifications from chat; listed, editable and deletable in Settings.
- [ ] Copy is identity-framed; no guilt or streak framing.

## Functional Requirements

- FR-1: The rotation is Push -> Pull -> Legs and advances only on a completed Training Day session.
- FR-2: A session contains movements from exactly one group plus at most two Core Sprinkles and the bookends.
- FR-3: Main movement count follows decision 8; warm-up and cooldown each hold at most 2 movements.
- FR-4: Every main and core station has 4 sets; every rep target is a multiple of 5; per-side and hold rules follow decision 14.
- FR-5: Padding and Practice never change Earned Reps, a rung, or foundation clearing.
- FR-6: Rest and transition caps follow decision 17.
- FR-7: A Rest Day follows each completed cycle; rest never lowers the Consistency Score.
- FR-8: An Outside Activity or Custom Workout gives its group at least one day off and never completes a group.
- FR-9: No engine session serves a movement without Trainer art.
- FR-10: The app generates, plays and logs sessions with no connectivity.
- FR-11: The Coach never plays a workout the user has not accepted.
- FR-12: Users under 18 receive no diet guidance.

## Non-Goals (Out of Scope)

- Equipment-based movements (zero-equipment rule stands).
- A weekday-picker schedule (rest is automatic per cycle).
- Server push notifications or a messaging-app bot.
- Android or web clients (M3 enables them; not built here).
- Calorie or macro targets, meal plans, weight-loss plans.
- Variation art production (captain content task; Open Question 1).
- Changing the Coach's LLM provider (decided in M4 kickoff if needed).

## Design Considerations

- Every new screen (Welcome Page, Rest Day card, Outside Activity entry, Health suggestion card, Focus Areas, Save your plan, Coach tab, Custom Workout card and editor) uses `DesignSystem/Theme.swift` tokens and is checked in light and dark, largest Dynamic Type, VoiceOver, and a 375x667 screen.
- Copy stays discipline-first: identity framing, no streaks, no guilt.

## Technical Considerations

- Engine code: `SessionAssembly.swift`, `AdaptiveOverload.swift`, `ProgressionChainSelection.swift`, `MovementAccess.swift`, `MockExerciseService.swift`, `Exercises.json`, `Models/Workout.swift`, `Models/WorkoutLog.swift`, new `RepGrammar.swift` and `TrainingRotation.swift`.
- Tests to rewrite or retire in M1: `SessionAssemblyTests`, `UniformSessionShapeTests`, `StrengthPrimaryRegressionTests`, `BookendComplementSelectionTests`, `PatternEmphasisPolicyTests`, `FirstWeekContrastTests`, `AdaptiveOverloadTests`, `ProgressionChainSelectionTests`, `PhaseEvaluatorTests`, `PlateauDiagnosisTests`, `StapleMovementsTests`, `ExerciseLibraryTests`, `ExerciseServiceTests`, pace and bookend evidence tests; delete `RoundCapWideCircuitsTests`, `RoundCapInvariantGuardTests`, `AccessoryProgressionParityTests`, `AccessoryDepthMismatchTests`; narrow `SitsLongBookendBiasTests` to "same movements, same earned level".
- Foundation clearing gets harder (ADR-0006 amendment); Discipline users' cleared counts may drop on update, so show a one-time note.
- M3 removes CloudKit; the migration must be idempotent and resumable.
- M4 sends workout and injury history to the LLM provider; the disclosure and privacy policy must say so before release.

## Success Metrics

- Distinct movements per 45/60 minute session at or below 8/9 (9/10 with Abs focus).
- 45/60 minute session completion rate up versus the pre-M1 baseline (funnel telemetry).
- Share of weeks with at least one Rest Day honored.
- Outside Activities logged per active user per week.
- Coach tab premium conversion and Custom Workouts accepted per premium user.

## Open Questions

1. Variation list per rung (Push and Pull first) and its Trainer art schedule. Recommendation: Wide and One-legged for Standard push-up; Decline for Pike; captain supplies the list.
2. ~~Confirm the planning defaults listed under the decisions table at M1 kickoff.~~ Resolved 2026-11-10: the captain confirmed the defaults as implemented, with the reconciliations recorded in ADR-0013.
3. M4 LLM provider and model for an agent with tools. Recommendation: decide at M4 kickoff with a short evaluation.

## Documentation changes (applied 2026-11-10)

### CONTEXT.md - new terms
- **Training Day** - a session for one group: Push Day, Pull Day, or Legs Day (squat and hinge). It never mixes groups; its only extras are the Core Sprinkle and the bookends.
- **Rotation / Cycle** - Training Days run Push -> Pull -> Legs and advance only when a session is completed. One pass is a Cycle.
- **Rest Day** - the planned day off after every completed Cycle. Any session-free day after Legs counts; "train anyway" forfeits it. It never lowers the Consistency Score.
- **Core Sprinkle** - the one core movement on every Training Day (two when Abs is a Focus Area), rotating across core ladders.
- **Practice Movement** - the next harder rung, prescribed at low reps beside the current rung on longer sessions. It never advances progression and may sit above the user's staple level.
- **Variation** - a same-difficulty alternative to a rung that joins longer sessions once its Trainer art exists. It unlocks with its parent rung and never advances the ladder.
- **Earned Reps / Rep Ramp** - the per-movement rep count earned through rated sessions, always a multiple of 5.
- **Padding** - reps above Earned Reps prescribed only to fill a longer session. They count as done but never move the Rep Ramp or a rung.
- **Outside Activity** - a workout done outside Rep Today, logged by hand or confirmed from Apple Health. It counts as showing up and gives the group it worked at least a day off.
- **Custom Workout** - a Coach-written workout the user reviews, edits and accepts before playing. It counts like an Outside Activity.
- **Focus Area** - a body part the user wants to improve. It changes emphasis within Training Days, never the Rotation.
- **Welcome Page** - the tap-through page on every cold launch before Today.
- **Account** - the user's required sign-in identity; data lives on the device first and syncs to Rep Today's server.

### CONTEXT.md - updated or retired terms
- **Pillar**: primal retired.
- **Wide Circuit**: retired.
- **Continuous Circuit**: 4 rounds per station; level-capped rest on 45/60 min sessions.
- **Staple movement**: Practice exception.
- **Coach**: agent with memory, tools, Custom Workouts, adult diet guidance and reminders.
- **Two-Writer Policy Safety**: Custom Workouts are a separate, user-accepted artifact, not a policy write.

### New ADRs
- 0012 Push/Pull/Legs rotation with automatic Rest Day.
- 0013 Fixed 4 sets, 5-step reps, reps as the fit lever with Padding, fixed movement counts, level-capped rest (supersedes ADR-0004; amends ADR-0003).
- 0014 Retire the primal pillar (amends ADR-0001).
- 0015 Practice Movement bypasses the staple gate (amends ADR-0007).
- 0016 Clerk accounts with Convex as local-first source of truth (reverses the Coach PRD non-goal; replaces CloudKit).
- 0017 Coach as a Convex-hosted agent with user-accepted Custom Workouts (supersedes the Cloudflare/App Attest design; relates to ADR-0005).

## Verification (when milestones are implemented)

- M1: fit harness + invariant guard + rotation tests green on both CI lanes; simulator walk of each Training Day and a Rest Day at 15/30/45/60 min; pixel check of Today and the player in light/dark and Dynamic Type.
- M2: simulator walk of Welcome Page, Focus Areas onboarding/Settings, manual Outside Activity changing tomorrow, Health suggestion with a seeded Health workout.
- M3: fresh install, seeded existing-user migration, airplane-mode session then sync, account deletion on a device.
- M4: Coach turn with each tool on a Convex dev deployment; Custom Workout propose -> edit -> accept -> play; under-18 diet decline; reminder fires; sandbox subscription gate.
