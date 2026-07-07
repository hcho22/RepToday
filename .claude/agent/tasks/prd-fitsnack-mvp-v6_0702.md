# PRD: FitSnack v6 MVP - The Discipline Loop with a Daily-Adaptive AI Programmer

**Source plan:** `.claude/agent/tasks/FitSnack-PRD-v6_070226.md` (strategic PRD v6.0, reconciled to ADRs 0001-0019).
**Build approach:** Story-by-story against this document; each user story is one focused session with acceptance criteria and a Validation Test.
**Scope:** Comprehensive standalone v6 MVP. Covers the net-new v6 work (Session Policy, AI Programmer at option C, cold-start, Ready Screen, Return / Re-entry Ramp, engine 5-60 min and first-class primal, thin proxy) plus the still-unbuilt v5 epics (Consistency/Phase, onboarding, active/post/progress, Apple integrations) reframed under v6.
**Supersedes:** `.claude/agent/tasks/prd-fitsnack-mvp_0626.md` (the v5 implementation PRD). Its Epics A-C are already built and are carried forward here as done; its Epics D-J are re-expressed under v6 below.
**Persistence:** CoreData backed by `NSPersistentCloudKitContainer`; domain models are `Codable` structs; nested fields stored as JSON-encoded `Data`.
**Platform:** iOS 17+, SwiftUI, Swift 5.9, Xcode 16.3. Bundle ID `com.fitsnack.app`.
**Status:** Epics A-C built (`[x]`); Epic D complete (US-D01-D04 done); Epic E complete (US-E01-E06 done); Epic F in progress (US-F01 done); Epics G-N not started (`[ ]`).

---

## Introduction

FitSnack is a discipline-first micro-workout iOS app for busy, desk-bound adults who can give exercise a few minutes a day.
It exists to build one thing: the discipline of showing up.
Open the app and a complete zero-equipment session is already waiting, assembled by a deterministic on-device engine that blends bodyweight strength, mobility, and primal movement.
There is no browsing, no choosing, no thinking, and no question to answer before you start.
Sessions run anywhere from 5 to 60 minutes, and the app arrives pre-set to the length you actually complete.

v6 introduces the wedge that separates FitSnack from every strength-led competitor: a daily-adaptive AI that builds discipline.
Behind the scenes an asynchronous, off-device AI Programmer reviews each user's logged history and rewrites a per-user Session Policy - the progression rate, pillar weighting, and variety windows the engine runs on.
The AI never generates a workout and is never on the path between opening the app and starting one; it shapes the program, not the session.
The MVP ships this Programmer at option (C): the re-weighting runs as deterministic heuristics on-device with zero LLM calls, and its user-visible note is templated.
The single LLM call pulled into the MVP is the day-one Variety Language slice, always backed by a deterministic template so the app never depends on the network, even on day one.

The product is built on the two-phase journey carried from v5.
New users live in the Discipline Phase, where the only goal is consistency and sessions stay short and simple.
A user earns the Strength Phase by sustaining the habit and progressing their movements; at launch no user has earned it, so the MVP ships the Discipline-Phase experience with the `PhaseEvaluator` already in place.
Discipline overrides optimization by design: a Return after a gap is served easy, winnable, and celebrated regardless of detraining, and readjustment for lost time happens across the following Re-entry Ramp, never in the Return itself.

## Goals

- Ship the Ready Screen: the app opens to a complete, pre-generated session at the user's Default Duration, one tap to start, never gated on "how long do you have?".
- Extend the deterministic engine to the full 5-60 min range and promote primal to a first-class pillar, while preserving the <100ms, fully-offline generation guarantee.
- Introduce the always-valid Session Policy and the on-device AI Programmer at option (C): deterministic plateau diagnosis and cross-signal re-weighting, with a templated note.
- Make discipline override optimization mechanically: Trigger Precedence (Disengagement suppresses Physical Stall), the Return override, and the Re-entry Ramp.
- Seed a safe, vivid cold start: capped Starting Difficulty served gentle, an Asymmetric Ramp, First-Week Contrast, and the network-independent Variety Language slice.
- Deliver the forgiving, Return-protected Consistency Score and the deterministic PhaseEvaluator (Discipline-only at launch).
- Complete the core loop UI (onboarding, Ready Screen, active session, post-session, progress) and the Apple-native integrations, plus the one thin stateless proxy that holds the model API key.

## User Stories

> Stories are grouped into dependency-ordered epics (foundations first, then engine, then policy and AI, then UI, then integrations).
> Epics A-C are already built in the current codebase and are shown here fully checked (`[x]`) as a compact summary; v6 modifies the built engine through Epic E.
> Epics D-N are net-new or reframed under v6 and start fully unchecked (`[ ]`).
>
> **iOS verification note:** this is an iOS app, so every UI-facing story ends its acceptance criteria with "Verify in iOS Simulator" (build and run on an iPhone 16 simulator via `xcodebuild` or Xcode and inspect the screen), replacing the generic browser-verification convention. Pure-logic stories end with "Build and tests pass".
>
> As each story is completed, flip its acceptance-criteria checkboxes `[ ]` to `[x]` so this PRD doubles as a live progress tracker.

---

### Epic A - Project & Data Foundation (BUILT)

> Shipped in the current codebase. Carried forward as done. See `prd-fitsnack-mvp_0626.md` for the full story text.

| Story | Title | Status |
|-------|-------|--------|
| US-A01 | Bootstrap the clean Xcode project (`App/`, `DesignSystem/Theme.swift`, `RootView`, Assets) | `[x]` |
| US-A02 | Define domain enums (`Models/Enums.swift`) | `[x]` |
| US-A03 | Define domain model structs (`Exercise`, `User`, `Workout`, `WorkoutLog`) | `[x]` |
| US-A04 | CoreData stack with CloudKit container (`Persistence/`, `CDUser`, `CDWorkoutLog`) | `[x]` |
| US-A05 | Service protocols, `ServiceContainer`, and `AppState` | `[x]` |

---

### Epic B - Exercise Library (BUILT)

> Shipped. 42 zero-equipment movements. Carried forward as done.

| Story | Title | Status |
|-------|-------|--------|
| US-B01 | Author the bundled exercise library (`Resources/Exercises.json`) | `[x]` |
| US-B02 | Exercise service loads, caches, and validates the library (`MockExerciseService`, `ExerciseLibraryError`) | `[x]` |

---

### Epic C - Deterministic Workout Engine, Steps 1-7 + Swap (BUILT)

> Shipped. Pure Swift, offline, <100ms. Carried forward as done.
> v6 extends this pipeline (5-60 min range, first-class primal, Session Policy consumption, Step 0 cold-start override, Return / Re-entry Ramp) through Epic E - it does not rebuild it.

| Story | Title | Status |
|-------|-------|--------|
| US-C01 | Session-shape selection - Step 1 (`SessionShapeSelection.swift`, 5-30 min) | `[x]` |
| US-C02 | Pillar balance by staleness - Step 2 (`PillarBalance.swift`, strength/mobility) | `[x]` |
| US-C03 | Movement-pattern focus - Step 3 (`MovementPatternFocus.swift`) | `[x]` |
| US-C04 | Exercise pool filtering - Step 4 (`ExercisePoolFilter.swift`) | `[x]` |
| US-C05 | Progression-chain selection - Step 5 (`ProgressionChainSelection.swift`) | `[x]` |
| US-C06 | Adaptive Overload rep/set targets - Step 6 (`AdaptiveOverload.swift`) | `[x]` |
| US-C07 | Assembly and timing fit - Step 7 (`SessionAssembly.swift`) | `[x]` |
| US-C08 | Deterministic exercise swap (`ExerciseSwap.swift`) | `[x]` |

---

### Epic D - v6 Data Model & Session Policy Foundation

