# PRD: FitSnack Phase 1 MVP - The Discipline Loop

**Source plan:** `.claude/agent/tasks/FitSnack-PRD-v5.md` (v5.0, reconciled to ADRs 0001-0013)
**Build approach:** Clean rebuild (existing codebase is reference only)
**Scope:** Full Phase 1 MVP
**Persistence:** CoreData + `NSPersistentCloudKitContainer`
**Platform:** iOS 17+, SwiftUI, Swift 5.9+
**Status:** Pre-Development

---

## Introduction

FitSnack is an iOS-first movement app for busy, desk-bound adults who can give exercise 5-30 minutes a day.
It exists to build one thing: the discipline of showing up.
The user opens the app, says how many minutes they have, and a deterministic on-device engine generates a complete zero-equipment session that blends bodyweight strength and mobility.
No browsing, no choosing, no thinking.

This PRD covers the full Phase 1 MVP as a clean rebuild.
The app is built around a two-phase journey: every new user starts in the Discipline Phase (consistency is the only goal, sessions stay short and simple), and earns the way into the Strength Phase over time by sustaining the habit and progressing their movements.
At launch no user has earned the Strength Phase yet, so the MVP ships the Discipline-Phase experience with the PhaseEvaluator already in place.

The problem it solves: time- and bandwidth-poor adults feel stiff and guilty, have abandoned 2-3 fitness apps, and need same-day relief plus a forgiving way to keep showing up that never punishes a single missed day.

## Goals

- Generate a complete, personalized, zero-equipment session in under 100ms, fully offline, the moment the user gives their available minutes.
- Make mobility (Movement Practice) a co-primary pillar, not a warm-up, so a stiff desk worker feels relief in minute one.
- Replace fragile streaks with a forgiving rolling Consistency Score that survives a missed day and is identity-framed, never loss-framed.
- Guarantee the Zero-Equipment Floor: every session is completable with only a floor and a wall.
- Keep the core loop free and unlimited; charge only for depth (analytics, Strength Phase, later AI).
- Ship on an Apple-native stack with no custom backend: CoreData + CloudKit, StoreKit 2, Sign in with Apple, HealthKit.
- Get the user into their first workout within 5 minutes of opening the app.

## User Stories

> Stories are grouped into epics and ordered by dependency.
> Build foundations first (Epic A-B), then the engine (Epic C), then logic layers (Epic D), then UI (Epic E-I), then Apple integrations (Epic J).
> Each story is small enough for one focused session.
>
> **iOS verification note:** this project is an iOS app, so the skill's "Verify in browser using dev-browser skill" criterion is replaced by "Verify in iOS Simulator" (build and run on an iPhone 15 simulator via `xcodebuild`/Xcode, inspect the screen, exercise the flow).

---

### Epic A - Project & Data Foundation

#### US-A01: Bootstrap the clean Xcode project

**Description:** As a developer, I want a fresh, buildable SwiftUI project scaffold so that all later work has a home.

**Acceptance Criteria:**

- [x] `ios/FitSnack/project.yml` defines the app target (iOS 17.0 deployment, Swift 5.9, bundle id `com.fitsnack.app`) and a `FitSnackTests` target
- [x] `xcodegen generate` produces a project that builds clean with zero warnings
- [x] Folder structure created: `App/`, `Models/`, `Services/Protocols/`, `Services/`, `Persistence/`, `Views/`, `ViewModels/`, `DI/`, `Resources/`, `Utilities/`, `DesignSystem/`
- [x] Design tokens scaffolded in `DesignSystem/Theme.swift`: `Theme.Colors`, `Theme.Typography`, `Theme.Spacing` (button height 56pt, card radius 16pt, min touch target 44pt / 60pt on workout screens)
- [x] App launches to an empty placeholder root view
- [x] Build passes

**Validation Test:**

- **Setup:** Clean checkout, xcodegen installed
- **Steps:**
  1. Run `cd ios/FitSnack && xcodegen generate`
  2. Run `xcodebuild -project ios/FitSnack/FitSnack.xcodeproj -scheme FitSnack -sdk iphonesimulator build`
  3. Run the app in the iOS Simulator
- **Expected Result:** Project generates, builds with zero warnings, and launches to the placeholder root view.
- **Failure Indicator:** xcodegen fails, build emits warnings/errors, or the app crashes on launch.

#### US-A02: Define domain enums

**Description:** As a developer, I want the canonical domain enums so that every model and the engine share one vocabulary.

**Acceptance Criteria:**

- [x] Enums defined in `Models/Enums.swift`: `Pillar` (`strength`/`mobility`/`primal`), `Phase` (`discipline`/`strength`), `MovementPattern` (push/squat/hinge/core/pull/mobility/locomotion), `ExerciseCategory` (strength/mobility/warmup/cooldown/primal), `Equipment`, `FitnessLevel` (beginner/intermediate/advanced), `PrimaryGoal` (stay_active/build_strength/increase_energy/reduce_stress/lose_weight), `SessionShape` (single_focus/blend), `PerceivedDifficulty` (too_easy/just_right/too_hard)
- [x] Every enum conforms to `Codable`, `CaseIterable`, `Identifiable` (where it has a stable id), and `Equatable`
- [x] Unit tests assert raw values are stable (so persisted data never breaks on rename)
- [x] Build and tests pass

**Validation Test:**

- **Setup:** US-A01 complete
- **Steps:**
  1. Build the project
  2. Run the enum encoding tests
- **Expected Result:** All enums encode to their documented string raw values and decode back identically.
- **Failure Indicator:** A raw value differs from the documented value or a round-trip decode fails.

#### US-A03: Define domain model structs

**Description:** As a developer, I want plain Codable domain structs so that the engine and views work with simple value types decoupled from persistence.

**Acceptance Criteria:**

