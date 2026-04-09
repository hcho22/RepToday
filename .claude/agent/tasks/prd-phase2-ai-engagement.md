# PRD: FitSnack Phase 2 — AI Intelligence Layer + Engagement

**Version:** 1.0
**Date:** April 8, 2026
**Timeline:** Weeks 9-16 (8 weeks)
**Status:** Draft

---

## 1. Introduction / Overview

Phase 1 MVP delivered the core workout loop: a deterministic rule-based engine generating personalized 5-30 minute workouts from a 30-exercise database, with full gamification (XP, levels, badges, streaks), SwiftData persistence, HealthKit write, notifications, and StoreKit 2 subscriptions.

Phase 2 layers three categories of improvements on top of the validated workout loop:

1. **AI Intelligence** — Claude API integration for post-workout summaries, weekly progress reports, and next-workout reasoning via a secure backend proxy
2. **Engine v2** — Expanded 142-exercise calisthenics database, 12 progression chains, duration-based workout templates, movement pattern day rotation, staleness scoring, and preference learning
3. **Engagement Features** — Shareable workout cards, streak freezes, streak saver micro-workouts, muscle radar chart, progression chain visualization, Lottie exercise animations, personalized notifications, and HealthKit reading

The engine overhaul and AI layer transform FitSnack from a functional workout generator into an intelligent fitness companion that adapts, explains, and motivates.

---

## 2. Goals

- Expand exercise database from 30 to 142 calisthenics-focused exercises with progression tracking
- Deliver AI-powered personalized insights after every workout and weekly via Claude API
- Implement a secure backend proxy (Cloudflare Worker / Vercel Edge Function) for all AI API calls
- Refactor the workout generation engine to support duration-based templates, movement pattern rotation, and progression chain integration
- Add engagement mechanics (streak freezes, shareable cards) to improve retention
- Enhance progress visualization with muscle radar charts and progression chain tracking
- Integrate HealthKit reading (heart rate, weight) and personalized notification timing
- Maintain < 100ms on-device workout generation latency
- Keep AI costs under $360/month at 1,000 active users

---

## 3. User Stories

### Work Stream A: Data Model & Exercise Database

---

#### US-A01: Expand Movement Pattern Enum

**Description:** As a developer, I need granular movement pattern categories so the engine can implement push/pull/squat/hinge day rotation per the PRD v2 algorithm.

**Acceptance Criteria:**

- [x] `MovementPattern` enum in `Models/Enums/MovementPattern.swift` has 15 cases: `pushHorizontal`, `pushVertical`, `pullVertical`, `pullHorizontal`, `squat`, `hinge`, `lunge`, `carry`, `coreAntiExtension`, `coreFlexion`, `coreRotation`, `coreCompression`, `cardio`, `mobility`, `primal`
- [x] Each case has `displayName` computed property
- [x] Each case has `focusGroup` computed property mapping to high-level category: `.push`, `.pull`, `.squat`, `.hinge`, `.core`, `.cardio`, `.mobility`
- [x] Custom `init(from decoder:)` maps old raw values to new cases (`"push"` -> `.pushHorizontal`, `"core"` -> `.coreFlexion`, `"plank"` -> `.coreAntiExtension`, `"rotation"` -> `.coreRotation`, `"carry"` -> `.carry`, `"lunge"` -> `.lunge`, `"cardio"` -> `.cardio`)
- [x] All existing saved workouts in SwiftData still decode correctly after migration
- [x] Typecheck passes

**Validation Test:**

- **Setup:** App with Phase 1 data (saved workouts using old `push`, `pull`, `core` enum values)
- **Steps:**
  1. Build and run Phase 2 app
  2. Open Progress tab -> workout history
  3. Verify old workouts display correctly
  4. Generate a new workout and verify it uses new movement patterns
- **Expected Result:** Old workouts decode without crash. New workouts use granular patterns like `pushHorizontal`.
- **Failure Indicator:** Crash on decode, missing workout history, or `nil` movement patterns

---

#### US-A02: Expand Equipment Enum

**Description:** As a user, I want to select calisthenics-specific equipment (parallettes, rings, dip bars) during onboarding and in settings so my workouts match what I actually have.

**Acceptance Criteria:**

- [x] `Equipment` enum in `Models/Enums/Equipment.swift` adds 10 new cases: `parallettes`, `rings`, `dipBars`, `elevatedSurface`, `wall`, `slidersOrTowel`, `anchorPoint`, `bandOrStick`, `stepOrStairs`, `boxOrPlatform`
- [x] Old cases (`dumbbells`, `kettlebell`, `yogaMat`, `jumpRope`, `foamRoller`, `stabilityBall`) retained for backward compatibility but hidden from selection UI
- [x] Each new case has `displayName` and `icon` (SF Symbol)
- [x] `EquipmentSelectionView.swift` shows new equipment chips, hides deprecated ones
- [x] `EquipmentEditView.swift` shows new equipment chips, hides deprecated ones
- [x] Existing user profiles with old equipment values decode correctly
- [x] Typecheck passes

**Validation Test:**

- **Setup:** User profile saved with Phase 1 equipment (e.g., `dumbbells`, `pullUpBar`)
- **Steps:**
  1. Launch Phase 2 app
  2. Open Settings -> Equipment
  3. Verify old equipment still shows as selected
  4. Select new equipment (parallettes, rings)
  5. Save and reopen
- **Expected Result:** Old equipment preserved. New equipment types visible and selectable. Deprecated types not shown in selection UI but still stored in profile.
- **Failure Indicator:** Profile decode crash, old equipment lost, or deprecated types still appearing in picker

---

#### US-A03: Expand Exercise Model

**Description:** As a developer, I need the `Exercise` model to support progression chain fields so the engine can track advancement and select exercises at the user's level.

**Acceptance Criteria:**

- [x] `Exercise` struct in `Models/Exercise.swift` adds 5 optional fields:
  - `progressionChainId: String?` — e.g., `"chain_horizontal_push"`
  - `progressionOrder: Int?` — position in chain (1 = easiest)
  - `advancementCriteria: String?` — e.g., `"3x15 clean reps"`
  - `athleteSource: [String]?` — e.g., `["heria", "israetel"]`
  - `apartmentFriendly: Bool?` — defaults to `true` when absent
- [x] Custom `init(from decoder:)` provides defaults for missing keys (backward-compatible with existing 30-exercise JSON)
- [x] Existing `Exercises.json` (30 exercises) decodes without error even without new fields
- [x] Typecheck passes

**Validation Test:**

- **Setup:** Existing 30-exercise `Exercises.json` without new fields
- **Steps:**
  1. Build app with new Exercise model
  2. Load exercises via `MockExerciseService`
  3. Access `progressionChainId`, `apartmentFriendly` on loaded exercises
- **Expected Result:** All 30 exercises load. New optional fields are `nil`/default. No decode errors.
- **Failure Indicator:** JSON decode failure or crash accessing new fields

---

#### US-A04: Expand MuscleGroup Enum

**Description:** As a developer, I need additional muscle group cases to accurately tag the 142-exercise database per PRD v2.

**Acceptance Criteria:**

- [x] `MuscleGroup` enum in `Models/Enums/MuscleGroup.swift` adds 4 cases: `wrists`, `rotatorCuff` (raw: `"rotator_cuff"`), `traps`, `erectors`
- [x] Each has a `displayName` computed property
- [x] Typecheck passes

**Validation Test:**

- **Setup:** Clean build
- **Steps:**
  1. Encode and decode each new case via `JSONEncoder`/`JSONDecoder`