> The new v6 domain layer that everything downstream reads. Additive to the built models; preserves the persistence contract pinned by `EnumsTests`, `ModelsTests`, and `PersistenceTests`.

#### US-D01: Extend the User model with `why`, `duration`, and `coldStart`

**Description:** As a developer, I want the v6 user fields so that the engine and AI Programmer can read a user's motivation, learned Default Duration, and cold-start state.

**Acceptance Criteria:**

- [x] `Models/User.swift` adds a nested `Why` struct on `UserProfile` (or `User`): `statement: String` (free text) and `openingBias: Pillar?` (the single allowed programming effect of `why`)
- [x] `Models/User.swift` adds a nested `Duration` struct: `defaultMinutes: Int` (shown on the Ready Screen, set to completed duration), `onboardingSeedMinutes: Int`, `completedDurationEWMA: Double?`
- [x] `Models/User.swift` adds a nested `ColdStart` struct: `sessionsLogged: Int`, `active: Bool`
- [x] The existing `primaryGoal` enum on `UserProfile` is retained unchanged (additive migration; reconciliation with `why` is an Open Question)
- [x] `Persistence/CDUser.swift` and `Persistence/PersistenceCoding.swift` encode/decode the new nested fields as JSON-encoded `Data`, and a user saved without them decodes to sensible defaults (empty `why`, `defaultMinutes == onboardingSeedMinutes`, `coldStart.active == true`, `sessionsLogged == 0`)
- [x] All new structs are `Codable`/`Equatable`; `EnumsTests`/`ModelsTests` extended for round-trip stability; build and tests pass

**Validation Test:**

- **Setup:** US-A03 and US-A04 complete
- **Steps:**
  1. Construct a `User` with `why.statement = "get on the floor with my grandkids"`, `why.openingBias = .mobility`, `duration.onboardingSeedMinutes = 15`, `coldStart.active = true`
  2. Save it via the persistence layer, then fetch it back
- **Expected Result:** The fetched user's `why`, `duration`, and `coldStart` round-trip identically; an older-shaped user record with those fields absent decodes with the documented defaults.
- **Failure Indicator:** A field is lost on round-trip, a missing field crashes decoding, or `primaryGoal` was removed/renamed.

#### US-D02: Extend the WorkoutLog model with `requestedMinutes` and `wasReturn`

**Description:** As a developer, I want the log to record what was offered and whether it was a Return so that Default Duration learning and the Re-entry Ramp have their inputs.

**Acceptance Criteria:**

- [x] `Models/WorkoutLog.swift` adds `requestedMinutes: Int` (what the Ready Screen offered or the user set) and `wasReturn: Bool`
- [x] `durationMinutes` (already present) is documented as the actually-completed duration that feeds `completedDurationEWMA`
- [x] `Persistence/CDWorkoutLog.swift` and `PersistenceCoding.swift` persist both new fields; a legacy log without them decodes to `requestedMinutes == durationMinutes` and `wasReturn == false`
- [x] `ModelsTests`/`PersistenceTests` extended for round-trip stability; build and tests pass

**Validation Test:**

- **Setup:** US-D01 complete
- **Steps:**
  1. Save a `WorkoutLog` with `requestedMinutes = 20`, `durationMinutes = 12`, `wasReturn = true`
  2. Fetch it back
- **Expected Result:** All three fields round-trip; a legacy log missing them decodes with the documented defaults.
- **Failure Indicator:** A field is lost, or a legacy log fails to decode.

#### US-D03: Define the always-valid SessionPolicy

**Description:** As a developer, I want a Session Policy that is valid from day one so that the engine can run offline and before the AI Programmer has ever executed.

**Acceptance Criteria:**

- [x] New `Models/SessionPolicy.swift` defines `SessionPolicy` with: `version: Int`, `updatedAt: Date`, `updatedBy` (`default`/`deterministic`/`llm`), `progressionRate: Double`, `pillarWeighting: [Pillar: Double]`, `varietyWindow: Int`, optional `coldStartContract` (`forceContrastSpread: Bool`, `cappedMaxDifficulty: Int` in 1...5), optional `reentry` (`rampSessionsRemaining: Int`), optional `note` (`text: String`, `source`: `template`/`llm`)
- [x] A `SessionPolicy.default(for:)` (or `static let default`) produces a sensible policy for a fresh user: `progressionRate == 1.0`, equal `pillarWeighting` across `strength`/`mobility`/`primal`, `varietyWindow == 3`, `updatedBy == .default`
- [x] The type is `Codable`/`Equatable` and persists (CoreData or a dedicated store) so the last-written policy survives relaunch and offline use
- [x] Unit tests assert the default policy is valid and deterministic; build and tests pass

**Validation Test:**

- **Setup:** US-D01 complete
- **Steps:**
  1. Build a `SessionPolicy.default` for a fresh user
  2. Encode and decode it
- **Expected Result:** The default policy is fully populated with the documented values, is stable across encode/decode, and equal-weights all three pillars.
- **Failure Indicator:** Any required field is nil/unset, weights are unequal or omit primal, or the round-trip differs.

#### US-D04: Define ReprogramTrigger and the SessionPolicy service seam

**Description:** As a developer, I want a policy service protocol and a trigger type so that the AI Programmer and the engine communicate through one seam that is easy to swap from mock to real.

**Acceptance Criteria:**

- [x] New `ReprogramTrigger` type with `kind` (`weekly_boundary`/`return`/`physical_stall`/`disengagement`) and `detectedAt: Date`
- [x] `Services/Protocols/ServiceProtocols.swift` adds `SessionPolicyServiceProtocol` with `async throws` methods: `currentPolicy(for:) -> SessionPolicy`, `reprogram(user:recentLogs:trigger:) -> SessionPolicy`, and `dueTriggers(user:recentLogs:asOf:) -> [ReprogramTrigger]`
- [x] A `MockSessionPolicyService` returns `SessionPolicy.default` and no due triggers; it is wired into `DI/ServiceContainer.swift` (`ServiceContainer` and `.mock()`)
- [x] `WorkoutEngineProtocol.generateWorkout(...)` gains a `sessionPolicy:` parameter (or the engine reads it via the container); the mock engine still generates correctly
- [x] `ServiceContainerTests` extended to resolve the new service; build and tests pass

**Validation Test:**

- **Setup:** US-D03 complete
- **Steps:**
  1. Resolve `SessionPolicyServiceProtocol` from `ServiceContainer.mock()`
  2. Call `currentPolicy(for:)` and `dueTriggers(...)`
- **Expected Result:** The container resolves the service; `currentPolicy` returns the default policy; `dueTriggers` returns an empty array for a fresh user.
- **Failure Indicator:** The container cannot resolve the service, or the mock throws.

---

### Epic E - Engine v6 Extensions

> Modifies the built Epic C pipeline. Every story preserves the engine's invariants: pure Swift, no network, no LLM, deterministic for a given input, <100ms, Zero-Equipment Floor (`equipment == []`).

#### US-E01: Extend session-shape selection to 5-60 min

**Description:** As a user, I want the engine to shape sessions correctly across 5 to 60 minutes so that I can do anything from a micro-reset to a full session.

**Acceptance Criteria:**

- [x] `Services/Engine/SessionShapeSelection.swift` maps the full 5-60 range using the provisional thresholds: `5-10 -> singleFocus`, `11-20 -> blendLight`, `21-40 -> blendFull`, `41-60 -> blendExtended`
- [x] A new `blendExtended` case is added to `SessionShapeTemplate` and resolves to a `SessionShape` (`single_focus`/`blend`) - `blendExtended` resolves to `.blend`
- [x] `select(requestedMinutes:)` is clamped to 5...60 and remains a pure, deterministic function
- [x] `SessionShapeSelectionTests` covers 5/10/15/20/30/45/60 and the 10/20/40 boundaries; build and tests pass