- [x] Structs in `Models/`: `UserProfile` (age, sex, heightCm, weightKg, fitnessLevel, primaryGoal, sitsLong, injuries, typicalAvailableMinutes), `User` (id, displayName, createdAt, profile, phase, subscription, consistency), `Exercise` (all fields from v5 section 2.3, including `pillar`, `movementPattern`, `category`, `difficulty`, `phase`, `equipment`, `isHold`, `defaultReps`, `defaultDurationSeconds`, `estimatedTimePerSetSeconds`, `metValue`, `progressionChainId`, `progressionOrder`, `regressionId`, `progressionId`, `advancementCriteria`, `apartmentFriendly`), `Workout` (ordered blocks of prescribed exercises with reps/sets/duration/rest), `WorkoutBlock`, `WorkoutLog` (per v5 section 2.3), `Consistency` (weeklyGoal, score, workoutsThisWeek, longestChain, totalWorkoutsCompleted, totalMinutesExercised), `Subscription` (tier, provider, expiresAt, trialEndsAt)
- [x] All structs are `Codable` and `Equatable`; `Exercise` and `Workout` are `Identifiable`
- [x] Unit tests cover encode/decode round-trips for every struct, including optional fields present and absent
- [x] Build and tests pass

**Validation Test:**

- **Setup:** US-A02 complete
- **Steps:**
  1. Build the project
  2. Run the model Codable tests
- **Expected Result:** Every struct round-trips through JSON encode/decode with no data loss, including nil optionals.
- **Failure Indicator:** A field is dropped, a decode throws, or an Equatable comparison fails after round-trip.

#### US-A04: CoreData stack with CloudKit container

**Description:** As a developer, I want a CoreData stack backed by `NSPersistentCloudKitContainer` so that user data persists locally and is ready to sync.

**Acceptance Criteria:**

- [x] `FitSnack.xcdatamodeld` defines entities `CDUser` and `CDWorkoutLog` mirroring the domain structs (complex/nested fields stored as JSON-encoded `Data` attributes)
- [x] `Persistence/PersistenceController.swift` initializes `NSPersistentCloudKitContainer` with a local-only configuration that does NOT yet require an iCloud account (CloudKit sync wiring lands in US-J02)
- [x] Conversion methods: `CDUser.toUser()` / `update(from: User)` and `CDWorkoutLog.toWorkoutLog()` / `update(from: WorkoutLog)`
- [x] A `MockPersistence` in-memory store is available for tests and previews
- [x] Unit tests: save a `User`, reload, and assert equality; save and query `WorkoutLog`s by date range
- [x] Build and tests pass

**Validation Test:**

- **Setup:** US-A03 complete
- **Steps:**
  1. Run the persistence tests against the in-memory store
  2. Save a fully-populated `User`, fetch it back, convert to domain struct
- **Expected Result:** The fetched `User` equals the saved one across all fields, including nested profile and consistency.
- **Failure Indicator:** Save/fetch loses a field, conversion drops nested data, or the store fails to initialize.

#### US-A05: Service protocols, ServiceContainer, and app state

**Description:** As a developer, I want protocol-based services injected via the environment so that mocks and real implementations are swappable in one place.

**Acceptance Criteria:**

- [x] Protocols in `Services/Protocols/`: `ExerciseServiceProtocol`, `WorkoutEngineProtocol`, `ConsistencyServiceProtocol`, `PhaseServiceProtocol`, `UserServiceProtocol`, `WorkoutLogServiceProtocol`, `HealthKitServiceProtocol`, `SubscriptionServiceProtocol`, `AuthServiceProtocol`; all methods `async throws` where they touch storage or external systems
- [x] `DI/ServiceContainer.swift` composes all service instances; a custom `EnvironmentKey` (`\.services`) injects it at the app root
- [x] `Utilities/AppState.swift` is an `@Observable` holding `isOnboarded` and `selectedTab`, persisted to UserDefaults; controls onboarding-vs-main-tabs routing
- [x] All view models are `@Observable` (Observation framework), never `ObservableObject`
- [x] Swapping a mock for a real service requires changing only one line in `ServiceContainer`
- [x] Build passes

**Validation Test:**

- **Setup:** US-A04 complete
- **Steps:**
  1. Build the project with mock services wired in `ServiceContainer`
  2. Inspect a sample view that reads `@Environment(\.services)`
- **Expected Result:** The app compiles and a view can resolve every service through the environment without passing them manually.
- **Failure Indicator:** A service is unreachable from the environment, or a view model uses `ObservableObject`/`@Published`.

---

### Epic B - Exercise Library

#### US-B01: Author the bundled exercise library

**Description:** As a developer, I want a complete bundled JSON library of ~38 movements so that the engine has a real pool to build sessions from.

**Acceptance Criteria:**

- [x] `Resources/Exercises.json` contains ~38 movements spanning all categories per v5 section 5.1: push (~8), squat (~5), hinge (~4), core (~7), pull/postural (~3), Movement Practice mobility (~12), primal (~3)
- [x] Every exercise has all fields from US-A03 fully populated; `equipment` is always `[]` (Zero-Equipment Floor)
- [x] Each strength/primal movement has a regression and a progression forming valid progression chains (`progressionChainId` + `progressionOrder` link without gaps)
- [x] Strength-Phase-only skills (e.g. L-sit, pistol squat, one-arm push-up) are tagged `phase: "strength"`; all others `phase: "discipline"`
- [x] Every exercise sets `apartmentFriendly: true` and a realistic `metValue` and `estimatedTimePerSetSeconds`
- [x] Holds set `isHold: true` with `defaultDurationSeconds`; rep-based set `isHold: false` with `defaultReps`

**Validation Test:**