- **Expected Result:** Round-trip succeeds for all new cases.
- **Failure Indicator:** Decode failure or raw value mismatch

---

#### US-A05: Expand Exercise Database to 142 Exercises

**Description:** As a user, I want a comprehensive calisthenics exercise library so my workouts have enough variety and cover all movement patterns across difficulty levels 1-5.

**Acceptance Criteria:**

- [x] `Resources/Exercises.json` contains exactly 142 exercises
- [x] All 30 existing exercises migrated to new `MovementPattern` raw values
- [x] 112 new exercises added with all fields populated: `id`, `name`, `displayName`, `description`, `instructions`, `commonMistakes`, `muscleGroups`, `movementPattern`, `category`, `difficulty`, `equipment`, `isUnilateral`, `defaultReps`/`defaultDurationSeconds`, `defaultSets`, `restBetweenSetsSeconds`, `estimatedTimePerSetSeconds`, `regressions`, `progressions`, `metValue`, `tags`, `progressionChainId`, `progressionOrder`, `advancementCriteria`, `athleteSource`, `apartmentFriendly`
- [x] Coverage: at least 2 exercises per movement pattern per difficulty level (1-5)
- [x] Coverage: at least 85 bodyweight-only exercises (equipment = `["none"]`)
- [ ] All `progressionChainId` references match a valid chain in `ProgressionChains.json` (US-A06)
- [x] All `equipment` values are valid `Equipment` enum cases
- [x] All `movementPattern` values are valid `MovementPattern` enum cases
- [x] All `muscleGroups.primary` and `muscleGroups.secondary` values are valid `MuscleGroup` cases
- [x] Exercise categories follow PRD v2 Section 6.3 organization (Push Horizontal, Push Vertical, Pull, Squat, Hinge, Core, Cardio/Mobility/Primal)
- [x] `MockExerciseService` loads all 142 exercises successfully
- [x] Typecheck passes

**Validation Test:**

- **Setup:** Fresh build with expanded `Exercises.json`
- **Steps:**
  1. Run `ExerciseDatabaseTests` (new test file)
  2. Verify `MockExerciseService.getAllExercises().count == 142`
  3. Filter by equipment `[.none]` — verify >= 85 results
  4. Filter by each `MovementPattern` — verify >= 2 per difficulty level
  5. Verify all `progressionChainId` references are valid
- **Expected Result:** All 142 exercises load, all references valid, coverage requirements met.
- **Failure Indicator:** Decode errors, missing chain references, insufficient coverage

**Exercise Schema Example (new exercise):**

```json
{
  "id": "push_008",
  "name": "pseudo_planche_push_ups",
  "displayName": "Pseudo Planche Push-Ups",
  "description": "A push-up variation with hands positioned near the hips, leaning forward to load the shoulders and chest.",
  "instructions": [
    "Place hands by your hips with fingers pointing sideways or backward",
    "Lean forward until shoulders are well ahead of hands",
    "Lower chest toward the ground while maintaining the forward lean",
    "Push back up, keeping core engaged throughout"
  ],
  "commonMistakes": [
    "Not leaning far enough forward",
    "Letting hips sag",
    "Flaring elbows out wide"
  ],
  "muscleGroups": {
    "primary": ["shoulders", "chest"],
    "secondary": ["biceps", "core"]
  },
  "movementPattern": "push_horizontal",
  "category": "strength",
  "difficulty": 3,
  "equipment": ["none"],
  "isUnilateral": false,
  "defaultReps": 10,
  "defaultDurationSeconds": null,
  "defaultSets": 3,
  "restBetweenSetsSeconds": 60,
  "estimatedTimePerSetSeconds": 30,
  "regressions": ["push_006"],
  "progressions": ["push_011"],
  "metValue": 4.5,
  "tags": ["planche_prep", "shoulder_strength"],
  "progressionChainId": "chain_horizontal_push",
  "progressionOrder": 7,
  "advancementCriteria": "3x12 clean reps with forward lean past hands",
  "athleteSource": ["heria"],
  "apartmentFriendly": true
}
```

---

#### US-A06: Create Progression Chain Model and JSON

**Description:** As a user, I want to see my progression path for each movement pattern (e.g., wall push-ups -> standard -> diamond -> one-arm) so I know what to work toward and when I'm ready to advance.

**Acceptance Criteria:**

- [x] New model `Models/ProgressionChain.swift`:
  ```swift
  struct ProgressionChain: Codable, Identifiable {
      let id: String                     // e.g., "chain_horizontal_push"
      let name: String                   // e.g., "Horizontal Push"
      let description: String
      let movementPattern: MovementPattern
      let exerciseIds: [String]          // ordered easiest to hardest
      let levels: [ChainLevel]
      
      struct ChainLevel: Codable {
          let exerciseId: String
          let order: Int
          let advancementCriteria: String // e.g., "3x15 clean reps"
      }
  }
  ```
- [x] New resource `Resources/ProgressionChains.json` with 12 chains per PRD v2 Section 6.4:
  1. Horizontal Push, 2. Vertical Push, 3. Vertical Pull, 4. Horizontal Pull, 5. Squat, 6. Hinge, 7. Core Anti-Extension, 8. Core Dynamic, 9. Core Compression, 10. Front Lever, 11. Planche, 12. Primal Movement
- [x] Every `exerciseId` in every chain references a valid exercise in `Exercises.json`
- [x] New protocol `Services/Protocols/ProgressionServiceProtocol.swift`:
  ```swift
  protocol ProgressionServiceProtocol {
      func getAllChains() -> [ProgressionChain]
      func getChain(by id: String) -> ProgressionChain?
      func getUserLevel(for chainId: String) async throws -> Int
      func updateUserLevel(for chainId: String, level: Int) async throws
      func checkAdvancement(chainId: String, exerciseId: String, recentSets: [SetLog]) -> Bool
  }
  ```
- [x] New mock `Services/Mock/MockProgressionService.swift` — loads chains from bundled JSON, persists user levels in SwiftData via `SDUserProfile.progressionLevelsRaw`
- [x] Typecheck passes

**Validation Test:**

- **Setup:** Fresh build with `ProgressionChains.json` and expanded `Exercises.json`
- **Steps:**
  1. Load all 12 chains via `MockProgressionService`
  2. For each chain, verify every `exerciseId` resolves to a real exercise
  3. Set user level for `chain_horizontal_push` to 4
  4. Retrieve user level — verify it's 4
  5. Call `checkAdvancement` with mock `SetLog` data meeting criteria — verify returns `true`
- **Expected Result:** All chains load, all references valid, user level persists, advancement check works.
- **Failure Indicator:** Missing exercise references, level not persisting, false advancement result

---

#### US-A07: Create Workout Template Model and JSON

**Description:** As a developer, I need duration-based workout templates so the engine can generate structurally different workouts for 5, 10, 15, 20, 25, and 30-minute sessions per the PRD v2 algorithm.

**Acceptance Criteria:**

- [x] New model `Models/WorkoutTemplate.swift`:
  ```swift
  struct WorkoutTemplate: Codable, Identifiable {
      let id: String
      let durationMinutes: Int           // 5, 10, 15, 20, 25, 30
      let name: String                   // "Density", "Circuit", "Focused", etc.
      let warmupTimeSeconds: Int
      let cooldownTimeSeconds: Int
      let blockDefinitions: [BlockDefinition]
      
      struct BlockDefinition: Codable {
          let type: BlockType
          let exerciseCount: Int
          let sets: Int
          let workSeconds: Int?          // for timed exercises (HIIT, circuit)
          let restBetweenSetsSeconds: Int
          let restBetweenExercisesSeconds: Int
          let rounds: Int?
          let patternCount: Int          // how many movement patterns this block uses
      }
  }
  ```