**Validation Test:**

- **Setup:** US-C01 complete
- **Steps:**
  1. Call `SessionShapeTemplate.select(requestedMinutes:)` for 8, 15, 30, 50
- **Expected Result:** Returns `singleFocus`, `blendLight`, `blendFull`, `blendExtended` respectively; identical inputs always yield identical outputs.
- **Failure Indicator:** A boundary maps to the wrong shape, 60 is rejected, or output varies across calls.

#### US-E02: Promote primal to a first-class pillar

**Description:** As a user, I want primal movement treated as its own pillar so that longer sessions can include a dedicated primal block instead of folding it into strength.

**Acceptance Criteria:**

- [x] `Services/Engine/PillarBalance.swift` reasons about all three pillars: `PillarStaleness` and `PillarPlan`/`PillarWeights` include `primal` (not just `strength`/`mobility`)
- [x] `Services/Engine/SessionAssembly.swift` builds a dedicated primal block for `blendExtended` sessions, driven by the `locomotion` pattern and `pillar == .primal`; shorter shapes may still fold primal in as before
- [x] Primal selection respects staleness and `sessionPolicy.pillarWeighting[.primal]`; the Zero-Equipment Floor and difficulty gating still hold
- [x] `PillarBalanceTests` and `SessionAssemblyTests` extended: a 50-min session produces a distinct primal block; a short session does not regress; build and tests pass

**Validation Test:**

- **Setup:** US-E01 complete; the 3 primal movements exist in the library (`bear_crawl`, `crab_walk`, `ground_to_standing`)
- **Steps:**
  1. Generate a 50-minute session for a user with stale primal history
- **Expected Result:** The assembled workout contains a dedicated primal block (a `WorkoutBlock` whose exercises are `pillar == .primal`) in addition to strength and mobility blocks.
- **Failure Indicator:** Primal never appears as its own block, or a short session breaks.

#### US-E03: Engine consumes the SessionPolicy levers

**Description:** As a user, I want my personalized policy to actually shape sessions so that the AI Programmer's decisions are felt.

**Acceptance Criteria:**

- [x] `SessionAssembly.assemble(...)` accepts a `sessionPolicy:` parameter and threads it through Steps 2, 5, and 6
- [x] `pillarWeighting` scales pillar staleness in Step 2 (`PillarBalance`); a heavier weight on a pillar measurably increases its share of session time
- [x] `progressionRate` scales the Adaptive Overload bump in Step 6 (`AdaptiveOverload.target`); a higher rate advances reps/holds faster, still clamped to the existing safety rails
- [x] `varietyWindow` replaces the hardcoded no-repeat window in Step 5 (`ProgressionChainSelection`, currently `recentSessionWindow = 3`) so it is tunable per user
- [x] With `SessionPolicy.default`, output is identical to pre-policy behavior (no regression); `SessionAssemblyTests`/`AdaptiveOverloadTests`/`ProgressionChainSelectionTests` extended; build and tests pass

**Validation Test:**

- **Setup:** US-D03 and US-E02 complete
- **Steps:**
  1. Generate a 30-min session with `SessionPolicy.default`
  2. Generate again with `pillarWeighting[.mobility]` doubled
- **Expected Result:** The default matches prior behavior; the mobility-weighted policy yields a session with a larger mobility time share.
- **Failure Indicator:** The policy has no effect, or the default policy changes output versus the built engine.

#### US-E04: Step 0 cold-start override and capped Starting Difficulty

**Description:** As a new user, I want my first sessions kept gentle and vivid so that a mis-reported fitness level never produces a badly over-hard day.

**Acceptance Criteria:**

- [x] A Step 0 runs in `SessionAssembly` only while `user.coldStart.active` and `sessionPolicy.coldStartContract != nil`
- [x] When `coldStartContract.forceContrastSpread` is set, the day's pillar/pattern is derived from onboarding inputs but forced to a vivid day-to-day spread across pillars (First-Week Contrast), overriding the single-theme bias that `why`/`sitsLong` alone would produce
- [x] Difficulty is capped at `coldStartContract.cappedMaxDifficulty` and served at the gentle end of the eligible band
- [x] When `coldStart.active` is false, Step 0 is a no-op and the engine behaves exactly as US-E03; determinism preserved
- [x] `SessionAssemblyTests` covers: cold-start caps difficulty; consecutive cold-start days differ in pillar; a warmed-up user is unaffected; build and tests pass

**Validation Test:**

- **Setup:** A brand-new `beginner` user with `coldStart.active == true` and a `coldStartContract` with `forceContrastSpread == true`, `cappedMaxDifficulty == 2`
- **Steps:**
  1. Generate three consecutive first-week sessions (advancing `sessionsLogged` each time)
- **Expected Result:** No prescribed exercise exceeds difficulty 2, and the three days span different pillars rather than repeating one theme.
- **Failure Indicator:** A difficulty-3+ movement appears, or all three days are the same pillar.

#### US-E05: Asymmetric Ramp in Adaptive Overload

**Description:** As a user, I want difficulty to back off fast when a session is too hard but climb only gradually when it is too easy so that I am never overwhelmed and never bored.

**Acceptance Criteria:**

- [x] `Services/Engine/AdaptiveOverload.swift` applies the Asymmetric Ramp: a single recent `too_hard` or a skip pulls the next target down immediately (eager), while `too_easy` nudges up only gradually (patient) - the down-step magnitude is >= the up-step magnitude
- [x] The behavior is expressed as tunable constants (extending the existing `easyStep`/`hardStep`) and stays within the existing rails (`minReps 3`/`maxReps 50`, `minHoldSeconds 10`/`maxHoldSeconds 180`, `minSets 1`/`maxSets 4`)
- [x] The ramp composes with `sessionPolicy.progressionRate` from US-E03
- [x] `AdaptiveOverloadTests` covers: immediate drop on one `too_hard`; gradual rise on `too_easy`; asymmetry (down >= up); rails honored; build and tests pass

**Validation Test:**

- **Setup:** Last log: 3x12 squats marked `too_hard`; a separate history marked `too_easy`
- **Steps:**
  1. Generate the next squat target for each history
- **Expected Result:** The `too_hard` history eases the target immediately and by more than the `too_easy` history raises its target; both stay within the rails.
- **Failure Indicator:** The drop is not immediate, or the up-step is larger than the down-step.

#### US-E06: Return override and Re-entry Ramp

**Description:** As a returning user, I want my first session back to be easy and winnable so that I am never made to feel behind after a gap.

**Acceptance Criteria:**

- [x] A Return is detected when the gap since the last completed session exceeds a threshold (tunable, e.g. >= 7 days); the resulting log records `wasReturn == true` (US-D02)
- [x] On a Return, Step 2 discipline-overrides-optimization: the engine serves an easy, winnable session regardless of staleness or the policy's optimization levers
- [x] After a Return, `sessionPolicy.reentry.rampSessionsRemaining` is set (provisional 3) and Step 6 holds difficulty below normal, walking it back up over those sessions
- [x] The Return itself never carries the readjustment; readjustment lives only in the Re-entry Ramp
- [x] `SessionAssemblyTests`/`AdaptiveOverloadTests` cover: a Return produces a gentler session than the pre-gap norm; the ramp decrements and difficulty climbs back; build and tests pass

**Validation Test:**

- **Setup:** A user with a strong pre-gap history and a 10-day gap
- **Steps:**
  1. Generate the Return session
  2. Generate the next two sessions
- **Expected Result:** The Return is easier than the pre-gap norm; the two following sessions step difficulty back up as `rampSessionsRemaining` decrements.
- **Failure Indicator:** The Return matches or exceeds pre-gap difficulty, or readjustment lands inside the Return.

---

### Epic F - AI Programmer at Option (C)