- **Setup:** US-A03 complete
- **Steps:**
  1. Decode `Exercises.json` into `[Exercise]`
  2. Count movements per category and per pillar
  3. Walk each progression chain from `progressionOrder` 0 upward
- **Expected Result:** ~38 exercises decode with no errors; every category from v5 5.1 is represented; every chain is contiguous with no orphan `progressionId`/`regressionId` references.
- **Failure Indicator:** Decode throws, a category is missing, a chain has a gap, or any exercise has non-empty equipment.

#### US-B02: Exercise service loads and validates the library

**Description:** As a developer, I want a service that loads and integrity-checks the library at startup so that a malformed library fails loudly, not silently.

**Acceptance Criteria:**

- [x] `MockExerciseService` implements `ExerciseServiceProtocol`, loading `Exercises.json` once and caching it
- [x] On load it validates: unique ids, every `regressionId`/`progressionId` resolves, every chain is contiguous, all `equipment == []`
- [x] Query helpers: by pillar, by movement pattern, by phase, by difficulty range, and resolve-next-in-chain
- [x] A validation failure throws a descriptive error (which exercise, which rule)
- [x] Unit tests cover each query helper and each validation rule (with a deliberately broken fixture)
- [x] Build and tests pass

**Validation Test:**

- **Setup:** US-B01 complete
- **Steps:**
  1. Load the real library via the service
  2. Load a fixture with a dangling `progressionId`
- **Expected Result:** The real library loads and answers queries; the broken fixture throws an error naming the offending exercise and rule.
- **Failure Indicator:** The broken fixture loads without error, or a query returns wrong results.

---

### Epic C - Deterministic Workout Engine

> The engine is pure Swift, no network, no LLM, instant, offline.
> Each story below implements one step of the v5 section 2.4 pipeline and is independently unit-tested.

#### US-C01: Session-shape selection (pipeline Step 1)

**Description:** As a user, I want short sessions to stay simple and long sessions to do more so that the workout always fits my available minutes.

**Acceptance Criteria:**

- [x] Given `requestedMinutes`, the engine selects: 5-10 min -> `SINGLE_FOCUS`; 15 min -> `BLEND` (light: warm-up + one real block + small second block); 20-30 min -> `BLEND` (full: warm-up + strength block + mobility block + cooldown)
- [x] Boundary minutes (10, 15, 20) map to the documented shape deterministically
- [x] Pure function: same input always yields the same shape
- [x] Unit tests cover 5/10/15/20/30 and the boundaries
- [x] Build and tests pass

**Validation Test:**

- **Setup:** Engine module compiles
- **Steps:**
  1. Call shape selection for 5, 10, 15, 20, 30 minutes
- **Expected Result:** 5 and 10 -> single-focus; 15 -> blend light; 20 and 30 -> blend full.
- **Failure Indicator:** Any value maps to the wrong shape or the function is non-deterministic.

#### US-C02: Pillar balance by staleness (pipeline Step 2)

**Description:** As a user, I want the app to work the pillar I have neglected so that strength and mobility stay balanced over time.

**Acceptance Criteria:**

- [x] From `recentLogs`, the engine computes days-since-worked per pillar (strength, mobility)
- [x] For single-focus, it chooses the stalest pillar; it biases toward mobility when `profile.sitsLong` AND `requestedMinutes <= 10` AND strength is not strongly stale
- [x] For blend, it includes both pillars and weights time by relative staleness
- [x] With no history, it applies a documented default (mobility-first if `sitsLong`, else strength)
- [x] Unit tests cover: empty history, strength-stale, mobility-stale, sitsLong tie-break
- [x] Build and tests pass

**Validation Test:**

- **Setup:** Construct logs where strength was worked yesterday and mobility 6 days ago
- **Steps:**
  1. Request a 10-minute single-focus session
- **Expected Result:** The engine selects the mobility pillar (the stalest).
- **Failure Indicator:** It selects strength, or ignores the staleness signal.

#### US-C03: Movement-pattern focus (pipeline Step 3)

**Description:** As a user, I want variety across movement patterns so that I am not always doing the same thing.

**Acceptance Criteria:**

- [x] Within the chosen pillar, patterns (push/squat/hinge/core/mobility groups) are ranked by staleness
- [x] Yesterday's primary pattern is never repeated unless explicitly requested
- [x] Selection is deterministic for a given log history
- [x] Unit tests cover: stalest-pattern selection and the no-repeat-yesterday rule
- [x] Build and tests pass

**Validation Test:**

- **Setup:** Logs show push performed yesterday, squat stale 5 days
- **Steps:**
  1. Generate a strength single-focus session
- **Expected Result:** The session leads with squat, not push.
- **Failure Indicator:** Push is selected again, or pattern choice ignores staleness.

#### US-C04: Exercise pool filtering (pipeline Step 4)

**Description:** As a user, I want only safe, appropriate exercises offered so that I never get something above my level or against my injuries.

**Acceptance Criteria:**

- [x] Starting from the full library, the engine removes: `phase == strength` exercises when `user.phase == discipline`; exercises flagged for the user's injuries; difficulty above the user's level cap (beginner 1-2, intermediate 1-3, advanced 1-5); exercises skipped more than 3 times recently
- [x] All remaining exercises are bodyweight (`equipment == []`)
- [x] If filtering empties a needed pattern, it falls back to the safest available bodyweight option and records why
- [x] Unit tests cover each filter rule independently and the fallback
- [x] Build and tests pass

**Validation Test:**

- **Setup:** Beginner user in discipline phase with `injuries: ["knees"]`
- **Steps:**
  1. Run the filter over the full library
- **Expected Result:** No strength-phase exercises, no difficulty 3+ exercises, and no knee-flagged exercises remain in the pool.
- **Failure Indicator:** A gated exercise survives the filter, or the pool becomes empty without a fallback.