- [x] New resource `Resources/WorkoutTemplates.json` with 6 templates matching PRD v2 Section 2.4:
  - 5-min Density: 1 pattern, 5 rounds x (40s work / 20s rest)
  - 10-min Circuit: 7-8 exercises, 45s/15s, 1 round
  - 15-min Focused: 2 patterns, 3-4 exercises, 3 sets each
  - 20-min Structured: 2-3 patterns, 4-5 exercises, 3 sets + cooldown
  - 25-min Superset: 3 patterns, supersets with 90s rest
  - 30-min Full: 3-4 supersets of opposing movements, 3 sets each
- [x] Warmup/cooldown times sum correctly per template
- [x] Total estimated time per template stays within the duration (validated via unit test)
- [x] Typecheck passes

**Validation Test:**

- **Setup:** Fresh build with `WorkoutTemplates.json`
- **Steps:**
  1. Decode all 6 templates from JSON
  2. For each template, compute: `warmupTimeSeconds + sum(block timing) + cooldownTimeSeconds`
  3. Verify total fits within `durationMinutes * 60` seconds (±30s tolerance)
- **Expected Result:** All 6 templates decode. Timing budgets are valid.
- **Failure Indicator:** Decode failure or timing exceeds requested duration

---

#### US-A08: Update SDUserProfile for Phase 2 Fields

**Description:** As a developer, I need the SwiftData user profile to store Phase 2 data (streak freezes, progression levels, exercise preferences, notification timing) so it persists across app launches.

**Acceptance Criteria:**

- [x] `SDUserProfile` in `Persistence/SwiftDataModels/SDUserProfile.swift` adds:
  - `streakFreezes: Int` — default `0`
  - `lastFreezeReplenishDate: Date?` — default `nil`
  - `progressionLevelsRaw: String` — base64-encoded JSON `[String: Int]`, default `""`
  - `exerciseSkipCountsRaw: String` — base64-encoded JSON `[String: Int]`, default `""`
  - `exerciseRatingsRaw: String` — base64-encoded JSON `[String: Int]`, default `""`
  - `preferredWorkoutTimeHour: Int?` — default `nil`
- [x] Helper methods to encode/decode each raw field (following existing `getBadges()`/`setBadges(_:)` pattern)
- [x] SwiftData lightweight migration succeeds when upgrading from Phase 1 schema (new properties with defaults)
- [x] `init(from:)` and `update(from:)` updated for new fields
- [x] Typecheck passes

**Validation Test:**

- **Setup:** Phase 1 app installed with existing user profile
- **Steps:**
  1. Install Phase 2 build over Phase 1
  2. Launch app
  3. Open Profile tab — verify profile loads
  4. Set streak freezes to 2, save, relaunch, verify persisted
- **Expected Result:** Migration succeeds silently. New fields default to 0/nil/empty. Profile intact.
- **Failure Indicator:** Crash on launch, profile data lost, or migration error

---

### Work Stream B: Workout Engine v2

---

#### US-B01: Refactor Workout Generation Engine into Modular Components

**Description:** As a developer, I need the monolithic `WorkoutGenerationEngine` refactored into focused modules so we can implement template-based generation, movement pattern rotation, staleness scoring, and preference learning without a tangled single file.

**Acceptance Criteria:**

- [x] New file `Services/Engine/ExerciseFilter.swift` — extracted and enhanced filtering logic:
  - Equipment filtering (existing)
  - Injury exclusion (existing)
  - Difficulty gating by fitness level: beginner=1-2, intermediate=1-3, advanced=1-5 (existing)
  - **NEW:** Skip-frequency filtering — remove exercises skipped > 3 times (reads from `SDUserProfile.exerciseSkipCountsRaw`)
  - **NEW:** Apartment-friendly filtering — when user preference set, remove exercises where `apartmentFriendly == false`
  - **NEW:** Rating boost — exercises rated 4-5 stars by user get sorted higher in selection (reads from `SDUserProfile.exerciseRatingsRaw`)
- [x] New file `Services/Engine/ExerciseSelector.swift`:
  - **NEW:** Staleness scoring — days since each movement pattern was last worked (from workout history)
  - **NEW:** Variety enforcement — don't repeat exercises from last 3 workouts
  - **NEW:** Progression chain integration — select exercise at user's current chain level
  - **NEW:** Auto-advancement detection — if `advancementCriteria` met based on recent `SetLog` data, flag for next level
- [x] New file `Services/Engine/MovementPatternRotation.swift`:
  - **NEW:** Day rotation: Push+Core (Day A) / Pull+Hinge (Day B) / Squat+Primal (Day C) / Full Body Circuit (Day D)
  - **NEW:** Selects pattern combo with highest staleness score
  - **NEW:** Never repeats yesterday's primary pattern unless only option
- [x] New file `Services/Engine/WorkoutAssembler.swift`:
  - **NEW:** Takes a `WorkoutTemplate` + selected exercises, assembles `WorkoutBlock` structures
  - **NEW:** Timing verification: `totalTime <= requestedDuration`
  - **NEW:** Overflow handling: remove last exercise or reduce sets if over budget
  - **NEW:** Underflow handling: add exercise from same pattern if under budget by > 2 min
- [x] `Services/WorkoutGenerationEngine.swift` refactored to a facade that orchestrates the 4 modules
- [x] Generate signature expanded: `func generate(duration: Int, profile: UserProfile, history: [Workout], progressionLevels: [String: Int], exercisePreferences: ExercisePreferences) -> Workout`
- [x] New struct `ExercisePreferences` with `skipCounts: [String: Int]` and `ratings: [String: Int]`
- [x] Workout generation still completes in < 100ms (on-device, no network)
- [x] All existing `WorkoutGenerationTests` updated to pass with new engine
- [x] Typecheck passes

**Validation Test:**

- **Setup:** App with 142 exercises loaded, user profile with mixed equipment, some workout history
- **Steps:**
  1. Generate a 5-min workout — verify Density template (single pattern, 5 rounds)
  2. Generate a 15-min workout — verify Focused template (2 patterns, 3 sets each)
  3. Generate a 30-min workout — verify Full template (supersets of opposing movements)
  4. Generate 3 workouts in a row — verify no exercise repeats across them
  5. Generate with apartment-friendly on — verify no jumping exercises
  6. Measure generation time — verify < 100ms
- **Expected Result:** Each duration produces the correct template structure. Exercises don't repeat across recent workouts. Filtering works. Fast.
- **Failure Indicator:** Wrong template for duration, repeated exercises, jumping exercises when apartment-friendly enabled, or > 100ms generation

---

#### US-B02: Enhanced Exercise Swap Algorithm

**Description:** As a user, I want to swap exercises with a reason so the app gives me an appropriate substitute and learns my preferences over time.

**Acceptance Criteria:**

- [x] `ExerciseSwapSheet.swift` updated with 5 swap reasons: "Too Hard", "Too Easy", "No Equipment", "It Hurts", "Don't Like It"
- [x] Swap logic in `MockWorkoutService.swapExercise()` enhanced:
  - Matches by `movementPattern` (not just `category`)
  - Matches by `progressionChainId` when possible
  - "Too Hard" -> pick regression (lower `progressionOrder` in same chain)
  - "Too Easy" -> pick progression (higher `progressionOrder`)
  - "It Hurts" -> exclude all exercises sharing same primary muscle group
  - "Don't Like It" -> log exercise ID to skip counts, pick different exercise same pattern
  - "No Equipment" -> pick exercise with equipment user has
  - Replacement cannot be already used in current workout