> On-device, deterministic, zero LLM calls. Writes the Session Policy; never generates a session; never on the critical path of starting one. The user never waits: the app renders from the existing policy immediately and a freshly computed policy applies on the next open.

#### US-F01: Re-program trigger detection with Trigger Precedence

**Description:** As a developer, I want the client to detect when a Re-program is due on app open so that programming updates happen without any server clock.

**Acceptance Criteria:**

- [x] `SessionPolicyServiceProtocol.dueTriggers(user:recentLogs:asOf:)` returns the triggers currently due: `weekly_boundary` (aligned to the Consistency Score week), `return` (post-gap), `physical_stall` (cleared to advance but hasn't), `disengagement` (shrinking or skipped sessions)
- [x] Trigger Precedence is enforced: when `physical_stall` and `disengagement` both apply, `disengagement` wins and `physical_stall` is suppressed
- [x] Detection is pure and deterministic for a given `(user, recentLogs, asOf)`; no wall-clock reads inside the logic (time is passed in)
- [x] Unit tests cover each trigger firing independently and the precedence case; build and tests pass

**Validation Test:**

- **Setup:** A history that simultaneously shows "cleared to advance but hasn't" and "sessions shrinking/skipped"
- **Steps:**
  1. Call `dueTriggers(...)`
- **Expected Result:** The result includes `disengagement` and excludes `physical_stall`.
- **Failure Indicator:** Both are returned, or challenge would be added to a disengaging user.

#### US-F02: Plateau diagnosis (Physical Stall vs Disengagement)

**Description:** As a developer, I want the Programmer to distinguish a physical plateau from a motivation plateau so that it adds challenge in one case and reduces friction in the other.

**Acceptance Criteria:**

- [ ] A pure diagnosis function classifies recent history as `physical_stall` (advancement criteria cleared repeatedly but not advanced -> more challenge) or `disengagement` (declining session length, rising skips, longer gaps -> less friction)
- [ ] The diagnosis is deterministic and reads only `WorkoutLog` history plus consistency signals
- [ ] The mapping from diagnosis to policy levers is explicit: `physical_stall` raises `progressionRate`/variety; `disengagement` lowers difficulty and shortens sessions
- [ ] Unit tests cover a clear stall case, a clear disengagement case, and a mixed case (resolved by precedence); build and tests pass

**Validation Test:**

- **Setup:** History A: consistent attendance, criteria cleared, no advance. History B: sessions shrinking from 20 to 5 min with skips.
- **Steps:**
  1. Diagnose each history
- **Expected Result:** A is `physical_stall`; B is `disengagement`.
- **Failure Indicator:** Either is misclassified, or the diagnosis is non-deterministic.

#### US-F03: Deterministic policy re-weighting service

**Description:** As a user, I want the app to quietly re-tune my program when a trigger fires so that sessions stay winnable and progressive without my ever waiting.

**Acceptance Criteria:**

- [ ] A real `DeterministicSessionPolicyService` implements `reprogram(user:recentLogs:trigger:)` and writes a new `SessionPolicy` with `version` incremented and `updatedBy == .deterministic`
- [ ] Re-program is invoked by the client on app open only when `dueTriggers` is non-empty; the app renders from the existing policy immediately and the new policy applies on the next open (new programming lands one session later)
- [ ] The service never generates or returns a workout; it only writes policy
- [ ] `disengagement` never increases challenge (Trigger Precedence upheld end-to-end); `return` sets the `reentry` ramp (US-E06)
- [ ] Unit tests cover: version increments; each trigger moves the expected levers; a disengagement re-program does not raise difficulty; build and tests pass

**Validation Test:**

- **Setup:** A user on `SessionPolicy.default` with a due `physical_stall` trigger
- **Steps:**
  1. Call `reprogram(...)`
  2. Inspect the returned policy
- **Expected Result:** `version` increments, `updatedBy == .deterministic`, and `progressionRate`/variety increased; no session was generated.
- **Failure Indicator:** The version is unchanged, a workout is returned, or a disengagement case raises difficulty.

#### US-F04: Templated policy note and Default Duration learning

**Description:** As a user, I want an honest note about what changed and a Default Duration that matches what I actually finish so that the app feels like it knows me.

**Acceptance Criteria:**

- [ ] Each re-program writes a templated `note` (`source == 'template'`) describing the real change ("what I changed and why"); the note may never invoke a `why` or claim a change the sessions will not reflect
- [ ] The service updates `user.duration.completedDurationEWMA` from logged `durationMinutes` (what the user completed, not requested) and sets `duration.defaultMinutes` from that EWMA
- [ ] `defaultMinutes` is snapped to a valid chip value (5/10/15/20/30/45/60)
- [ ] Unit tests cover: the note reflects the actual lever moved; EWMA tracks completed durations; `defaultMinutes` snaps correctly; build and tests pass

**Validation Test:**

- **Setup:** A user whose last five sessions were requested at 20 min but completed at ~12 min
- **Steps:**
  1. Run a `weekly_boundary` re-program
- **Expected Result:** `completedDurationEWMA` trends toward ~12, `defaultMinutes` snaps to 10 or 15, and the note names the real change without a hollow callback.
- **Failure Indicator:** `defaultMinutes` tracks the requested 20, or the note claims a change that did not happen.

---

### Epic G - Cold Start & Variety Language

> Governs roughly the first five sessions until the engine can drive itself. Includes the one LLM slice pulled into the MVP, always backed by a deterministic template.

#### US-G01: Starting Difficulty seeding (capped band, served gentle)

**Description:** As a new user, I want my first difficulty seeded safely from my self-report so that I get a winnable first session even if I over-rate myself.

**Acceptance Criteria:**

- [ ] Onboarding seeds `sessionPolicy.coldStartContract.cappedMaxDifficulty` from `profile.fitnessLevel` using a capped band (provisional: beginner 2, intermediate 3, advanced 4)
- [ ] The engine serves cold-start sessions at the gentle end of the eligible band (lowest eligible difficulty first), per US-E04
- [ ] Correction is left to the Asymmetric Ramp (US-E05): too-easy self-corrects as the user returns; too-hard is prevented up front
- [ ] Unit tests assert the cap per fitness level and gentle-end selection; build and tests pass

**Validation Test:**

- **Setup:** Three fresh users at beginner, intermediate, advanced
- **Steps:**
  1. Seed each user's `coldStartContract` and generate their first session
- **Expected Result:** Prescribed difficulties never exceed 2/3/4 respectively and start at the gentle end of the band.
- **Failure Indicator:** A first session exceeds the cap or opens at the top of the band.

#### US-G02: First-Week Contrast enforcement

**Description:** As a new user, I want my first week to visibly span strength, mobility, and primal so that the variety wedge is felt from session one.

**Acceptance Criteria:**

- [ ] While `coldStart.active`, `coldStartContract.forceContrastSpread` is true and drives the Step 0 spread from US-E04
- [ ] The First-Week Contrast rule guarantees no pillar repeats back-to-back across the first several cold-start sessions, even when `why`/`sitsLong` would bias toward one theme (e.g. a desk worker toward all mobility)
- [ ] The spread is deterministic given the onboarding inputs
- [ ] Unit tests assert a desk-worker cold start still spans multiple pillars in week one; build and tests pass

**Validation Test:**

- **Setup:** A `sitsLong == true` beginner whose inputs bias toward mobility
- **Steps:**
  1. Generate the first four cold-start sessions
- **Expected Result:** The four sessions span at least two pillars with no back-to-back repeat, rather than four mobility days.
- **Failure Indicator:** Week one collapses to a single pillar.

#### US-G03: Variety Language slice (LLM via thin proxy, template-backed)

**Description:** As a new user, I want each early session named and contrasted in plain language so that I immediately understand what today is and how it differs from yesterday.

**Acceptance Criteria:**

- [ ] A `VarietyLanguage` component produces a short line for the session ("Today's a mobility day - yesterday was strength")
- [ ] When online and cold-start-active, it may call the LLM once through the thin stateless proxy (US-N05) and set `note.source == 'llm'`
- [ ] It is always backed by a deterministic template: on any failure, timeout, or offline state it falls back to the template and sets `note.source == 'template'`; the app never blocks on the call
- [ ] The language may only name a contrast the engine actually produced (no hollow callbacks)
- [ ] Unit tests cover: template output offline; graceful fallback on a simulated proxy failure; the produced contrast matches the assembled session; build and tests pass

**Validation Test:**

- **Setup:** Airplane mode (no network); a mobility session that follows a strength session
- **Steps:**
  1. Open the app and read the session's Variety Language line
- **Expected Result:** A correct template line appears instantly ("Today's a mobility day - yesterday was strength") with `source == 'template'`, and nothing blocks.
- **Failure Indicator:** The app stalls waiting on the network, shows a blank/incorrect line, or names a contrast the session does not reflect.

#### US-G04: Cold-start handoff

**Description:** As a developer, I want cold-start rules to retire once there is enough history so that the engine drives itself unassisted.

**Acceptance Criteria:**

- [ ] `user.coldStart.sessionsLogged` increments on each completed session
- [ ] `coldStart.active` flips to false once `sessionsLogged` reaches the provisional threshold of 5 (tunable; v6 range 5-7)
- [ ] When `coldStart.active` becomes false, `coldStartContract` is cleared from the policy and Step 0 becomes a no-op, so staleness rotation and Adaptive Overload drive sessions unassisted
- [ ] Unit tests cover the flip at the threshold and the no-op Step 0 afterward; build and tests pass

**Validation Test:**

- **Setup:** A cold-start user with `sessionsLogged == 4`
- **Steps:**
  1. Complete a fifth session and re-evaluate
- **Expected Result:** `coldStart.active` flips to false, `coldStartContract` is cleared, and the sixth session is driven by staleness/overload rather than the contrast rule.
- **Failure Indicator:** Cold-start rules persist past the threshold, or the flip never happens.

---

### Epic H - Consistency & Phase

> Real implementations of the two evaluators that are currently mocks. Return-protected and Discipline-only at launch.

#### US-H01: Forgiving, Return-protected Consistency Score

**Description:** As a user, I want a score that rewards showing up and survives a missed day so that I am never punished for being human.

**Acceptance Criteria:**

- [ ] A real `ConsistencyScore`/evaluator replaces `MockConsistencyService`: `weeklyAdherence(week) = min(1, workoutsCompleted / weeklyGoal)`; `score = weightedRollingAverage(weeklyAdherence, recentWeeks) * 100` with recent weeks weighted more (`weeklyGoal` default 3)
- [ ] A 5-minute session counts as a full show-up; a single miss dents the score but never zeroes it
- [ ] `longestChain` is tracked and surfaced as an earned point of pride; a broken chain reduces the chain counter but only dents the score
- [ ] A Return (US-E06) protects the Score - it is celebrated, never penalized
- [ ] Copy contracts are identity-framed ("you're someone who moves"), never loss-framed
- [ ] New `ConsistencyScoreTests` cover: empty history, perfect run, single-miss dent (not zero), 5-min show-up, rolling weighting, Return protection; build and tests pass

**Validation Test:**

- **Setup:** A user at score ~90 who misses one day this week
- **Steps:**
  1. Recompute the score
- **Expected Result:** The score dents modestly (not to zero); a Return after a longer gap does not reduce it.
- **Failure Indicator:** A single miss zeroes the score, or a Return penalizes it.

#### US-H02: PhaseEvaluator (earned progression)

**Description:** As a user, I want my phase decided by demonstrated consistency and competence so that Strength is earned, never self-selected.

**Acceptance Criteria:**

- [ ] A real `PhaseEvaluator` replaces `MockPhaseService`: returns `.strength` only when both hold - Consistency Score sustained above threshold over a rolling window (e.g. >= 80% over ~8 weeks) and the foundational chains' entry tiers cleared (push/squat/hinge/core)
- [ ] Consistency-only or competence-only stays `.discipline`; a fresh user is `.discipline`
- [ ] Phase is never user-selectable; the transition is a gradual ramp, framed as honest stewardship (never failure) for a consistent-but-not-advancing user
- [ ] New `PhaseEvaluatorTests` cover: consistency-only stays Discipline, competence-only stays Discipline, both-met promotes, fresh user Discipline; build and tests pass

**Validation Test:**

- **Setup:** A user with 8 weeks at >= 80% but who has not cleared the entry tiers
- **Steps:**
  1. Evaluate the phase
- **Expected Result:** Returns `.discipline` (competence not yet met).
- **Failure Indicator:** Returns `.strength` on consistency alone, or the phase is settable.

---

### Epic I - Onboarding

> Minimal by design; the detailed flow is deferred to Phase 2. Ends by opening the Ready Screen with the first session already generated.

#### US-I01: Minimal v6 onboarding flow

**Description:** As a new user, I want a short onboarding that ends with a ready session so that I am moving within five minutes of opening the app.

**Acceptance Criteria:**

- [ ] Onboarding collects: name and basic profile (age/sex/height/weight), `fitnessLevel`, the free-text `why` statement, "do you sit 6+ hours most days?" (`sitsLong`), optional injuries, and exactly one duration question ("how long do you usually have?") that seeds `duration.onboardingSeedMinutes` and `duration.defaultMinutes`
- [ ] Onboarding seeds the capped Starting Difficulty (US-G01) and initializes `coldStart` (`active == true`, `sessionsLogged == 0`) and `SessionPolicy.default` with a `coldStartContract`
- [ ] On completion the app routes straight to the Ready Screen with the first session already generated (no picker to clear); `AppState` records onboarded
- [ ] The flow uses `Theme` tokens (56pt buttons, 16pt card radius, >= 44pt targets); no XP/levels/badges anywhere
- [ ] Uses `@Observable` view models; verify in iOS Simulator

**Validation Test:**

- **Setup:** Fresh install, not onboarded
- **Steps:**
  1. Complete onboarding, answering "15 minutes" to the duration question
  2. Observe the screen that follows
- **Expected Result:** The app lands on a Ready Screen showing a complete ~15-minute session, with `defaultMinutes == 15` and cold-start seeded.
- **Failure Indicator:** A duration picker blocks entry, no session is pre-generated, or cold-start is not seeded.

---

### Epic J - Ready Screen

> The state the app opens to (ADR-0016). A complete session pre-generated at the Default Duration, one tap to start, duration a non-blocking adjustment. Replaces the v5 Home screen.

#### US-J01: Ready Screen with pre-generated session and non-blocking duration chip

**Description:** As a user, I want today's session already there when I open the app so that I never have to browse or answer a question before starting.

**Acceptance Criteria:**

- [ ] On open, the app shows a complete session pre-generated at `duration.defaultMinutes` with one visually dominant "Start" action
- [ ] Duration is a non-blocking, one-tap-adjustable chip offering 5/10/15/20/30/45/60; tapping a value regenerates the session in under 100ms; Start is never disabled waiting for an answer
- [ ] The screen shows "Today: N min - Start", never "How long do you have today?" with Start gated
- [ ] The session preview lists today's blocks; no XP/levels/badges appear
- [ ] Uses `Theme` tokens and `@Observable` view models; verify in iOS Simulator

**Validation Test:**

- **Setup:** An onboarded user with `defaultMinutes == 15`, no session generated today
- **Steps:**
  1. Open the app to the Ready Screen
  2. Tap the "30" chip
- **Expected Result:** A ~15-min session preview is already present on open; tapping 30 regenerates a ~30-min session instantly; Start is prominent and always enabled.
- **Failure Indicator:** No session on open, a gate before Start, chip lag, or any XP/badge UI.

#### US-J02: Variety Language, Consistency, AI note, and Re-program-on-open

**Description:** As a user, I want the Ready Screen to tell me what today is, how I'm doing, and what the app changed so that the personalization is felt without any waiting.

**Acceptance Criteria:**

- [ ] The screen surfaces the session's Variety Language line (US-G03), the forgiving Consistency Score (identity-framed, never loss-framed), and the policy `note` when present
- [ ] On open, the app checks `dueTriggers` (US-F01) and, if any are due, triggers a Re-program in the background while rendering from the existing policy; the new policy applies next open
- [ ] The user never waits on the Re-program or the LLM slice; the screen is fully interactive immediately
- [ ] No XP/levels/badges; uses `Theme` tokens; verify in iOS Simulator

**Validation Test:**

- **Setup:** A user with a due `weekly_boundary` trigger and a templated note from the last re-program
- **Steps:**
  1. Open the app and read the Variety Language line, the score, and the note
  2. Confirm the screen is interactive immediately
- **Expected Result:** All three surfaces render from the existing policy with no spinner blocking Start; a Re-program is kicked off in the background.
- **Failure Indicator:** The screen blocks on re-programming, the score is loss-framed, or the note is missing when one exists.

---

### Epic K - Active Session

> The player. Large touch targets (60pt on active screens), auto-playing demos, set tracking, rest timer, swap, and resume.

#### US-K01: Active session player

**Description:** As a user, I want a focused player that walks me through each exercise so that I never lose my place mid-session.

**Acceptance Criteria:**

- [ ] The player renders each `PrescribedExercise` in order with its target (reps or hold seconds), an auto-playing Lottie demo (static fallback under Reduce Motion), and set tracking
- [ ] Elapsed time is always visible; touch targets are >= 60pt on this screen
- [ ] Set completion advances the session and records completed sets toward the eventual log
- [ ] Accessibility: VoiceOver labels on controls, Dynamic Type respected
- [ ] Uses `Theme` tokens and `@Observable` view models; verify in iOS Simulator

**Validation Test:**

- **Setup:** A generated 15-min session started from the Ready Screen
- **Steps:**
  1. Start the session and complete the first two exercises
- **Expected Result:** Each exercise shows its demo and target, elapsed time updates, and completing sets advances to the next exercise.
- **Failure Indicator:** The player loses position, the demo does not play (with no static fallback), or elapsed time is hidden.

#### US-K02: Rest timer with haptics

**Description:** As a user, I want a rest timer between sets so that I pace the work without watching the clock.

**Acceptance Criteria:**

- [ ] After a set, a rest timer counts down `restSeconds` and auto-advances when done
- [ ] Completion fires a haptic, with an audio alternative for accessibility
- [ ] The timer can be skipped or extended; it pauses correctly if the app is backgrounded
- [ ] Uses `Theme` tokens; verify in iOS Simulator (haptics verified on device where possible)

**Validation Test:**

- **Setup:** Mid-session, between two sets
- **Steps:**
  1. Complete a set and let the rest timer run out
- **Expected Result:** The timer counts down `restSeconds`, fires a haptic (or audio alternative), and advances to the next set.
- **Failure Indicator:** The timer does not fire, gives no feedback, or fails to advance.

#### US-K03: In-session swap

**Description:** As a user, I want to swap an exercise I can't or won't do so that one bad movement never derails the session.

**Acceptance Criteria:**

- [ ] A swap control calls the deterministic swap engine (US-C08, `ExerciseSwap.swap`) and substitutes within the same pillar/pattern, difficulty band, and time budget, never duplicating a movement already in the session
- [ ] When no safe in-budget peer exists, the UI shows a clear "no alternative" state rather than an unsafe substitution
- [ ] The swapped exercise carries a fresh capacity-relative target and preserves the slot's set count and rest
- [ ] Uses `Theme` tokens; verify in iOS Simulator

**Validation Test:**

- **Setup:** An active session whose current exercise has an eligible peer
- **Steps:**
  1. Tap swap on the current exercise
- **Expected Result:** The exercise is replaced by a same-pillar/same-pattern peer within budget, with a valid target; a lone-peer slot instead shows "no alternative".
- **Failure Indicator:** The swap crosses pillar/pattern, breaks the time budget, or duplicates an existing movement.

#### US-K04: Background and resume

**Description:** As a user, I want the session to survive backgrounding so that a text message doesn't cost me my workout.

**Acceptance Criteria:**

- [ ] Session state (current exercise, set, elapsed time, rest timer) persists across backgrounding and app relaunch
- [ ] Resuming restores the exact position; the rest timer resumes correctly
- [ ] An abandoned session can be resumed or discarded from the Ready Screen
- [ ] Verify in iOS Simulator

**Validation Test:**

- **Setup:** An active session at exercise 3, set 2
- **Steps:**
  1. Background the app for a minute, then reopen
- **Expected Result:** The session resumes at exercise 3, set 2, with elapsed time preserved.
- **Failure Indicator:** The session resets, loses position, or cannot be resumed.

---

### Epic L - Post-Session

> Celebration, summary, log write, and the feedback that feeds Default Duration and the Asymmetric Ramp.

#### US-L01: Post-session summary and log write

**Description:** As a user, I want a clear wrap-up after finishing so that I feel the win and my history is recorded.

**Acceptance Criteria:**

- [ ] On completion the app writes a `WorkoutLog` with `requestedMinutes`, the actually-completed `durationMinutes`, `shape`, `focusPillar`, `wasReturn`, and per-exercise `completedSets`/`skipped`
- [ ] `durationMinutes` feeds `duration.completedDurationEWMA` (US-F04); the Consistency Score updates (US-H01)
- [ ] The screen shows a completion celebration and a template-based summary with muscle/mobility coverage; copy is identity-framed
- [ ] No XP/levels/badges; uses `Theme` tokens and `@Observable` view models; verify in iOS Simulator

**Validation Test:**

- **Setup:** A 20-min session finished in ~14 min
- **Steps:**
  1. Complete the session and view the post-session screen
- **Expected Result:** A celebration and summary appear; a `WorkoutLog` is written with `requestedMinutes == 20`, `durationMinutes ≈ 14`; the score updates.
- **Failure Indicator:** No log is written, `durationMinutes` records the requested 20, or XP/badges appear.

#### US-L02: Rating and perceived-difficulty feedback

**Description:** As a user, I want to rate how hard the session felt so that tomorrow's session adjusts to me.

**Acceptance Criteria:**

- [ ] The post-session screen collects `perceivedDifficulty` (`too_easy`/`just_right`/`too_hard`) and stores it on the `WorkoutLog`
- [ ] The value feeds the Asymmetric Ramp (US-E05) so the next session adjusts within one cycle
- [ ] The control is optional and non-blocking; skipping it is treated as unrated
- [ ] Uses `Theme` tokens; verify in iOS Simulator

**Validation Test:**

- **Setup:** A finished session
- **Steps:**
  1. Rate it `too_hard`
  2. Generate the next session
- **Expected Result:** The log records `too_hard`, and the next session's targets ease immediately per the Asymmetric Ramp.
- **Failure Indicator:** The rating is not stored, or the next session ignores it.

---

### Epic M - Progress Tab

> The reflection surface. Core history is free; deeper analytics sit behind the paywall.

#### US-M01: Session calendar and Consistency Score trend

**Description:** As a user, I want to see my history and score over time so that I feel my consistency building.

**Acceptance Criteria:**

- [ ] A calendar shows completed sessions; a chart shows the Consistency Score over time (Swift Charts)
- [ ] `longestChain` is surfaced as an earned point of pride; all copy is identity-framed, never loss-framed
- [ ] The view reads real `WorkoutLog` history and the real score (US-H01)
- [ ] Uses `Theme` tokens and `@Observable` view models; verify in iOS Simulator

**Validation Test:**

- **Setup:** A user with three weeks of logged sessions
- **Steps:**
  1. Open the Progress tab
- **Expected Result:** The calendar marks the logged days and the score trend renders; `longestChain` shows as a positive achievement.
- **Failure Indicator:** History is missing, the trend fails to render, or copy is loss-framed.

#### US-M02: Pillar balance, chain position, personal bests, and premium gating

**Description:** As a user, I want to see how my training is balanced and where I stand so that progress feels legible, with depth available if I want it.

**Acceptance Criteria:**

- [ ] The tab shows pillar balance (strength/mobility/primal), progression-chain position, and personal bests from real history
- [ ] Deeper analytics are gated behind premium (US-N04); the gate is a clear, non-nagging upsell
- [ ] Free users still see basic balance, chain position, and bests; only the deep-analytics layer is gated
- [ ] Uses `Theme` tokens; verify in iOS Simulator

**Validation Test:**

- **Setup:** A free user and a premium user, each with history
- **Steps:**
  1. Open the Progress tab as each
- **Expected Result:** Both see basic balance/chain/bests; only the premium user sees the deep-analytics layer; the free user sees a clear upsell in its place.
- **Failure Indicator:** Deep analytics are free, or basic history is gated behind premium.

---

### Epic N - Apple-Native Integrations & Thin Proxy

> Identity, sync, health, monetization, and the single backend piece: a thin stateless proxy that holds the model API key for the Variety Language slice. No scheduler, no data mirror.

#### US-N01: Sign in with Apple

**Description:** As a user, I want to sign in with Apple so that my identity is private and setup is one tap.

**Acceptance Criteria:**

- [ ] A real `AuthService` implements `signInWithApple()`, `currentUserIdentifier()`, and `signOut()` via Sign in with Apple
- [ ] The core loop works offline and without an iCloud account; sign-in is not a gate to the first session
- [ ] The signed-in identifier is stored and used to key the user record
- [ ] Verify in iOS Simulator (full flow verified on device where possible)

**Validation Test:**

- **Setup:** Fresh install
- **Steps:**
  1. Complete Sign in with Apple
- **Expected Result:** A stable user identifier is returned and persisted; the app remains usable offline afterward.
- **Failure Indicator:** Sign-in blocks the core loop, or the identifier is not persisted.

#### US-N02: CloudKit sync and backup

**Description:** As a user, I want my data synced and backed up so that I never lose my history across devices.

**Acceptance Criteria:**

- [ ] The CoreData stack switches to the CloudKit-backed `NSPersistentCloudKitContainer` private DB for `CDUser`, `CDWorkoutLog`, and the persisted `SessionPolicy`
- [ ] The core loop still works fully offline and with no iCloud account; sync is additive
- [ ] Conflict handling and initial sync are verified; no data loss on a round trip through iCloud
- [ ] Verify in iOS Simulator (sync verified across two signed-in instances where possible)

**Validation Test:**

- **Setup:** A signed-in user with local history
- **Steps:**
  1. Enable CloudKit and let an initial sync run, then read back
- **Expected Result:** User, logs, and the latest `SessionPolicy` are present after sync; offline use is unaffected.
- **Failure Indicator:** Sync drops records, or offline use breaks.

#### US-N03: HealthKit write

**Description:** As a user, I want my sessions written to Health so that my movement counts where I already track it.

**Acceptance Criteria:**

- [ ] A real `HealthKitService` requests authorization and writes each completed session as a workout (on-device only, using `metValue`/duration)
- [ ] HealthKit data stays on-device; a denied authorization degrades gracefully (no crash, no blocked loop)
- [ ] Writes are idempotent per session (no duplicates on resume)
- [ ] Verify in iOS Simulator (write verified on device where possible)

**Validation Test:**

- **Setup:** A user who grants HealthKit permission
- **Steps:**
  1. Complete a session and check Health
- **Expected Result:** A workout with the correct duration is written once; denying permission still lets the session complete.
- **Failure Indicator:** No write on grant, a duplicate on resume, or a crash on denial.

#### US-N04: StoreKit 2 subscriptions and paywall

**Description:** As a user, I want to unlock depth with a subscription so that I can get more out of the habit once I'm hooked, while the core loop stays free.

**Acceptance Criteria:**

- [ ] A real `SubscriptionService` implements `currentSubscription()`, `refreshEntitlements()`, `purchasePremium()`, and `restorePurchases()` via StoreKit 2
- [ ] Free tier is unlimited workouts forever; premium (~$7.99/mo or ~$59.99/yr, 14-day trial) unlocks the depth layer (analytics depth, Strength Phase, later AI reports)
- [ ] The paywall never gates the core loop; entitlement drives the premium gates in US-M02
- [ ] Subscription state persists and restores; clear disclosure per App Store rules
- [ ] Verify in iOS Simulator (StoreKit configuration/sandbox)

**Validation Test:**

- **Setup:** A free user viewing a premium-gated analytics view
- **Steps:**
  1. Purchase premium in the StoreKit sandbox, then revisit
- **Expected Result:** The gated depth unlocks; the core loop was never blocked; restore re-grants entitlement.
- **Failure Indicator:** The core loop is gated, or entitlement does not persist/restore.

#### US-N05: Thin stateless proxy for the Variety Language slice

**Description:** As a developer, I want a minimal key-holding proxy so that the one day-one LLM call can run without shipping an API key in the app.

**Acceptance Criteria:**

- [ ] A thin stateless proxy (e.g. a Cloudflare Worker) holds the model API key and proxies exactly one Claude call per Variety Language request
- [ ] It stores no user logs at rest: history is sent transiently from the device and not persisted server-side; no scheduler, no database mirror
- [ ] The client calls it only for the Variety Language slice (US-G03) and always falls back to the deterministic template on any failure or timeout
- [ ] The proxy endpoint, request/response contract, and the client fallback are documented; a failing/absent proxy never blocks the app

**Validation Test:**

- **Setup:** The proxy deployed with a valid key; then a second run with the proxy unreachable
- **Steps:**
  1. Trigger a Variety Language request online
  2. Repeat with the proxy unreachable
- **Expected Result:** The first returns an LLM line (`source == 'llm'`); the second falls back to the template (`source == 'template'`) with no user-visible error and no blocking.
- **Failure Indicator:** The key is shipped client-side, the proxy stores logs, or an unreachable proxy blocks the app.

---

## Functional Requirements

**Data & persistence**

- FR-1: The system must extend `User` with `why` (statement + optional `openingBias`), `duration` (`defaultMinutes`/`onboardingSeedMinutes`/`completedDurationEWMA`), and `coldStart` (`sessionsLogged`/`active`), retaining `primaryGoal`.
- FR-2: The system must extend `WorkoutLog` with `requestedMinutes` and `wasReturn`, and treat `durationMinutes` as the actually-completed duration.
- FR-3: The system must define an always-valid `SessionPolicy` with a sensible `default(for:)`, persisted and available offline and before the AI Programmer first runs.
- FR-4: The system must define `ReprogramTrigger` and a `SessionPolicyServiceProtocol`, wired into `ServiceContainer`.
- FR-5: The system must persist all new fields and types through `CDUser`/`CDWorkoutLog`/`PersistenceCoding` with backward-compatible defaults for legacy records.

**Engine**

- FR-6: The system must shape sessions across the full 5-60 min range using four shapes (single-focus / blend-light / blend-full / blend-extended).
- FR-7: The system must treat primal as a first-class pillar and build a dedicated primal block in extended sessions.
- FR-8: The system must consume the Session Policy levers (`progressionRate`, `pillarWeighting`, `varietyWindow`) in the pipeline, with `SessionPolicy.default` reproducing prior behavior.
- FR-9: The system must apply a Step 0 cold-start override (First-Week Contrast + capped Starting Difficulty) only while `coldStart.active`.
- FR-10: The system must apply the Asymmetric Ramp (down eager, up gradual) in Adaptive Overload.
- FR-11: The system must serve a Return as an easy, winnable session and defer readjustment to a Re-entry Ramp.
- FR-12: The system must keep generation deterministic, fully offline, and under 100ms across the whole 5-60 range.

**AI Programmer, cold start, consistency & phase**

- FR-13: The system must detect due Re-program triggers on app open (Weekly Boundary, Return, Physical Stall, Disengagement) and enforce Trigger Precedence (Disengagement suppresses Physical Stall).
- FR-14: The system must diagnose Physical Stall vs Disengagement deterministically and re-weight the policy accordingly, incrementing `version` and setting `updatedBy == 'deterministic'`, never generating a session and never blocking the user.
- FR-15: The system must write a templated policy `note` that only names real changes, and set `defaultMinutes` from `completedDurationEWMA`.
- FR-16: The system must seed a capped Starting Difficulty served at the gentle end, enforce First-Week Contrast, and retire cold-start after ~5 logged sessions.
- FR-17: The system must produce the Variety Language line, optionally via the proxy (`source == 'llm'`) but always with a deterministic template fallback (`source == 'template'`), never blocking on the network.
- FR-18: The system must compute a forgiving, Return-protected Consistency Score and a deterministic PhaseEvaluator that returns Discipline unless both consistency and competence hold.

**UI**

- FR-19: The system must open to a Ready Screen with a complete session pre-generated at the Default Duration, one dominant Start, and a non-blocking one-tap duration chip (5/10/15/20/30/45/60); it must never gate Start on a duration question.
- FR-20: The system must surface Variety Language, the identity-framed Consistency Score, and the policy note on the Ready Screen, and trigger due Re-programs in the background without making the user wait.
- FR-21: The system must provide an active session player (60pt targets, auto demos with Reduce-Motion fallback, set tracking, rest timer with haptics/audio, in-session swap, background/resume), a post-session summary that writes the log and collects perceived difficulty, and a Progress tab (calendar, score trend, pillar balance, chain position, bests) with premium-gated depth.
- FR-22: The system must never display XP, levels, or badges anywhere, and must use `Theme` tokens for all colors/typography/spacing.

**Apple integrations & backend**

- FR-23: The system must integrate Sign in with Apple (identity), CloudKit (private-DB sync of user/logs/policy), HealthKit (on-device workout writes), and StoreKit 2 (free unlimited core + premium depth, 14-day trial).
- FR-24: The system must run exactly one thin stateless proxy that holds the model API key for the Variety Language slice, stores no user logs at rest, and runs no scheduler or data mirror.

## Non-Goals (Out of Scope)

- The full option-(B) LLM Programmer (richer diagnosis and narrative notes) - the MVP ships option (C) plus the single Variety Language slice.
- Any server-side scheduler or user-data mirror - re-program is client-triggered on app open only.
- XP, levels, or badges; social features, leaderboards, or challenges.
- The full Strength-Phase catalog and optional equipment variants (kettlebell/dumbbell); all MVP movements are bodyweight (Zero-Equipment Floor).
- Direct AI generation of sessions - the AI only writes policy; the deterministic engine assembles every session.
- Android, widgets, Live Activities, and Apple Watch.
- A detailed onboarding flow and full animation sourcing (deferred to Phase 2).

## Design Considerations

- The Ready Screen must read "Today: N min - Start", never "How long do you have today?" with Start disabled - this distinction defines the wedge.
- All consistency and return copy is identity-framed ("you're someone who moves"), never loss-framed; a Return is celebrated, never a scolding.
- Mobility is co-primary, presented as same-day relief, never as a warm-up.
- Design tokens only: `Theme.Colors`/`Theme.Typography`/`Theme.Spacing`; 56pt buttons, 16pt card radius, >= 44pt targets (60pt on active session screens).
- Accessibility throughout: VoiceOver, Dynamic Type, Reduce Motion (static demo fallback), haptics with an audio alternative.
- The Variety Language line must be legible and instant; it never spins waiting on the LLM.

## Technical Considerations

- **Architecture:** MVVM + protocol-based services; views access services via `@Environment(\.services)`; view models are `@Observable` (never `ObservableObject`/`@Published`); all service methods are `async throws`; swap a mock for a real implementation by changing one line in `ServiceContainer`.
- **Persistence:** CoreData via `NSPersistentCloudKitContainer`; domain models are `Codable` structs; nested/complex fields stored as JSON-encoded `Data` via `PersistenceCoding`; new fields must decode with backward-compatible defaults.
- **Engine:** pure Swift, on-device, deterministic, <100ms, Zero-Equipment Floor; v6 extends the built Steps 1-7 + swap rather than rewriting them; time is always injected (`asOf:`), never read from the wall clock inside pure logic.
- **AI Programmer:** on-device deterministic heuristics (option C) writing the Session Policy; never on the critical path; new programming applies one open later.
- **Proxy:** a single thin stateless key-holder (e.g. Cloudflare Worker) for the one Variety Language LLM call; documented request/response contract; the client always has a deterministic fallback.
- **Build:** `xcodegen generate` then `xcodebuild ... -scheme FitSnack ... test`; single `FitSnack` scheme builds the app and runs `FitSnackTests`.
- **Testing:** `XCTestCase` + `@testable import FitSnack`; all new logic has tests; extend the existing suites (`SessionShapeSelectionTests`, `PillarBalanceTests`, `AdaptiveOverloadTests`, `SessionAssemblyTests`, `ExerciseSwapTests`, `ModelsTests`, `PersistenceTests`, `EnumsTests`, `ServiceContainerTests`) and add new ones (`SessionPolicyTests`, `AIProgrammerTests`, `ColdStartTests`, `VarietyLanguageTests`, `ConsistencyScoreTests`, `PhaseEvaluatorTests`).

## Success Metrics

North Star: Weekly Active Exercisers (users completing >= 1 session/week).

| Metric | Month 3 | Month 6 |
|--------|---------|---------|
| Onboarding -> 1st session | 60% | 70% |
| Day 7 retention | 20% | 25% |
| Day 30 retention | 10% | 15% |
| Weekly Active Exercisers | 35% of installs | 40% |
| Free -> Paid | 4% | 7% |
| Session completion (started -> finished) | >= 80% | >= 80% |
| Generation latency (on-device, 5-60 min) | <100ms | <100ms |
| Variety Language availability (template + LLM) | 100% | 100% |

## Open Questions

- Session model at 5-60 min: this PRD writes stories against the provisional 4-shape mapping (5-10 single-focus, 11-20 blend-light, 21-40 blend-full, 41-60 blend-extended). Confirm the thresholds and whether a 60-min session should always blend all three pillars.
- `primaryGoal` vs `why`: the PRD keeps both (additive `why`, unchanged `primaryGoal`) to avoid a persistence-contract break. Decide whether to fold `primaryGoal` into `why` in a later migration.
- Cold-start handoff threshold: provisionally `coldStart.active` flips after 5 logged sessions (v6 range 5-7). Tune in testing.
- Proxy hosting: confirm the Cloudflare Worker (per CLAUDE.md's deferred note) as the thin stateless proxy, and the exact request/response contract for the Variety Language call.
- Return threshold: provisionally a gap >= 7 days triggers a Return and a 3-session Re-entry Ramp. Confirm both numbers.

---

*Generated by the `prd` skill from `FitSnack-PRD-v6_070226.md`. Epics A-C are carried forward as built; Epics D-N are new or reframed under v6. Mark each story's acceptance-criteria checkboxes `[x]` as it is completed, so this PRD doubles as a live progress tracker.*