#### US-C05: Progression-chain selection (pipeline Step 5)

**Description:** As a user, I want the right exercise in each chain for my current ability so that I am always appropriately challenged.

**Acceptance Criteria:**

- [x] For each chosen pattern, the engine finds the user's current chain position from logged performance
- [x] It selects that exercise; if `advancementCriteria` are met from logs, it offers the next exercise in the chain
- [x] It avoids exercises used in the last 3 sessions for variety
- [x] A user with no history starts at the chain entry (`progressionOrder` 0)
- [x] Unit tests cover: entry position, advancement when criteria met, no-advancement when not met, no-repeat-last-3
- [x] Build and tests pass

**Validation Test:**

- **Setup:** Logs show the user cleared "3x15 clean reps" on knee push-ups (chain order 2)
- **Steps:**
  1. Generate a push-focused session
- **Expected Result:** The engine offers the next chain exercise (standard push-up) rather than repeating knee push-ups.
- **Failure Indicator:** It repeats the cleared exercise or skips ahead past an un-cleared tier.

#### US-C06: Adaptive Overload rep/set targets (pipeline Step 6)

**Description:** As a user, I want rep and set targets matched to what I have actually done so that the workout is challenging but never absurd.

**Acceptance Criteria:**

- [x] The engine pulls the user's logged capacity for the selected exercise and prescribes reps/sets at or just above demonstrated capacity (progressive)
- [x] It NEVER prescribes a fixed heroic number (e.g. "100 squats"); every target is capacity-relative
- [x] A `perceivedDifficulty` of `too_hard` last time reduces the next target; `too_easy` increases it (within one cycle)
- [x] For holds, the same logic applies to duration in seconds
- [x] With no prior capacity, it uses the exercise's `defaultReps`/`defaultDurationSeconds`
- [x] Unit tests cover: progressive bump, too_hard reduction, too_easy increase, default fallback, and absence of any fixed heroic number
- [x] Build and tests pass

**Validation Test:**

- **Setup:** Last log: 3x12 squats marked `too_hard`
- **Steps:**
  1. Generate the next session including squats
- **Expected Result:** The prescribed squat target is at or below 3x12 (eased), and is computed from capacity, not a constant.
- **Failure Indicator:** The target ignores the `too_hard` signal or equals a hardcoded number.

#### US-C07: Assembly and timing fit (pipeline Step 7)

**Description:** As a user, I want a session that opens with a warm-up and lands within a minute of my requested time so that it reliably fits my schedule.

**Acceptance Criteria:**

- [x] Every session opens with a warm-up; in a short mobility-led session the opening flow doubles as warm-up + training
- [x] Blocks are assembled per the Step 1 shape; sessions over 10 minutes end with a cooldown stretch
- [x] `totalTime = Σ(sets × estTimePerSet) + rests + transitions`; the engine trims or extends to land within ±1 minute of `requestedMinutes`
- [x] End-to-end generation latency is under 100ms on a modern device/simulator
- [x] Output is a fully-formed `Workout` ready to play
- [x] Unit tests assert: warm-up present, cooldown present only when >10 min, total time within ±1 min for 5/10/15/20/30, and a measured latency assertion
- [x] Build and tests pass

**Validation Test:**

- **Setup:** Intermediate user, some history, request 20 minutes
- **Steps:**
  1. Generate the session and sum the planned durations
  2. Measure generation time
- **Expected Result:** Session opens with a warm-up, closes with a cooldown, totals 19-21 minutes, and generates in under 100ms.
- **Failure Indicator:** No warm-up, total outside ±1 min, missing cooldown on a 20-min session, or latency over 100ms.

#### US-C08: Deterministic exercise swap

**Description:** As a user, I want to swap an exercise I dislike for an equivalent one so that I stay in control without breaking the session.

**Acceptance Criteria:**

- [x] Given a workout and a target exercise, the engine returns a substitute within the same pillar, movement pattern, and difficulty band, fitting the same time budget
- [x] The substitute is bodyweight and respects the user's injuries and phase
- [x] Substitution is deterministic and does not change total session time by more than the swapped slot's tolerance
- [x] If no valid substitute exists, it returns a clear "no alternative" result rather than an unsafe pick
- [x] Unit tests cover: valid swap within constraints, injury-respecting swap, and the no-alternative case
- [x] Build and tests pass

**Validation Test:**

- **Setup:** A generated session containing standard push-ups
- **Steps:**
  1. Request a swap on the push-up slot
- **Expected Result:** The engine returns another push-pattern strength exercise of similar difficulty that fits the same time slot.
- **Failure Indicator:** It returns a different pattern, a gated/injurious exercise, or blows the time budget.

---

### Epic D - Consistency & Phase

#### US-D01: Forgiving Consistency Score

**Description:** As a user, I want a score that rewards showing up and survives a missed day so that one slip never erases my progress.

**Acceptance Criteria:**

- [ ] `weeklyAdherence(week) = min(1, workoutsCompleted(week) / weeklyGoal)`; `score = weightedRollingAverage(weeklyAdherence, recentWeeks) × 100` with recent weeks weighted more
- [ ] A 5-minute session counts as a full "show up"
- [ ] A single missed week dents the score but never zeroes it
- [ ] `longestChain` is tracked and surfaced as an earned badge of pride; a broken chain reduces the chain counter but only dents the score
- [ ] All user-facing copy is identity-framed ("you're someone who moves"), never loss-framed
- [ ] Unit tests cover: empty history, a perfect run, a single miss (dent not zero), 5-min-counts-as-show-up, and rolling-window weighting
- [ ] Build and tests pass

**Validation Test:**

- **Setup:** 7 weeks at goal, then 1 missed week
- **Steps:**
  1. Compute the Consistency Score after the missed week