- [x] Swap reason stored in `SDUserProfile.exerciseSkipCountsRaw` (for "Don't Like It")
- [x] Recalculates timing and calories after swap
- [x] Typecheck passes

**Validation Test:**

- **Setup:** Active workout with a difficulty-3 push exercise that has regressions
- **Steps:**
  1. Tap Swap -> select "Too Hard"
  2. Verify replacement is an easier exercise (lower difficulty or `progressionOrder`)
  3. Tap Swap on another exercise -> select "Don't Like It"
  4. Generate a new workout next day
  5. Verify the "don't like" exercise doesn't appear
- **Expected Result:** Swap provides contextually appropriate replacement. Preferences persist and affect future generation.
- **Failure Indicator:** Same-difficulty replacement for "Too Hard", or disliked exercise reappears

---

#### US-B03: Update Exercise Display for New Exercises

**Description:** As a developer, I need the exercise display view updated with icons and movement pattern labels for the 112 new exercises.

**Acceptance Criteria:**

- [x] `ExerciseDisplayView.swift` — `exerciseIcons` dictionary expanded for all 142 exercises
- [x] `movementPatternFallbackIcon` updated for all 15 new movement pattern cases
- [x] Any exercise without a specific icon falls back to its movement pattern icon
- [x] Typecheck passes

**Validation Test:**

- **Setup:** Generate workout with new exercises (e.g., pseudo planche push-ups, cossack squats)
- **Steps:**
  1. Start workout
  2. Verify each exercise displays an icon (specific or fallback)
  3. No blank or missing icon states
- **Expected Result:** Every exercise shows an appropriate icon.
- **Failure Indicator:** Missing icon, crash, or blank exercise card

---

### Work Stream C: AI Service Integration

---

#### US-C01: Define AI Service Protocol and Mock

**Description:** As a developer, I need an AI service protocol and mock implementation so the app can display AI insights during development without requiring a live API.

**Acceptance Criteria:**

- [x] New `Services/Protocols/AIServiceProtocol.swift`:
  ```swift
  protocol AIServiceProtocol {
      func generatePostWorkoutSummary(
          workout: Workout, 
          userProfile: UserProfile, 
          recentHistory: [Workout]
      ) async throws -> String
      
      func generateWeeklyReport(
          workouts: [Workout], 
          userProfile: UserProfile, 
          stats: GamificationStats
      ) async throws -> String
      
      func generateNextWorkoutPreview(
          userProfile: UserProfile, 
          recentHistory: [Workout], 
          tomorrowsFocus: String
      ) async throws -> String
  }
  ```
- [x] New `Services/Mock/MockAIService.swift` — returns realistic template-based strings:
  - Post-workout: `"Great {duration}-minute {focusArea} session! You completed {exerciseCount} exercises targeting {primaryMuscles}."`
  - Weekly: `"This week you completed {count} workouts totaling {minutes} minutes..."`
  - Preview: `"Tomorrow's focus: {focus} because you haven't worked {muscles} in {days} days."`
- [x] Templates pull real data from the `Workout` / `UserProfile` parameters (not hardcoded)
- [x] Typecheck passes

**Validation Test:**

- **Setup:** Completed workout object with realistic data
- **Steps:**
  1. Call `MockAIService.generatePostWorkoutSummary(workout:userProfile:recentHistory:)`
  2. Verify returned string contains actual workout data (duration, exercise count)
  3. Verify string is 1-3 sentences
- **Expected Result:** Realistic, data-driven template string returned instantly.
- **Failure Indicator:** Generic/hardcoded text or crash

---

#### US-C02: Register AI and Progression Services in ServiceContainer

**Description:** As a developer, I need the new AI and Progression services wired into the dependency injection container so all views can access them.

**Acceptance Criteria:**

- [x] `ServiceContainer` in `DI/ServiceContainer.swift` adds:
  - `let ai: AIServiceProtocol`
  - `let progression: ProgressionServiceProtocol`
- [x] `init()` updated to accept both new services
- [x] `static func mock(modelContext:)` updated to create `MockAIService()` and `MockProgressionService(modelContext:)`
- [x] `FitSnackApp.swift` updated to pass new services
- [x] All existing view code that accesses `services` continues to work
- [x] Typecheck passes

**Validation Test:**

- **Setup:** Clean build
- **Steps:**
  1. Build and run app
  2. Verify app launches without crash
  3. Access `services.ai` and `services.progression` from a view
- **Expected Result:** Services accessible. No compile or runtime errors.
- **Failure Indicator:** Compile error or runtime crash on ServiceContainer init

---

#### US-C03: Build Backend Proxy for Claude API

**Description:** As a developer, I need a secure backend proxy (Cloudflare Worker or Vercel Edge Function) for Claude API calls so the API key never ships in the iOS binary.

**Acceptance Criteria:**

- [x] Backend proxy deployed (Cloudflare Worker or Vercel Edge Function) with:
  - `POST /api/ai/summary` — proxies to Claude Haiku for post-workout summaries
  - `POST /api/ai/weekly-report` — proxies to Claude Sonnet for weekly reports
  - `POST /api/ai/next-workout-preview` — proxies to Claude Haiku for next-workout reasoning
- [x] Proxy authenticates iOS client via a lightweight API key or JWT (not the Anthropic key)
- [x] Anthropic API key stored as environment variable on the proxy, never exposed to client
- [x] Rate limiting: max 10 summary requests/day per user, 1 weekly report/week per user
- [x] Proxy validates request body shape before forwarding
- [x] Proxy strips any PII beyond age, sex, weight, fitness level (no name, email, device ID)
- [x] HTTPS only
- [x] Returns graceful error response on timeout (> 10s) or API failure
- [x] Proxy code lives in `proxy/` directory at project root (separate from iOS app)

**Validation Test:**

- **Setup:** Proxy deployed to staging
- **Steps:**
  1. `curl -X POST https://proxy-url/api/ai/summary` with valid workout payload and client API key
  2. Verify 200 response with AI-generated text
  3. `curl` same endpoint without auth header
  4. Verify 401 response
  5. Send 11 requests in a row for same user
  6. Verify 11th request returns 429 (rate limited)
- **Expected Result:** Authenticated requests succeed. Unauthenticated rejected. Rate limits enforced.
- **Failure Indicator:** API key exposed in response headers, no rate limiting, or unauth requests succeed

---

#### US-C04: Create Real AI Service Implementation

**Description:** As a user, I want personalized AI-generated insights after each workout so I understand what I accomplished and what to focus on next.

**Acceptance Criteria:**

- [x] New `Services/AIService.swift`:
  - URLSession-based HTTP client calling backend proxy endpoints (US-C03)
  - Client API key stored in iOS Keychain via new `Services/APIKeyManager.swift`
  - Post-workout summary: calls `/api/ai/summary`, max 100 tokens
  - Weekly report: calls `/api/ai/weekly-report`, max 300 tokens
  - Next-workout preview: calls `/api/ai/next-workout-preview`, max 150 tokens
  - Error handling: timeout (10s), rate limiting (429), network failure — all fall back to template-based text from `MockAIService`
  - Response caching: summary cached in `SDWorkout` (avoid duplicate calls for same workout ID)