- **Expected Result:** The score drops modestly (single-digit to low-double-digit dent) and stays well above zero; `longestChain` reflects the prior 7-week run.
- **Failure Indicator:** The score resets to zero, or a 5-minute session fails to count.

#### US-D02: PhaseEvaluator (earned progression)

**Description:** As a user, I want to advance to the Strength Phase only when I have earned it so that strength is a real, honest milestone.

**Acceptance Criteria:**

- [ ] A user is in the Strength Phase only when BOTH hold: Consistency Score sustained above a threshold over a rolling window (e.g. >=80% over ~8 recent weeks) AND the user has cleared the entry tiers of the foundational chains (push, squat, hinge, core)
- [ ] The evaluator is deterministic and never user-selectable
- [ ] At MVP launch every user resolves to the Discipline Phase (no one has earned Strength yet)
- [ ] A perfectly consistent user who never advances her movements stays in Discipline, with the engine nudging her up the chains - never framed as failure
- [ ] Unit tests cover: consistent-but-not-competent stays Discipline, competent-but-not-consistent stays Discipline, both-met -> Strength, fresh user -> Discipline
- [ ] Build and tests pass

**Validation Test:**

- **Setup:** A user with 90% score over 8 weeks but who has cleared none of the entry chain tiers
- **Steps:**
  1. Run the PhaseEvaluator
- **Expected Result:** The user remains in the Discipline Phase (competence gate not met).
- **Failure Indicator:** The evaluator promotes the user on consistency alone.

---

### Epic E - Onboarding

#### US-E01: Minimal onboarding flow

**Description:** As a new user, I want a short setup so that I am working out within five minutes of opening the app.

**Acceptance Criteria:**

- [ ] Onboarding collects: display name + basic profile (age, sex, height, weight), fitness level, primary goal, "do you sit 6+ hours most days?", optional injuries, and first-session minutes
- [ ] Answers persist to the `User`/`UserProfile` and set `AppState.isOnboarded = true`
- [ ] On finish, the app routes straight into generating the first session
- [ ] Onboarding is skippable-minimal: no field beyond the above; total flow completable in under 2 minutes
- [ ] Uses `Theme` tokens, 56pt buttons, 44pt+ targets, supports Dynamic Type and VoiceOver
- [ ] Verify in iOS Simulator

**Validation Test:**

- **Setup:** Fresh install, not onboarded
- **Steps:**
  1. Launch the app and complete every onboarding screen
  2. Tap finish
- **Expected Result:** Profile is saved, `isOnboarded` flips true, and the app lands on a generated first session; the whole flow takes well under 5 minutes.
- **Failure Indicator:** A field is lost, the app does not route to a session, or onboarding re-appears on next launch.

---

### Epic F - Home Screen

#### US-F01: Home screen with auto-generated session and duration selector

**Description:** As a user, I want one clear action to start today's session so that I never have to browse or decide.

**Acceptance Criteria:**

- [ ] On open, if no session was generated today, the app auto-generates one using `typicalAvailableMinutes`
- [ ] The screen shows today's session preview, a duration selector, and quick-start buttons (5/10/15/20/30)
- [ ] Tapping a quick-start regenerates the session for that duration in under 100ms
- [ ] One primary "Start" action is visually dominant
- [ ] No XP, levels, or badges appear anywhere (deferred to Phase 2)
- [ ] Uses `Theme` tokens; verify in iOS Simulator

**Validation Test:**

- **Setup:** Onboarded user, no session generated today
- **Steps:**
  1. Open the app to the Home tab
  2. Tap the "15" quick-start button
- **Expected Result:** A session preview appears immediately on open; tapping 15 regenerates a ~15-minute session instantly; a single Start button is clearly primary.
- **Failure Indicator:** No session auto-generates, quick-start lags or fails, or any XP/badge UI is visible.

#### US-F02: Consistency Score display and template insight

**Description:** As a user, I want to see my Consistency Score and a helpful nudge so that I feel encouraged, never threatened.

**Acceptance Criteria:**

- [ ] Home surfaces the Consistency Score, identity-framed and forgiving in tone
- [ ] A template-based insight appears (e.g. a pillar-balance nudge such as "your hips have missed you - today leans mobility")
- [ ] No loss-framed or streak-threat copy anywhere
- [ ] Insight text is generated from templates, not an LLM
- [ ] Verify in iOS Simulator

**Validation Test:**

- **Setup:** User with a mid-range score and mobility stale
- **Steps:**
  1. Open the Home tab and read the score area and insight
- **Expected Result:** The score shows with encouraging identity-framed copy; the insight nudges toward the stale pillar.
- **Failure Indicator:** Copy is loss-framed, the score is missing, or the insight is generic/irrelevant.

---

### Epic G - Active Session

#### US-G01: Active session player

**Description:** As a user, I want a clear, large-target player with a demo for each exercise so that I can follow along hands-free.

**Acceptance Criteria:**

- [ ] Plays the workout block-by-block with an auto-playing exercise demo (Lottie; static frame acceptable for mobility holds at MVP)
- [ ] Large touch targets (>=60pt on this screen), set tracking, and elapsed time always visible
- [ ] Advancing through sets and exercises is one tap
- [ ] Respects Reduce Motion (falls back to a static image)
- [ ] Verify in iOS Simulator

**Validation Test:**

- **Setup:** A generated 10-minute session
- **Steps:**
  1. Start the session and advance through two exercises
- **Expected Result:** Each exercise shows a demo, sets are trackable with one tap, and elapsed time is continuously visible.
- **Failure Indicator:** Demo missing, targets too small, elapsed time hidden, or advancing requires multiple taps.

#### US-G02: Rest timer with haptics

**Description:** As a user, I want a rest timer that buzzes when rest ends so that I keep moving without watching the clock.

**Acceptance Criteria:**

- [ ] Between sets/exercises a rest timer counts down the prescribed rest
- [ ] A haptic fires when rest ends (with an audio alternative for accessibility)
- [ ] The user can skip rest or add time
- [ ] Timer keeps correct time if the app is briefly backgrounded
- [ ] Verify in iOS Simulator (haptics verified on device where possible)

**Validation Test:**

- **Setup:** A session with rest periods
- **Steps:**
  1. Complete a set and let the rest timer run out
  2. Complete another set and tap skip-rest
- **Expected Result:** The timer counts down and fires a haptic/audio cue at zero; skip immediately advances.
- **Failure Indicator:** No cue at zero, timer drifts, or skip does nothing.

#### US-G03: In-session swap

**Description:** As a user, I want to swap an exercise mid-session so that a movement I dislike or cannot do does not derail me.

**Acceptance Criteria:**

- [ ] A swap control on each exercise calls the deterministic swap engine (US-C08)
- [ ] The substitute replaces the slot in place, preserving session timing
- [ ] If no alternative exists, the UI shows a clear, friendly message
- [ ] Verify in iOS Simulator

**Validation Test:**

- **Setup:** An active session on a push-up exercise
- **Steps:**
  1. Tap swap on the push-up slot
- **Expected Result:** The exercise is replaced in place with an equivalent push-pattern movement and the session continues seamlessly.
- **Failure Indicator:** Swap changes the session length noticeably, picks an invalid exercise, or crashes.

#### US-G04: Background and resume

**Description:** As a user, I want my session to survive an interruption so that a phone call does not cost me my workout.

**Acceptance Criteria:**

- [ ] Session progress (current block, set, elapsed, rest state) is preserved when the app is backgrounded or interrupted
- [ ] On return, the session resumes exactly where it left off
- [ ] If the app is killed mid-session, returning offers to resume or discard
- [ ] Verify in iOS Simulator

**Validation Test:**

- **Setup:** A session in progress at exercise 3, set 2
- **Steps:**
  1. Background the app for 30 seconds, then reopen
  2. Force-quit mid-session, relaunch
- **Expected Result:** Reopening resumes at exercise 3 set 2 with correct elapsed time; relaunch after kill offers resume-or-discard.
- **Failure Indicator:** Progress is lost, elapsed time resets, or the session restarts from the top.

---

### Epic H - Post-Session

#### US-H01: Post-session summary and log write

**Description:** As a user, I want a satisfying summary at the end so that I feel the win and my work is recorded.

**Acceptance Criteria:**

- [ ] A completion celebration plays on finish
- [ ] A template-based session summary shows duration, exercises done, and muscle/mobility coverage (which pillars/patterns were trained)
- [ ] A `WorkoutLog` is written to CoreData capturing per-exercise completed sets, pillar, pattern, shape, and skipped flags
- [ ] The Consistency Score updates immediately to reflect the completed session
- [ ] Verify in iOS Simulator

**Validation Test:**

- **Setup:** Finish a generated 15-minute blend session
- **Steps:**
  1. Complete the session
  2. Inspect the post-session screen, then check stored logs
- **Expected Result:** Celebration shows, summary lists the trained pillars/patterns, a matching `WorkoutLog` is persisted, and the score ticks up.
- **Failure Indicator:** No log written, coverage wrong, or score not updated.

#### US-H02: Rating and perceived difficulty feedback

**Description:** As a user, I want to tell the app how the session felt so that the next one adjusts to me.

**Acceptance Criteria:**

- [ ] The post-session screen captures a rating and a `perceivedDifficulty` (too_easy / just_right / too_hard)
- [ ] The values persist on the `WorkoutLog` and feed Adaptive Overload (US-C06)
- [ ] The very next generated session reflects the feedback within one cycle (too_hard eases, too_easy intensifies)
- [ ] Verify in iOS Simulator

**Validation Test:**

- **Setup:** Finish a session and mark it `too_hard`
- **Steps:**
  1. Submit the rating + `too_hard`
  2. Generate the next session for the same pattern
- **Expected Result:** The feedback persists on the log and the next session's targets for that pattern are eased.
- **Failure Indicator:** Feedback is not stored or the next session ignores it.

---

### Epic I - Progress Tab

#### US-I01: Session calendar and Consistency Score trend

**Description:** As a user, I want to see my history and score over time so that I can feel my consistency building.

**Acceptance Criteria:**

- [ ] A calendar marks days with completed sessions
- [ ] A Swift Charts line/area shows Consistency Score over recent weeks
- [ ] Both read from persisted logs and update after a new session
- [ ] Empty state shown for a brand-new user with no history
- [ ] Verify in iOS Simulator

**Validation Test:**

- **Setup:** A user with sessions on 3 days this week
- **Steps:**
  1. Open the Progress tab
- **Expected Result:** The 3 days are marked on the calendar and the score trend renders; a new user sees a friendly empty state instead of a blank chart.
- **Failure Indicator:** Marks missing, chart fails to render, or empty state is a blank screen.

#### US-I02: Pillar balance, chain position, personal bests, and premium gating

**Description:** As a user, I want to see my balance, progress, and bests so that I understand where I stand, with deeper analytics offered as premium.

**Acceptance Criteria:**

- [ ] Shows a pillar-balance view (strength vs mobility), current progression-chain positions, and personal bests
- [ ] Basic views are free; deeper analytics surfaces are visibly gated behind a premium lock state (wired to US-J04)
- [ ] Tapping a gated surface routes to the paywall
- [ ] Verify in iOS Simulator

**Validation Test:**

- **Setup:** A free user with some history
- **Steps:**
  1. Open the Progress tab and tap a locked analytics card
- **Expected Result:** Free views (pillar balance, chain position, bests) render; the locked card shows a clear premium state and tapping it opens the paywall.
- **Failure Indicator:** Premium content is freely accessible, or the lock leads nowhere.