- [x] New `Services/AIPromptBuilder.swift`:
  - Constructs prompts from workout/profile data
  - Post-workout prompt includes: exercise names, sets/reps completed, muscle groups, duration, rating, difficulty, last 7 days summary
  - Weekly report prompt includes: all workouts from past 7 days, 30-day trends, streak, XP, level
  - Next-workout prompt includes: recent history, movement pattern staleness, user goals
  - PII sanitization: only sends age, sex, weight, fitness level (no name, email, userId)
- [x] New `Services/APIKeyManager.swift`:
  - Keychain Services wrapper for storing/retrieving client API key
  - Key set during onboarding or first AI feature access
- [x] Typecheck passes

**Validation Test:**

- **Setup:** Proxy running. API key stored in Keychain. Completed workout.
- **Steps:**
  1. Complete a workout
  2. Verify AI summary appears on WorkoutCompleteView (loading -> text)
  3. Open the same completed workout in history
  4. Verify cached summary displays instantly (no loading)
  5. Turn on airplane mode, complete another workout
  6. Verify template-based fallback text appears
- **Expected Result:** AI summary loads in < 5s. Cached on second view. Graceful fallback offline.
- **Failure Indicator:** Crash, infinite loading, no fallback, or API key visible in logs

---

#### US-C05: Wire AI Summary into Post-Workout Flow

**Description:** As a user, after completing a workout I want to see a personalized AI insight that tells me what went well and what to focus on next.

**Acceptance Criteria:**

- [x] `WorkoutViewModel` adds `aiSummary: String?` and `isGeneratingInsight: Bool` properties
- [x] After `completeWorkout()` is called, `generatePostWorkoutSummary()` is triggered asynchronously
- [x] `WorkoutCompleteView.swift` displays:
  - Loading skeleton while `isGeneratingInsight == true`
  - AI summary card below XP earned when ready
  - "AI" badge/label on the summary card
  - Fallback template text if AI fails or user is on free tier
- [x] Premium gating: AI summaries only for premium users; free users see template text
- [x] Typecheck passes

**Validation Test:**

- **Setup:** Premium user, proxy running
- **Steps:**
  1. Complete a workout, provide rating and difficulty
  2. See WorkoutCompleteView
  3. Verify loading indicator appears briefly
  4. Verify AI summary appears with "AI" badge
  5. Switch to free user account, repeat
  6. Verify template text appears instead
- **Expected Result:** Premium sees AI insight. Free sees template. No crash.
- **Failure Indicator:** No summary shown, crash, or free users getting AI text

---

#### US-C06: Wire AI into Home Screen Insights

**Description:** As a user, I want the home screen insight card to show AI-generated content — yesterday's workout recap, weekly report on Mondays, and tomorrow's workout reasoning.

**Acceptance Criteria:**

- [x] `HomeViewModel` — replace static `insightText` computed property with dynamic logic:
  1. If Monday morning: show weekly report (call `generateWeeklyReport()` once, cache)
  2. If last workout has AI summary: show cached summary
  3. If next workout preview available: show AI reasoning for tomorrow's focus
  4. Fallback: static template tips (existing behavior)
- [x] `AIInsightCard.swift` updated:
  - Loading state while AI generates
  - "AI Insight" label when content is AI-generated
  - Expandable for longer content (weekly reports ~150 words)