---

### Epic J - Apple-Native Integrations

#### US-J01: Sign in with Apple

**Description:** As a user, I want to sign in with Apple so that my identity and data are private and portable across my devices.

**Acceptance Criteria:**

- [ ] Sign in with Apple is the identity mechanism; the credential is stored securely (Keychain)
- [ ] A signed-in user id ties the `User` record and enables CloudKit sync (US-J02)
- [ ] Sign-out and re-sign-in restore the same profile
- [ ] Handles the no-account / cancelled-auth path gracefully
- [ ] Verify in iOS Simulator (full flow verified on device where possible)

**Validation Test:**

- **Setup:** Fresh install
- **Steps:**
  1. Complete Sign in with Apple
  2. Sign out and sign back in
- **Expected Result:** Authentication succeeds, the profile persists across sign-out/in, and a cancelled auth returns to a safe state.
- **Failure Indicator:** Credential not stored, profile lost on re-auth, or a cancel crashes the flow.

#### US-J02: CloudKit sync and backup

**Description:** As a user, I want my data backed up and synced so that I keep my history across devices and reinstalls.

**Acceptance Criteria:**

- [ ] `NSPersistentCloudKitContainer` syncs `CDUser` and `CDWorkoutLog` to the user's private CloudKit database
- [ ] Data created offline syncs when connectivity returns
- [ ] Basic conflict handling uses a documented last-writer-wins or merge policy
- [ ] The core loop remains fully functional with no iCloud account (local-only fallback)
- [ ] Verify in iOS Simulator with two simulators / device + simulator on the same iCloud account where possible

**Validation Test:**

- **Setup:** Signed-in user on an iCloud account, a second device/simulator on the same account
- **Steps:**
  1. Complete a session on device A
  2. Open the app on device B
- **Expected Result:** The session and updated score appear on device B after sync; with no iCloud account, the app still works locally.
- **Failure Indicator:** Data does not sync, a conflict corrupts data, or the no-account path blocks the core loop.

#### US-J03: HealthKit write

**Description:** As a user, I want my workouts recorded in Health so that FitSnack contributes to my overall activity picture.

**Acceptance Criteria:**

- [ ] On first need, the app requests HealthKit write authorization with a clear purpose string
- [ ] On session completion, it writes a workout sample (type, duration, active energy estimated from MET × weight × duration)
- [ ] HealthKit data stays on-device (no upload)
- [ ] Denied permission degrades gracefully; the core loop is unaffected
- [ ] Verify in iOS Simulator (HealthKit write verified on device where possible)

**Validation Test:**

- **Setup:** A completed session, HealthKit authorized
- **Steps:**
  1. Finish a session
  2. Open Apple Health and find the workout
- **Expected Result:** A workout with sensible duration and energy appears in Health; denying permission still lets the session complete and log locally.
- **Failure Indicator:** No Health entry, wrong duration/energy, or a denial blocks completion.

#### US-J04: StoreKit 2 subscriptions and paywall

**Description:** As a user, I want unlimited free workouts and an optional premium tier so that the core loop is never gated but I can pay for depth.

**Acceptance Criteria:**

- [ ] StoreKit 2 products configured: monthly (~$7.99) and annual (~$59.99) premium, each with a 14-day trial
- [ ] Free tier is unlimited workouts forever, full ~38-movement library, Consistency Score, weekly goal, basic history - never gated
- [ ] Premium unlocks the depth layer (full analytics; Strength Phase and advanced programming flagged for later; equipment variants and AI later)
- [ ] A paywall screen presents the value of depth, both plans, the trial, and a Restore Purchases action
- [ ] Subscription state persists and updates entitlement gates (e.g. US-I02 locks)
- [ ] Verify in iOS Simulator using a StoreKit configuration file

**Validation Test:**

- **Setup:** StoreKit configuration file with both products, sandbox
- **Steps:**
  1. Generate and complete several workouts as a free user
  2. Open the paywall, start the trial, then check a gated analytics surface
  3. Use Restore Purchases
- **Expected Result:** Free workouts are never blocked; starting the trial unlocks the gated surfaces; Restore re-applies entitlement.
- **Failure Indicator:** A free workout is gated, the trial does not unlock depth, or Restore fails to recover entitlement.

---

## Functional Requirements

**Data & persistence**

- FR-1: The system must define canonical domain enums and Codable structs shared by the engine, persistence, and views.
- FR-2: The system must persist `User` and `WorkoutLog` data in CoreData via `NSPersistentCloudKitContainer`.
- FR-3: The system must bundle a ~38-movement, all-bodyweight exercise library and validate its integrity at load.

**Engine**

- FR-4: The system must select session shape from requested minutes (5-10 single-focus, 15 blend-light, 20-30 blend-full).
- FR-5: The system must choose pillars and movement patterns by staleness, biasing short sessions toward mobility for users who sit 6+ hours.
- FR-6: The system must filter the exercise pool by phase, injuries, difficulty level, skip frequency, and the Zero-Equipment Floor.
- FR-7: The system must select exercises by progression-chain position and avoid the last 3 sessions' exercises.
- FR-8: The system must prescribe capacity-relative rep/set/hold targets and never a fixed heroic number.
- FR-9: The system must assemble a session that always opens with a warm-up, adds a cooldown when over 10 minutes, and lands within ±1 minute of the requested time.
- FR-10: The system must generate a complete session in under 100ms, fully offline.
- FR-11: The system must support deterministic in-session swaps within pillar, pattern, difficulty, and time budget.

**Consistency, phase, and feedback**

- FR-12: The system must compute a forgiving rolling Consistency Score where a single miss dents but never zeroes, and a 5-minute session counts as a full show-up.
- FR-13: The system must evaluate phase deterministically, requiring both sustained consistency and demonstrated competence for the Strength Phase, with all MVP users in the Discipline Phase.
- FR-14: The system must capture post-session rating and perceived difficulty and feed them into Adaptive Overload within one cycle.

**UI**

- FR-15: The system must onboard a new user in under 5 minutes and route straight into a first session.
- FR-16: The Home screen must auto-generate today's session, offer quick-start durations, and surface the Consistency Score and a template insight, with no XP/badges.
- FR-17: The Active Session screen must provide large targets, an auto-playing demo, set tracking, a haptic rest timer, swap, and background/resume.
- FR-18: The Post-Session screen must celebrate completion, summarize coverage, write a `WorkoutLog`, and update the score.
- FR-19: The Progress tab must show a session calendar, score trend, pillar balance, chain position, and personal bests, with deeper analytics gated behind premium.

**Apple integrations**

- FR-20: The system must use Sign in with Apple for identity.
- FR-21: The system must sync data to the user's private CloudKit database and function locally with no iCloud account.
- FR-22: The system must write completed workouts to HealthKit on-device, degrading gracefully if denied.
- FR-23: The system must offer free unlimited workouts and StoreKit 2 premium subscriptions (monthly/annual, 14-day trial) gating only depth, with a paywall and Restore Purchases.

## Non-Goals (Out of Scope)

- No LLM/AI calls of any kind (post-workout summaries and weekly narratives are template-based in MVP; AI is deferred to Phase 2).
- No custom backend or server.
- No XP, levels, or badges.
- No social features, leaderboards, or challenges.
- No equipment-based exercises or equipment variants (Zero-Equipment Floor; equipment is Strength-Phase, Phase 2).
- No full Strength-Phase catalog or advanced programming content at launch.
- No detailed/animated onboarding flow or full animation sourcing (minimal onboarding only; Lottie demos for launch movements).
- No Android, widgets, Live Activities, or Apple Watch.
- No real Strength-Phase users at launch (PhaseEvaluator present, but all users resolve to Discipline).

## Design Considerations

- Use design tokens exclusively: `Theme.Colors`, `Theme.Typography`, `Theme.Spacing`. Never hardcode colors, fonts, or spacing.
- Button height 56pt, card corner radius 16pt, minimum touch target 44pt (60pt on workout screens).
- The Home screen has exactly one dominant action: start today's session.
- All consistency copy is identity-framed ("you're someone who moves"), never loss-framed or streak-threatening.
- Mobility is presented as co-primary, never as a warm-up; the first onboarding session is recommended (Phase 2 design) to be a short Movement Practice reset for same-day relief.
- Accessibility throughout: VoiceOver, Dynamic Type, Reduce Motion (static demo fallback), haptics with an audio alternative.

## Technical Considerations

- **Architecture:** MVVM + protocol-based services. Views read services via `@Environment(\.services)`; view models are `@Observable` (Observation framework), never `ObservableObject`. All storage/external methods are `async throws`. Swapping a mock for a real service is a one-line change in `ServiceContainer`.
- **Persistence:** CoreData with `NSPersistentCloudKitContainer`; domain structs are plain Codable, converted to/from CoreData entities; complex nested fields stored as JSON-encoded `Data`. (This follows v5 literally; it diverges from the prior SwiftData scaffold, which is reference only.)
- **Engine:** pure Swift, deterministic, on-device, no network, no LLM; latency target <100ms; every step independently unit-tested.
- **Build:** xcodegen-generated project from `project.yml`; iOS 17.0+, Swift 5.9, Xcode 16.3; bundle id `com.fitsnack.app`; app size target <50MB.
- **Apple stack:** Sign in with Apple, CloudKit (private DB), HealthKit (write, on-device), StoreKit 2 (free unlimited core + premium depth). No hosting cost; Apple Developer account ($99/yr) required.
- **Testing:** every new piece of logic must have unit tests; engine, Consistency Score, PhaseEvaluator, filtering, and progression are all covered. UI stories are verified in the iOS Simulator.

## Success Metrics

From v5 section 7. North Star: Weekly Active Exercisers (users completing >=1 session/week).

| Metric | Month 3 | Month 6 |
|--------|---------|---------|
| Onboarding -> 1st session | 60% | 70% |
| Day 7 retention | 20% | 25% |
| Day 30 retention | 10% | 15% |
| Weekly Active Exercisers | 35% of installs | 40% |
| Free -> Paid | 4% | 7% |
| Session completion (started -> finished) | >=80% | >=80% |
| Generation latency (on-device) | <100ms | <100ms |

## Open Questions

- What exact Consistency Score thresholds and rolling-window length should the PhaseEvaluator use (v5 suggests >=80% over ~8 weeks)? Needs a concrete constant before US-D02.
- ~~What is the precise rep/set bump curve for Adaptive Overload (percentage step per cycle, caps)?~~ Resolved in US-C06: per-cycle multipliers are progressive 1.05 / too-easy 1.15 / too-hard 0.85, clamped to per-set rails (reps 3-50, holds 10-180s) and set bounds 1-4 (default 3), all tunable constants in `AdaptiveOverload`.
- For CloudKit conflicts, is last-writer-wins acceptable for MVP, or is a field-level merge needed for `WorkoutLog`s?
- Which Lottie source/library is used for the launch demos (sourcing is deferred to Phase 2, but the player in US-G01 needs a placeholder strategy)?
- Should the first onboarding session be hardcoded as a Movement Practice reset in MVP, or left to the engine? (v5 recommends the reset but defers detailed onboarding to Phase 2.)

---

*Generated by the `prd` skill from `FitSnack-PRD-v5.md`. Mark each story's acceptance-criteria checkboxes `[x]` as it is completed, so this PRD doubles as a live progress tracker.*