- [x] Weekly reports cached in `SDUserProfile` (don't regenerate on every app open)
- [x] Premium gating: AI insights for premium; free users see static tips
- [x] Typecheck passes

**Validation Test:**

- **Setup:** Monday morning, premium user, several workouts last week
- **Steps:**
  1. Open app
  2. Verify insight card shows "AI Insight" label
  3. Verify content references last week's workouts
  4. Close and reopen app
  5. Verify same content loads instantly (cached)
  6. Open app on Tuesday
  7. Verify insight shows last workout summary or next-workout preview
- **Expected Result:** Monday shows weekly report. Other days show contextual insight. Caching works.
- **Failure Indicator:** Stale content, repeated API calls, or generic tips for premium user

---

#### US-C07: Weekly Report View

**Description:** As a user, I want a dedicated weekly report screen in my progress tab that shows AI-generated narrative analysis of my training week.

**Acceptance Criteria:**

- [x] New `Views/Progress/WeeklyReportView.swift`:
  - Displays ~150 word AI narrative for the current/selected week
  - Shows report history (last 4 weeks) in a scrollable list
  - Each report card shows: week date range, workout count, total minutes, AI narrative
  - Loading state for first-time generation
  - Empty state if no workouts that week
- [x] Accessible from `ProgressTabView` via "Weekly Report" section/link
- [x] Accessible via push notification deep link (Monday morning notification)
- [x] Premium gating: premium only
- [x] Typecheck passes

**Validation Test:**

- **Setup:** Premium user with 4+ weeks of workout history
- **Steps:**
  1. Navigate to Progress tab -> Weekly Report
  2. Verify current week report displays
  3. Scroll down to see previous weeks
  4. Verify each week shows correct date range and workout count
  5. Tap Monday notification -> verify deep links to this view
- **Expected Result:** Reports render with correct data per week. Deep link works.
- **Failure Indicator:** Missing weeks, wrong date ranges, or broken deep link

---

### Work Stream D: Progress Visualization

---

#### US-D01: Muscle Balance Radar Chart

**Description:** As a user, I want a visual radar/spider chart showing my 30-day movement pattern balance so I can see which areas I'm neglecting.

**Acceptance Criteria:**

- [ ] New `Views/Progress/MuscleRadarChart.swift`:
  - Swift Charts radar/spider chart (iOS 17+)
  - 7 axes: Push, Pull, Squat, Hinge, Core, Cardio, Mobility
  - Data: aggregate movement pattern frequency from last 30 days of workout history (using `MovementPattern.focusGroup`)
  - Normalized values (0-100%) so the shape is meaningful
  - Color-coded: current month in brand color, target/ideal distribution as light overlay
- [ ] `ProgressViewModel` adds `movementPatternFrequency: [String: Int]` computed from workout history
- [ ] `ProgressTabView` adds "Muscle Balance" section with the radar chart
- [ ] Chart updates when new workouts are completed
- [ ] Typecheck passes

**Validation Test:**

- **Setup:** User with 2 weeks of workouts emphasizing push/core, minimal pull
- **Steps:**
  1. Navigate to Progress tab
  2. Verify radar chart visible in "Muscle Balance" section
  3. Verify Push and Core axes are largest
  4. Verify Pull axis is noticeably smaller
  5. Complete a pull workout, return to progress tab
  6. Verify Pull axis grows
- **Expected Result:** Chart accurately reflects workout distribution. Updates after new workouts.
- **Failure Indicator:** All axes equal, chart not updating, or crash

---

#### US-D02: Progression Chain Visualization

**Description:** As a user, I want to see my current level in each of the 12 progression chains so I know where I am on each movement path and what to aim for next.

**Acceptance Criteria:**

- [ ] New `Views/Progress/ProgressionChainView.swift`:
  - Shows all 12 chains as cards in a vertical scroll list
  - Each card shows: chain name, current exercise name, level X of Y, a mini progress bar
  - Tapping a card navigates to detail view
- [ ] New `Views/Progress/ProgressionChainDetailView.swift`:
  - Horizontal scrollable chain showing exercises from easiest to hardest
  - Completed levels: checkmark + green
  - Current level: highlighted + brand color
  - Locked levels: grayed out
  - Tapping any exercise shows: name, description, advancement criteria, how close user is (if data available)
- [ ] `ProgressTabView` adds "Progression Chains" section
- [ ] Data sourced from `ProgressionServiceProtocol.getUserLevel(for:)` and `getAllChains()`
- [ ] Typecheck passes

**Validation Test:**

- **Setup:** User at level 3 in horizontal push chain (standard push-ups), level 1 in pull
- **Steps:**
  1. Navigate to Progress -> Progression Chains
  2. Verify Horizontal Push card shows "Standard Push-Ups" as current, level 3/9
  3. Tap into detail
  4. Verify Wall Push-Ups and Incline Push-Ups are checkmarked
  5. Verify Standard Push-Ups is highlighted
  6. Verify Diamond Push-Ups and beyond are grayed/locked
  7. Tap Standard Push-Ups — see advancement criteria "3x15 clean reps"
- **Expected Result:** Chain accurately reflects user's level with correct visual states.
- **Failure Indicator:** Wrong level shown, incorrect exercise order, or missing detail

---

#### US-D03: Enhanced Personal Records

**Description:** As a user, I want to see per-exercise personal records (max push-up reps, longest plank hold) in addition to workout-level PRs, so I can track my strength gains.

**Acceptance Criteria:**

- [ ] New `Views/Progress/PersonalRecordsView.swift` — dedicated PR view:
  - Workout PRs: longest workout, most calories, longest streak, most exercises in one workout
  - Exercise PRs: per-exercise max reps or max duration (from `SetLog` data)
  - Each PR shows: value, exercise name, date achieved
  - Sorted by recency of achievement
- [ ] `ProgressViewModel` — `calculatePRs()` expanded to scan `SetLog` data for per-exercise maxes
- [ ] `ProgressTabView` — "Personal Records" section links to `PersonalRecordsView`
- [ ] Typecheck passes

**Validation Test:**

- **Setup:** User with 10+ completed workouts, varying exercises and set logs
- **Steps:**
  1. Navigate to Progress -> Personal Records
  2. Verify workout PRs display (longest, most calories, etc.)
  3. Verify exercise PRs display (e.g., "Push-Ups: 20 reps on Mar 20")
  4. Complete a workout with a new PR (e.g., 25 push-ups)
  5. Return to PRs — verify new record appears
- **Expected Result:** Both workout and exercise PRs shown. New records update immediately.
- **Failure Indicator:** Missing exercise PRs, stale data, or wrong dates

---

### Work Stream E: Engagement Features

---

#### US-E01: Streak Freezes

**Description:** As a premium user, I want streak freezes so a single missed week doesn't destroy my multi-week streak.

**Acceptance Criteria:**

- [ ] `Constants.swift` adds `StreakFreeze` namespace:
  - Free users: 0 freezes
  - Premium users: 2 freezes per month
  - Auto-replenish on 1st of each month
  - A freeze preserves the streak for 1 week where goal was not met
- [ ] `Constants.Streak.calculateWeeklyStreak()` updated: when walking backwards and a week doesn't meet goal, check available freezes -> consume one -> continue counting
- [ ] `SDUserProfile` fields used: `streakFreezes`, `lastFreezeReplenishDate`
- [ ] `UserServiceProtocol` adds: `useStreakFreeze() async throws`, `getAvailableFreezes() async throws -> Int`
- [ ] UI: streak freeze count shown on `HomeView` near `StreakBadge` (e.g., "2 freezes available")
- [ ] UI: Settings shows streak freeze count and next replenish date
- [ ] Premium gating: only premium users get freezes
- [ ] Typecheck passes

**Validation Test:**

- **Setup:** Premium user with 4-week streak, 2 available freezes
- **Steps:**
  1. Simulate a week with 0 workouts (miss goal)
  2. Open app the following week
  3. Verify streak shows 4 (not reset to 0) — freeze auto-consumed
  4. Verify available freezes decreased to 1
  5. Simulate another missed week
  6. Verify streak preserved, freezes now 0
  7. Simulate a third missed week
  8. Verify streak resets to 0 (no freezes left)
  9. On the 1st of next month, verify freezes replenish to 2
- **Expected Result:** Freezes protect streak. Auto-consumed. Replenish monthly. Streak breaks when no freezes.
- **Failure Indicator:** Streak resets despite available freezes, or freezes don't replenish

---

#### US-E02: Streak Saver Micro-Workouts

**Description:** As a user, I want a Sunday evening notification and home screen banner when I'm 1 workout short of my weekly goal, offering a quick 5-minute "streak saver" workout.

**Acceptance Criteria:**

- [ ] `NotificationServiceProtocol` adds `scheduleStreakSaverCheck() async throws`
- [ ] `NotificationService` implements: check on Sunday at 6 PM if `workoutsThisWeek == weeklyGoal - 1`. If so, send local notification: "You're 1 workout away from keeping your streak! Tap for a quick 5-minute session."
- [ ] `HomeViewModel` adds `showStreakSaver: Bool` — true when Sunday + workoutsThisWeek == goal - 1
- [ ] `HomeView` shows a prominent "Streak Saver" banner card when `showStreakSaver == true`:
  - "Keep your streak alive! Quick 5-minute workout"
  - Tap -> generates and starts a 5-minute workout (standard engine flow)
- [ ] After completing the streak saver workout, banner disappears and weekly goal is met
- [ ] Notification deep links to HomeView
- [ ] Typecheck passes

**Validation Test:**

- **Setup:** User with weekly goal of 3, completed 2 workouts this week. It's Sunday.
- **Steps:**
  1. Open app on Sunday
  2. Verify "Streak Saver" banner appears on HomeView
  3. Tap banner
  4. Verify 5-minute workout generates
  5. Complete the workout
  6. Verify banner disappears and weekly count shows 3/3
- **Expected Result:** Banner appears at right time. Generates correct workout. Disappears after completion.
- **Failure Indicator:** Banner appears when not needed, generates wrong duration, or persists after completion

---

#### US-E03: Shareable Workout Cards

**Description:** As a user, I want to share a visual workout summary card to social media after completing a workout.

**Acceptance Criteria:**

- [ ] New `Services/ShareService.swift`:
  - Uses SwiftUI `ImageRenderer` (iOS 16+) to render workout card as `UIImage`
  - `func generateShareCard(workout: Workout, stats: GamificationStats) -> UIImage?`
- [ ] New `Views/Workout/ShareWorkoutCardView.swift` — the SwiftUI view rendered as image:
  - Workout duration, exercise count, calories burned
  - Muscle groups worked (icons)
  - Streak count, XP earned
  - FitSnack branding (logo, app name)
  - Gradient background using brand colors
  - Card dimensions: 1080x1920 (Instagram story) or 1080x1080 (square post)
- [ ] `WorkoutCompleteView.swift` adds "Share" button that:
  1. Renders the card via `ShareService`
  2. Presents `UIActivityViewController` with the image
- [ ] Premium gating consideration: free users get watermarked card, premium users get clean card
- [ ] Typecheck passes

**Validation Test:**

- **Setup:** Completed workout with rating
- **Steps:**
  1. Tap "Share" on WorkoutCompleteView
  2. Verify share sheet appears with workout card image
  3. Verify card shows correct workout data (duration, exercises, calories, streak)
  4. Save to photos and verify image quality
- **Expected Result:** Shareable card renders with correct data. Share sheet works. Image is high quality.
- **Failure Indicator:** Blank image, wrong data, share sheet doesn't appear, or low-res output

---

#### US-E04: Lottie Exercise Animation Framework

**Description:** As a user, I want to see animated exercise demonstrations during my workout so I understand proper form.

**Acceptance Criteria:**

- [ ] `project.yml` adds `lottie-ios` SPM dependency (latest stable version)
- [ ] New `Components/ExerciseDemoView.swift`:
  - Wrapper around Lottie `LottieAnimationView`
  - Loads exercise-specific Lottie JSON by `exerciseId` from `Resources/Animations/`
  - Loops animation continuously
  - Falls back to SF Symbol icon when animation file not found
  - Shows loading state while animation loads
- [ ] New directory `Resources/Animations/` — placeholder for Lottie JSON files (asset creation is a design task)
- [ ] `ExerciseDisplayView.swift` — replace static SF Symbol icon area with `ExerciseDemoView` component
- [ ] Animation file naming convention: `{exercise_id}.json` (e.g., `push_004.json`)
- [ ] Graceful behavior when no animation files exist (pure fallback mode)
- [ ] Typecheck passes

**Validation Test:**

- **Setup:** App built with Lottie dependency, 1-2 sample animation files in `Resources/Animations/`
- **Steps:**
  1. Generate workout containing an exercise with animation file
  2. Start workout — verify Lottie animation plays and loops
  3. Navigate to exercise without animation file
  4. Verify SF Symbol fallback icon displays
  5. Verify no crash or blank state
- **Expected Result:** Animations play when available. Fallback works when not. No performance issues.
- **Failure Indicator:** Crash loading Lottie, blank exercise card, or no fallback icon

---

#### US-E05: Paywall Optimization

**Description:** As a product owner, I want the paywall updated to highlight Phase 2 premium features (AI insights, streak freezes) to improve conversion.

**Acceptance Criteria:**

- [ ] `PaywallView.swift` updated:
  - Add "AI-Powered Insights" as premium feature with icon and description
  - Add "Streak Freezes" as premium feature with icon and description
  - Add "Progression Tracking" as premium feature
  - Show sample AI insight text with blur overlay (teaser for non-premium)
  - Features listed in order of perceived value
- [ ] Premium feature gates verified:
  - AI summaries: premium only (free gets template text)
  - AI weekly reports: premium only
  - Streak freezes: premium only (free gets 0)
  - Shareable cards: free gets watermark, premium gets clean
- [ ] Typecheck passes

**Validation Test:**

- **Setup:** Non-premium user
- **Steps:**
  1. Trigger paywall (e.g., tap on blurred AI insight)
  2. Verify "AI-Powered Insights" listed as feature
  3. Verify "Streak Freezes" listed as feature
  4. Verify sample AI text visible behind blur
  5. Purchase premium, dismiss paywall
  6. Verify AI insights now visible without blur
- **Expected Result:** Paywall showcases Phase 2 features. Premium unlocks them.
- **Failure Indicator:** Missing features on paywall, no blur teaser, or premium gates not enforced

---

### Work Stream F: Platform Integration

---

#### US-F01: HealthKit Read (Heart Rate, Weight)

**Description:** As a user, I want the app to read my weight and heart rate from Apple Health so my profile stays accurate and my progress insights include heart rate trends.

**Acceptance Criteria:**

- [ ] `HealthKitServiceProtocol` adds:
  - `func readLatestWeight() async throws -> Double?` (kg)
  - `func readLatestHeartRate() async throws -> Double?` (bpm)
  - `func readAverageRestingHeartRate(days: Int) async throws -> Double?`
- [ ] `HealthKitService.swift`:
  - Expand `requestAuthorization()` to include read types: `HKQuantityType(.bodyMass)`, `HKQuantityType(.heartRate)`, `HKQuantityType(.restingHeartRate)`
  - Implement read methods using `HKSampleQuery` / `HKStatisticsQuery`
- [ ] `MockHealthKitService.swift` — add mock implementations returning `nil`
- [ ] `project.yml` — update `NSHealthShareUsageDescription` to mention heart rate and weight reading
- [ ] Wire into Profile: auto-update `weightKg` in user profile when HealthKit weight changes (with user permission toggle)
- [ ] Wire into Progress: show resting heart rate trend in ProgressTabView (optional section)
- [ ] Typecheck passes

**Validation Test:**

- **Setup:** Simulator with Health data (or device with Apple Health data)
- **Steps:**
  1. Grant HealthKit read permissions
  2. Navigate to Profile
  3. Verify weight auto-populated from HealthKit (if available)
  4. Log weight in Apple Health app
  5. Return to FitSnack — verify weight updated
- **Expected Result:** Weight syncs from HealthKit. Heart rate data accessible.
- **Failure Indicator:** Permission prompt missing, weight not syncing, or crash on HealthKit query

---

#### US-F02: Personalized Notification Timing

**Description:** As a user, I want my daily workout reminder sent at the time I usually exercise, not a fixed time, so it's more relevant.

**Acceptance Criteria:**

- [ ] `NotificationServiceProtocol` adds `schedulePersonalizedReminder(basedOnHistory workoutTimes: [Date]) async throws`
- [ ] `NotificationService.swift` implements:
  - Analyze last 14 days of workout start times
  - Find most common hour (mode calculation)
  - Schedule daily reminder 30 minutes before that time
  - If < 5 data points: fall back to current fixed-time schedule (user-set or default 8 AM)
  - Recalculate weekly (not on every workout)
- [ ] `MockNotificationService.swift` — no-op implementation
- [ ] `HomeViewModel.loadData()` — after loading workout history, call personalized scheduler
- [ ] `SDUserProfile.preferredWorkoutTimeHour` stores computed optimal hour
- [ ] Typecheck passes

**Validation Test:**

- **Setup:** User with 10 workouts, most started around 7 AM
- **Steps:**
  1. Check scheduled notifications
  2. Verify daily reminder scheduled for ~6:30 AM (30 min before mode)
  3. Complete 5 workouts at 6 PM over next week
  4. Verify reminder shifts to ~5:30 PM after recalculation
- **Expected Result:** Reminder time adapts to workout patterns. Recalculates periodically.
- **Failure Indicator:** Fixed time regardless of history, or recalculates too frequently

---

## 4. Functional Requirements

### Data Model & Database
- FR-01: `MovementPattern` enum must support 15 granular pattern types with backward-compatible decoding
- FR-02: `Equipment` enum must support 14+ equipment types including calisthenics equipment
- FR-03: `Exercise` model must include progression chain fields (`progressionChainId`, `progressionOrder`, `advancementCriteria`, `athleteSource`, `apartmentFriendly`)
- FR-04: `Exercises.json` must contain exactly 142 exercises with complete metadata
- FR-05: `ProgressionChains.json` must define 12 chains with valid exercise references
- FR-06: `WorkoutTemplates.json` must define 6 duration-based templates (5/10/15/20/25/30 min)
- FR-07: `SDUserProfile` must persist streak freezes, progression levels, exercise preferences, and notification timing

### Engine v2
- FR-08: Workout generation must select template based on requested duration
- FR-09: Engine must implement movement pattern day rotation (Push+Core / Pull+Hinge / Squat+Primal / Full Body)
- FR-10: Engine must calculate staleness scores per movement pattern from workout history
- FR-11: Engine must filter exercises by skip frequency (> 3 skips = excluded) and boost exercises rated 4-5
- FR-12: Engine must support apartment-friendly filtering
- FR-13: Engine must select exercises at user's current progression chain level
- FR-14: Engine must detect when advancement criteria are met and flag for next level
- FR-15: Workout generation latency must remain < 100ms on-device
- FR-16: Exercise swap must match by movement pattern and progression chain, with reason-based behavior

### AI Integration
- FR-17: Backend proxy must handle all Claude API calls (client never contacts Anthropic directly)
- FR-18: Post-workout AI summary must be 2-3 sentences generated by Claude Haiku
- FR-19: Weekly AI report must be ~150 words generated by Claude Sonnet
- FR-20: Next-workout AI preview must explain tomorrow's focus using workout history context
- FR-21: AI responses must be cached to avoid duplicate API calls
- FR-22: AI must gracefully fall back to template-based text on failure/timeout
- FR-23: AI prompts must not include PII beyond age, sex, weight, and fitness level
- FR-24: AI features must be gated to premium subscribers only
- FR-25: Rate limiting: max 10 summaries/day, 1 weekly report/week per user

### Engagement
- FR-26: Premium users receive 2 streak freezes per month, auto-replenished on 1st
- FR-27: Streak calculation must consume available freezes before breaking streak
- FR-28: Streak saver notification sent Sunday 6 PM when 1 workout short of weekly goal
- FR-29: Shareable workout card rendered as image via `ImageRenderer` with workout data + branding
- FR-30: Lottie animations load per exercise ID with SF Symbol fallback

### Platform
- FR-31: HealthKit read must support weight, heart rate, and resting heart rate queries
- FR-32: Notification timing must adapt based on user's actual workout start times (mode of last 14 days)

---

## 5. Non-Goals (Out of Scope)

- No backend API server (beyond the lightweight AI proxy) — full backend is Phase 3
- No user authentication changes (Apple Sign In / email unchanged)
- No social features (friends, leaderboard, group challenges) — Phase 3
- No AI voice coaching or TTS — Phase 4
- No computer vision form checking — Phase 4
- No Apple Watch companion app — Phase 4
- No A/B testing framework — Phase 3
- No analytics integration (Mixpanel/Amplitude) — Phase 3
- No iOS widget or Dynamic Island — Phase 3
- No CloudKit sync — deferred until backend exists
- No video-based exercise demos (Lottie only in Phase 2)
- No creating the 50 Lottie animation asset files (design task — code framework only)
- No exercise database content changes beyond what PRD v2 Section 6 specifies

---

## 6. Design Considerations

### UI Components to Reuse
- `FitSnackCard` — for radar chart, chain cards, weekly report cards, streak saver banner
- `PrimaryButton` / `SecondaryButton` — for share button, streak saver CTA
- `ProgressRing` — for chain level progress visualization
- `XPProgressBar` — for chain advancement progress
- `StreakBadge` — update to show freeze count
- `LoadingWorkoutView` — reuse skeleton pattern for AI loading states
- `Theme.Colors`, `Theme.Typography`, `Theme.Spacing` — all new UI must use design tokens

### New UI Patterns
- **Radar chart**: Custom Swift Charts implementation; reference Apple's Chart documentation for custom marks
- **Progression chain**: Horizontal scroll with snap-to-center behavior
- **AI loading state**: Shimmer/skeleton text placeholder while AI generates
- **Shareable card**: Designed for Instagram stories (1080x1920) and square posts (1080x1080)
- **Streak freeze indicator**: Small snowflake icon near flame streak badge

### Accessibility
- All new views must support VoiceOver
- Radar chart must have VoiceOver alternative (text summary of balance)
- Progression chain must be navigable via VoiceOver
- AI summary text must support Dynamic Type
- Share card must include alt-text for screen readers

---

## 7. Technical Considerations

### Dependencies
- **lottie-ios** (SPM) — exercise animation framework
- **Backend proxy** (Cloudflare Worker or Vercel Edge Function) — AI API proxy

### Architecture Decisions
- Engine modularization: 4 files under `Services/Engine/` vs flat in `Services/`. Recommendation: `Services/Engine/` subdirectory for clarity, but referenced via `WorkoutGenerationEngine` facade
- AI proxy architecture: Cloudflare Worker (lowest latency, generous free tier, edge deployment) recommended over Vercel Edge Function
- Progression level storage: base64-encoded JSON in `SDUserProfile` (consistent with existing `badgesRaw` pattern) vs. separate SwiftData model. Recommendation: base64 JSON for simplicity

### Migration Risks
- **MovementPattern enum change**: Old raw values (`push`, `core`, `plank`) in saved `SDWorkout` JSON. Mitigation: custom decoder with old->new mapping
- **Equipment enum expansion**: Old profile data may reference deprecated cases. Mitigation: keep old cases, just hide from UI
- **SDUserProfile new fields**: SwiftData lightweight migration should handle new stored properties with defaults. Test explicitly.
- **Exercises.json format change**: Old format (30 exercises, no chain fields) must remain decodable via optional fields

### Performance
- Workout generation: must remain < 100ms with 142 exercises (vs 30 currently). Profile the filter/sort/select pipeline
- Exercise DB load: 142 exercises from JSON. Cache in memory after first load (existing pattern in `MockExerciseService`)
- AI response time: 2-5 seconds typical. Show loading state immediately. Timeout at 10 seconds.
- Radar chart: aggregate 30 days of workout data. Pre-compute on `loadData()`, not on every render

### Cost Projections (AI)
| Feature | Model | Cost/Call | Calls/User/Week | 1K Users/Month |
|---------|-------|-----------|------------------|----------------|
| Post-workout summary | Haiku | $0.01-0.03 | 3 | $120-360 |
| Weekly report | Sonnet | $0.05-0.10 | 1 | $200-400 |
| Next-workout preview | Haiku | $0.01-0.02 | 3 | $120-240 |
| **Total** | | | | **$440-1,000** |

Mitigations: aggressive caching, free tier uses templates only, rate limiting

---

## 8. Success Metrics

| Metric | Target |
|--------|--------|
| Exercise database: total exercises | 142 |
| Workout generation latency (on-device) | < 100ms |
| AI summary generation latency | < 5 seconds |
| AI summary user satisfaction | >= 3.5/5 rating |
| Exercise swap rate (should decrease with better generation) | < 12% (from < 15%) |
| Workout difficulty "Just Right" rating | >= 70% (from >= 65%) |
| Premium conversion (paywall with AI features) | >= 8% |
| Weekly report engagement (premium users) | >= 40% open rate |
| Streak freeze usage (premium users) | >= 1 freeze used/quarter |
| Share card usage | >= 5% of completed workouts |
| Day 7 retention (Phase 2) | >= 25% |
| Day 30 retention (Phase 2) | >= 15% |
| AI cost per 1,000 active users/month | < $1,000 |

---

## 9. Open Questions

1. **AI proxy hosting**: Cloudflare Worker vs Vercel Edge Function — which does the team have existing infrastructure/expertise with?
2. **API key provisioning**: How does the iOS client receive its proxy API key? Bundled at build time? Fetched on first launch? Tied to Apple Sign In?
3. **Progression auto-advancement**: Should advancement happen automatically when criteria are met, or should the user confirm ("You're ready for Diamond Push-Ups! Try them?")?
4. **Streak freeze UX**: Should freezes be consumed automatically when a week is missed, or should the user manually activate a freeze before the week ends?
5. **Lottie asset pipeline**: Who creates the 50 Lottie animation files? Is there a budget for a designer/animator? What's the fallback timeline if animations aren't ready?
6. **Exercise database review**: Should a fitness professional review the 142 exercises for accuracy before shipping, or is the PRD v2 source material (Heria, Israetel, Strength Side) sufficient?
7. **AI content moderation**: Should AI-generated summaries pass through a content filter before display, or is Claude's built-in safety sufficient?
8. **Radar chart library**: Custom Swift Charts implementation or use a third-party radar chart library (e.g., SwiftUICharts)?

---

*End of PRD — Phase 2: AI Intelligence Layer + Engagement*
